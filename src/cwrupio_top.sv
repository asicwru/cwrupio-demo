module cwrupio_top import cwrupio_pkg::*; #(
    parameter int DEPTH = IMEM_DEPTH, // instruction memory depth
    parameter int PIN_COUNT = 4 // logical pins P0-P3
)(
    input logic clk,
    input logic rst_n,

    // host link (SPI target, configuration port only)
    input logic host_sck,
    input logic host_cs_n,
    input logic host_mosi,
    output logic host_miso,

    // logical protocol pins P0-P3
    input logic [PIN_COUNT-1:0] pin_in,
    output logic [PIN_COUNT-1:0] pin_out,
    output logic [PIN_COUNT-1:0] pin_oe
);

    localparam int ADDRESS_WIDTH = $clog2(DEPTH);
    localparam int TIMER_WIDTH = 12; // WAIT field width
    localparam int LOOP_WIDTH = DATA_WIDTH; // COUNT field width

    // host interface <-> core
    logic start;
    logic busy;
    logic done;
    logic fault;
    logic [DATA_WIDTH-1:0] tx_data;
    logic [DATA_WIDTH-1:0] rx_data;
    logic imem_write_enable;
    logic [ADDRESS_WIDTH-1:0] imem_write_addr;
    logic [INSTRUCTION_WIDTH-1:0] imem_write_data;
    logic [PIN_COUNT-1:0] pin_dir;

    // fetch and decode
    logic [ADDRESS_WIDTH-1:0] pc;
    pc_sel_t pc_sel;
    logic [INSTRUCTION_WIDTH-1:0] instruction;
    opcode_t opcode;
    logic [1:0] pin_select;
    logic pin_value;
    logic [TIMER_WIDTH-1:0] wait_cycles;
    logic [LOOP_WIDTH-1:0] count_value;
    logic [ADDRESS_WIDTH-1:0] branch_target;

    // sequencer strobes and status
    logic timer_start;
    logic timer_done;
    logic count_ld;
    logic count_dec;
    logic count_is_zero;
    logic count_is_one;
    logic tx_load;
    logic tx_shift;
    logic rx_clear;
    logic rx_shift;
    logic pin_set;
    logic pin_out_bit;

    // data path between execution units
    logic tx_bit;
    logic sample_bit;

    host_interface #(
        .ADDRESS_WIDTH(ADDRESS_WIDTH),
        .PIN_COUNT(PIN_COUNT)
    ) u_host_interface (
        .clk(clk),
        .rst_n(rst_n),
        .host_sck(host_sck),
        .host_cs_n(host_cs_n),
        .host_mosi(host_mosi),
        .host_miso(host_miso),
        .busy(busy),
        .done(done),
        .fault(fault),
        .start(start),
        .tx_data(tx_data),
        .rx_data(rx_data),
        .imem_write_enable(imem_write_enable),
        .imem_write_addr(imem_write_addr),
        .imem_write_data(imem_write_data),
        .pin_dir(pin_dir)
    );

    instruction_memory #(
        .WIDTH(INSTRUCTION_WIDTH),
        .DEPTH(DEPTH)
    ) u_instruction_memory (
        .clk(clk),
        .write_enable(imem_write_enable),
        .write_addr(imem_write_addr),
        .write_data(imem_write_data),
        .pc(pc),
        .instruction(instruction)
    );

    program_counter #(
        .DEPTH(DEPTH)
    ) u_program_counter (
        .clk(clk),
        .rst_n(rst_n),
        .pc_sel(pc_sel),
        .branch_target(branch_target),
        .pc(pc)
    );

    instruction_decoder #(
        .ADDRESS_WIDTH(ADDRESS_WIDTH)
    ) u_instruction_decoder (
        .instruction(instruction),
        .opcode(opcode),
        .pin_select(pin_select),
        .pin_value(pin_value),
        .wait_cycles(wait_cycles),
        .count_value(count_value),
        .branch_target(branch_target)
    );

    sequencer #(
        .TIMER_WIDTH(TIMER_WIDTH),
        .LOOP_WIDTH(LOOP_WIDTH)
    ) u_sequencer (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .busy(busy),
        .done(done),
        .fault(fault),
        .opcode(opcode),
        .wait_cycles(wait_cycles),
        .count_value(count_value),
        .pc_sel(pc_sel),
        .timer_done(timer_done),
        .timer_start(timer_start),
        .count_is_zero(count_is_zero),
        .count_is_one(count_is_one),
        .count_ld(count_ld),
        .count_dec(count_dec),
        .tx_load(tx_load),
        .tx_shift(tx_shift),
        .rx_clear(rx_clear),
        .rx_shift(rx_shift),
        .pin_set(pin_set),
        .pin_out_bit(pin_out_bit)
    );

    timing_unit #(
        .TIMER_WIDTH(TIMER_WIDTH)
    ) u_timing_unit (
        .clk(clk),
        .rst_n(rst_n),
        .timer_start(timer_start),
        .timer_cycles(wait_cycles),
        .timer_done(timer_done)
    );

    loop_counter #(
        .LOOP_WIDTH(LOOP_WIDTH)
    ) u_loop_counter (
        .clk(clk),
        .rst_n(rst_n),
        .count_ld(count_ld),
        .count_dec(count_dec),
        .count_val(count_value),
        .count_is_one(count_is_one),
        .count_is_zero(count_is_zero)
    );

    tx_shift_reg #(
        .WIDTH(DATA_WIDTH)
    ) u_tx_shift_reg (
        .clk(clk),
        .rst_n(rst_n),
        .load(tx_load),
        .shift(tx_shift),
        .tx_parallel_in(tx_data),
        .tx_serial_out(tx_bit)
    );

    // TODO: rx_shift_reg has no clear input yet, so CLEAR_RX (rx_clear) does nothing
    rx_shift_reg #(
        .WIDTH(DATA_WIDTH)
    ) u_rx_shift_reg (
        .clk(clk),
        .rst_n(rst_n),
        .shift(rx_shift),
        .rx_serial_in(sample_bit),
        .rx_parallel_out(rx_data)
    );

    pin_control #(
        .PIN_COUNT(PIN_COUNT)
    ) u_pin_control (
        .clk(clk),
        .rst_n(rst_n),
        .pin_set(pin_set),
        .pin_out_bit(pin_out_bit),
        .pin_select(pin_select),
        .pin_value(pin_value),
        .tx_bit(tx_bit),
        .sample_bit(sample_bit),
        .pin_dir(pin_dir),
        .pin_in(pin_in),
        .pin_out(pin_out),
        .pin_oe(pin_oe)
    );

endmodule
