module host_interface #(
    parameter int ADDRESS_WIDTH = cwrupio_pkg::IMEM_ADDR_WIDTH,
    parameter int PIN_COUNT = 4 // logical pins P0-P3
)(
    input logic clk,
    input logic rst_n,

    // host link: SPI target (host MCU is the controller), mode 0, MSB first
    // configuration port only, never connected to the protocol pins P0-P3
    // clk must be at least 4x host_sck; CS low to first SCK rise >= 3 clk cycles
    input logic host_sck,
    input logic host_cs_n,
    input logic host_mosi,
    output logic host_miso,

    // sequencer
    input logic busy,
    input logic done,
    input logic fault,
    output logic start, // 1-cycle pulse

    // tx/rx shift registers
    output logic [cwrupio_pkg::DATA_WIDTH-1:0] tx_data,
    input logic [cwrupio_pkg::DATA_WIDTH-1:0] rx_data,

    // instruction memory write port
    output logic imem_write_enable,
    output logic [ADDRESS_WIDTH-1:0] imem_write_addr,
    output logic [cwrupio_pkg::INSTRUCTION_WIDTH-1:0] imem_write_data,

    // pin control
    output logic [PIN_COUNT-1:0] pin_dir // 1 = output, 0 = input
);

    // register map: command byte = {rw, 3'b000, address[3:0]}, rw = 1 for write
    localparam logic [3:0] REG_CTRL = 4'h0; // W: bit0 start, bit1 reset load pointer
    localparam logic [3:0] REG_STATUS = 4'h1; // R: {5'b0, fault, done, busy}
    localparam logic [3:0] REG_TX_DATA = 4'h2; // R/W: byte for LOAD_TX
    localparam logic [3:0] REG_RX_DATA = 4'h3; // R: byte from SAMPLE
    localparam logic [3:0] REG_IMEM = 4'h4; // W: low byte, high byte, auto-increment
    localparam logic [3:0] REG_PIN_DIR = 4'h5; // R/W: pin direction

    // ---------------------------------------------------------------
    // Synchronizers and edge detect (all host link inputs sampled by clk)
    // ---------------------------------------------------------------
    logic [2:0] sck_sync;
    logic [1:0] cs_n_sync;
    logic [1:0] mosi_sync;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sck_sync <= '0;
            cs_n_sync <= 2'b11;
            mosi_sync <= '0;
        end 
        else begin
            sck_sync <= {sck_sync[1:0], host_sck};
            cs_n_sync <= {cs_n_sync[0], host_cs_n};
            mosi_sync <= {mosi_sync[0], host_mosi};
        end
    end

    logic cs_active;
    logic sck_rise;
    logic mosi_bit;

    assign cs_active = !cs_n_sync[1];
    assign sck_rise = cs_active && (sck_sync[2:1] == 2'b01);
    assign mosi_bit = mosi_sync[1];

    // ---------------------------------------------------------------
    // Byte receiver
    // ---------------------------------------------------------------
    logic [2:0] bit_count;
    logic [cwrupio_pkg::DATA_WIDTH-2:0] shift_in; // first 7 bits of the byte
    logic [cwrupio_pkg::DATA_WIDTH-1:0] rx_byte;
    logic byte_valid; // 1-cycle pulse when a full byte arrives
    logic first_byte; // next byte is the command byte

    assign rx_byte = {shift_in, mosi_bit};

    always_ff @(posedge clk) begin
        if (!rst_n || !cs_active) begin
            bit_count <= '0;
            shift_in <= '0;
        end 
        else if (sck_rise) begin
            bit_count <= bit_count + 1'b1;
            shift_in <= rx_byte[cwrupio_pkg::DATA_WIDTH-2:0];
        end
    end

    assign byte_valid = sck_rise && (bit_count == 3'd7);

    // ---------------------------------------------------------------
    // Command decode
    // ---------------------------------------------------------------
    logic cmd_write;
    logic [3:0] cmd_addr;
    logic data_write; // write strobe for a data byte

    always_ff @(posedge clk) begin
        if (!rst_n || !cs_active) begin
            first_byte <= 1'b1;
            cmd_write <= 1'b0;
            cmd_addr <= '0;
        end 
        else if (byte_valid && first_byte) begin
            first_byte <= 1'b0;
            cmd_write <= rx_byte[7];
            cmd_addr <= rx_byte[3:0];
        end
    end

    assign data_write = byte_valid && !first_byte && cmd_write;

    // ---------------------------------------------------------------
    // Registers written by the host
    // ---------------------------------------------------------------
    logic imem_high_phase; // 0 = next IMEM byte is the low byte
    logic [cwrupio_pkg::DATA_WIDTH-1:0] imem_low_byte;

    // the high byte goes straight to memory with the stored low byte (no data register)
    assign imem_write_enable = data_write && (cmd_addr == REG_IMEM) && !busy && imem_high_phase;
    assign imem_write_data = {rx_byte, imem_low_byte};

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            start <= 1'b0;
            tx_data <= '0;
            pin_dir <= '0; // all pins are inputs after reset
            imem_write_addr <= '0;
            imem_high_phase <= 1'b0;
            imem_low_byte <= '0;
        end 
        else begin
            start <= 1'b0;

            // pointer moves after each instruction write (same edge as the write)
            if (imem_write_enable) begin
                imem_write_addr <= imem_write_addr + 1'b1;
            end

            if (data_write) begin
                case (cmd_addr)
                    REG_CTRL: begin
                        start <= rx_byte[0];
                        if (rx_byte[1]) begin
                            imem_write_addr <= '0;
                            imem_high_phase <= 1'b0;
                        end
                    end
                    REG_TX_DATA: begin
                        tx_data <= rx_byte;
                    end
                    REG_IMEM: begin
                        if (!busy) begin // no program changes while running
                            if (!imem_high_phase) begin
                                imem_low_byte <= rx_byte;
                                imem_high_phase <= 1'b1;
                            end 
                            else begin
                                imem_high_phase <= 1'b0; // write happens this cycle
                            end
                        end
                    end
                    REG_PIN_DIR: begin
                        pin_dir <= rx_byte[PIN_COUNT-1:0];
                    end
                    default: begin
                        // read-only or unused address: ignore
                    end
                endcase
            end
        end
    end

    // ---------------------------------------------------------------
    // Read data and MISO shifter
    // ---------------------------------------------------------------
    logic [cwrupio_pkg::DATA_WIDTH-1:0] status_byte;
    logic [cwrupio_pkg::DATA_WIDTH-1:0] read_byte;
    logic [cwrupio_pkg::DATA_WIDTH-1:0] shift_out;
    logic [3:0] read_addr;
    logic cs_start; // first clk cycle with CS active

    assign status_byte = {5'b0, fault, done, busy};
    assign cs_start = (cs_n_sync == 2'b10); // older sample high, newer sample low

    // at the end of the command byte, cmd_addr is not updated yet, so use rx_byte
    assign read_addr = first_byte ? rx_byte[3:0] : cmd_addr;

    always_comb begin
        case (read_addr)
            REG_STATUS: begin
                read_byte = status_byte;
            end
            REG_TX_DATA: begin
                read_byte = tx_data;
            end
            REG_RX_DATA: begin
                read_byte = rx_data;
            end
            REG_PIN_DIR: begin
                read_byte = {{(cwrupio_pkg::DATA_WIDTH-PIN_COUNT){1'b0}}, pin_dir};
            end
            default: begin
                read_byte = '0;
            end
        endcase
    end

    // mode 0: host samples MISO on the rising edge, so the next bit is put on MISO
    // right after each detected rising edge (gives the host almost 1 full SCK period)
    // during the command byte, MISO returns the status byte
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            shift_out <= '0;
        end 
        else if (cs_start) begin
            shift_out <= status_byte;
        end 
        else if (sck_rise) begin
            if (bit_count == 3'd7) begin
                shift_out <= read_byte; // next byte starts
            end 
            else begin
                shift_out <= {shift_out[cwrupio_pkg::DATA_WIDTH-2:0], 1'b0};
            end
        end
    end

    assign host_miso = cs_active ? shift_out[cwrupio_pkg::DATA_WIDTH-1] : 1'b0;

endmodule
