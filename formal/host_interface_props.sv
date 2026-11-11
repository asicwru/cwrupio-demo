// Formal properties for host_interface, attached with bind so the RTL stays untouched.
// The solver drives the SPI pins (host_sck/cs_n/mosi) and busy/done/fault freely.
module host_interface_props #(
    parameter int ADDRESS_WIDTH = cwrupio_pkg::IMEM_ADDR_WIDTH,
    parameter int PIN_COUNT = 4
)(
    input logic                                      clk,
    input logic                                      rst_n,
    input logic                                      host_sck,
    input logic                                      host_cs_n,
    input logic                                      host_mosi,
    input logic                                      host_miso,
    input logic                                      busy,
    input logic                                      done,
    input logic                                      fault,
    input logic                                      start,
    input logic [cwrupio_pkg::DATA_WIDTH-1:0]        tx_data,
    input logic [cwrupio_pkg::DATA_WIDTH-1:0]        rx_data,
    input logic                                      imem_write_enable,
    input logic [ADDRESS_WIDTH-1:0]                  imem_write_addr,
    input logic [cwrupio_pkg::INSTRUCTION_WIDTH-1:0] imem_write_data,
    input logic [PIN_COUNT-1:0]                      pin_dir,
    // internal signals
    input logic                                      cs_active,
    input logic                                      sck_rise,
    input logic [2:0]                                bit_count,
    input logic                                      first_byte,
    input logic                                      data_write,
    input logic [3:0]                                cmd_addr,
    input logic [cwrupio_pkg::DATA_WIDTH-1:0]        rx_byte,
    input logic                                      imem_high_phase,
    input logic [cwrupio_pkg::DATA_WIDTH-1:0]        imem_low_byte
);
    localparam logic [3:0] REG_CTRL    = 4'h0;
    localparam logic [3:0] REG_TX_DATA = 4'h2;
    localparam logic [3:0] REG_IMEM    = 4'h4;
    localparam logic [3:0] REG_PIN_DIR = 4'h5;

    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;

    // Start in reset
    always_comb if (!f_past_valid) assume (!rst_n);

    logic f_ctrl_write, f_imem_write, f_ptr_reset;
    assign f_ctrl_write = data_write && cmd_addr == REG_CTRL;
    assign f_imem_write = data_write && cmd_addr == REG_IMEM;
    assign f_ptr_reset  = f_ctrl_write && rx_byte[1];

    // Combinational rules
    always_comb begin
        if (!cs_active) begin
            assert (host_miso == 1'b0);          // MISO idles low when not selected
            assert (!sck_rise && !data_write);   // nothing happens without chip select
        end
        assert (!(data_write && first_byte));    // the command byte is never treated as data
        assert (imem_write_enable == (f_imem_write && !busy && imem_high_phase));
        assert (!(imem_write_enable && busy));   // program can't change while running
        assert (imem_write_data == {rx_byte, imem_low_byte}); // {high byte, low byte}
    end

    // Register update rules
    always_ff @(posedge clk) begin
        if (f_past_valid) begin
            if (!$past(rst_n)) begin
                assert (!start && tx_data == '0 && pin_dir == '0);
                assert (imem_write_addr == '0 && !imem_high_phase);
            end else begin
                // start: a 1-cycle pulse, only from writing 1 to CTRL bit 0
                assert (start == ($past(f_ctrl_write) && $past(rx_byte[0])));
                if (start) assert (!$past(start));

                // tx_data and pin_dir change only when the host writes them
                if ($past(data_write) && $past(cmd_addr) == REG_TX_DATA)
                    assert (tx_data == $past(rx_byte));
                else
                    assert (tx_data == $past(tx_data));

                if ($past(data_write) && $past(cmd_addr) == REG_PIN_DIR)
                    assert (pin_dir == $past(rx_byte[PIN_COUNT-1:0]));
                else
                    assert (pin_dir == $past(pin_dir));

                // write pointer: +1 per instruction written, 0 on CTRL bit 1, else holds
                if ($past(imem_write_enable))
                    assert (imem_write_addr == $past(imem_write_addr) + 1'b1);
                else if ($past(f_ptr_reset))
                    assert (imem_write_addr == '0);
                else
                    assert (imem_write_addr == $past(imem_write_addr));

                // IMEM bytes alternate low, high; ignored while busy
                if ($past(f_ptr_reset))
                    assert (!imem_high_phase);
                else if ($past(f_imem_write) && !$past(busy))
                    assert (imem_high_phase == !$past(imem_high_phase));
                else
                    assert (imem_high_phase == $past(imem_high_phase));

                if ($past(f_imem_write) && !$past(busy) && !$past(imem_high_phase))
                    assert (imem_low_byte == $past(rx_byte));
                else
                    assert (imem_low_byte == $past(imem_low_byte));
            end

            // Deselecting resets the byte receiver
            if (!$past(rst_n) || !$past(cs_active))
                assert (bit_count == '0 && first_byte);
        end
    end

    // Reachability: full SPI transactions driven by the solver
    always_ff @(posedge clk) begin
        if (f_past_valid && rst_n) begin
            cover (pin_dir == 4'b1011);                               // write PIN_DIR
            cover (start);                                            // write CTRL start
            cover (imem_write_enable && imem_write_data == 16'h1006); // write SET P3, 0
        end
    end
endmodule

bind host_interface host_interface_props #(
    .ADDRESS_WIDTH(ADDRESS_WIDTH), .PIN_COUNT(PIN_COUNT)
) u_props (.*);
