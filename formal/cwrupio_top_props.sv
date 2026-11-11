// Whole-chip properties for cwrupio_top, attached with bind so the RTL stays untouched.
// The solver drives the real SPI host pins and protocol pins. Instruction memory
// starts with arbitrary contents, so the solver can also pick the program.
//
// Define SPEC to also check ISA rules from docs/isa.md that the RTL doesn't
// implement yet (run with `make spec`).
module cwrupio_top_props #(
    parameter int DEPTH = cwrupio_pkg::IMEM_DEPTH,
    parameter int PIN_COUNT = 4
)(
    input logic                                      clk,
    input logic                                      rst_n,
    input logic                                      host_sck,
    input logic                                      host_cs_n,
    input logic                                      host_mosi,
    input logic                                      host_miso,
    input logic [PIN_COUNT-1:0]                      pin_in,
    input logic [PIN_COUNT-1:0]                      pin_out,
    input logic [PIN_COUNT-1:0]                      pin_oe,
    // internal wires
    input logic                                      start,
    input logic                                      busy,
    input logic                                      done,
    input logic                                      fault,
    input logic [$clog2(DEPTH)-1:0]                  pc,
    input cwrupio_pkg::pc_sel_t                      pc_sel,
    input logic [cwrupio_pkg::INSTRUCTION_WIDTH-1:0] instruction,
    input cwrupio_pkg::opcode_t                      opcode,
    input logic [11:0]                               wait_cycles,
    input logic                                      count_is_zero,
    input logic                                      count_is_one,
    input logic                                      rx_clear,
    input logic [cwrupio_pkg::DATA_WIDTH-1:0]        rx_data,
    input logic                                      imem_write_enable,
    input logic [PIN_COUNT-1:0]                      pin_dir
);
    import cwrupio_pkg::*;
    localparam int AW = $clog2(DEPTH);

    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;

    // Start in reset
    always_comb if (!f_past_valid) assume (!rst_n);

    // Cycles the current instruction has been running, including this one
    logic          f_prev_busy;
    logic [AW-1:0] f_prev_pc;
    logic [12:0]   f_cycles_reg, f_cycles;
    logic          f_new_instr;

    assign f_new_instr = busy && (!f_prev_busy || pc != f_prev_pc);
    assign f_cycles    = f_new_instr ? 13'd1 : f_cycles_reg + 1'b1;

    always_ff @(posedge clk) begin
        f_prev_busy  <= rst_n && busy;
        f_prev_pc    <= pc;
        f_cycles_reg <= (busy && f_cycles != '1) ? f_cycles : f_cycles_reg;
    end

    always_comb begin
        assert (pin_oe == pin_dir);
        assert (!(imem_write_enable && busy));       // program can't change while running
        if (f_past_valid && fault) assert (done && !busy);
    end

    always_ff @(posedge clk) begin
        if (f_past_valid && $past(rst_n) && rst_n) begin
            // Protocol pins only change while a program runs
            if (pin_out != $past(pin_out)) assert ($past(busy));

            // Every program run starts at address 0
            if (busy && !$past(busy)) assert (pc == '0);
        end
    end

    // WAIT N holds the PC for exactly N cycles (only checked with a clean history)
    always_comb begin
        if (f_past_valid && rst_n && busy && opcode == OP_WAIT && pc_sel == PC_INC)
            assert (f_cycles == 13'(wait_cycles));
    end

`ifdef SPEC
    // ISA rules from docs/isa.md. busy with any opcode other than WAIT means the
    // sequencer is executing this instruction this cycle.
    logic [11:0] f_zero_mask;                   // bits that must be 0 for this opcode
    always_comb begin
        case (opcode)
            OP_HALT, OP_LOAD_TX, OP_SHIFT_TX, OP_CLEAR_RX: f_zero_mask = 12'hFFF;
            OP_SET:                                        f_zero_mask = 12'hFF8;
            OP_OUT_BIT, OP_SAMPLE:                         f_zero_mask = 12'hFFC;
            OP_COUNT, OP_LOOP, OP_JUMP:                    f_zero_mask = 12'hF00;
            default:                                       f_zero_mask = 12'h000;
        endcase
    end

    logic f_exec, f_bad_bits, f_bad_target;
    assign f_exec       = busy && opcode != OP_WAIT;
    assign f_bad_bits   = (instruction[11:0] & f_zero_mask) != '0;
    assign f_bad_target = instruction[7:0] >= 8'(DEPTH) &&
                          (opcode == OP_JUMP ||
                           (opcode == OP_LOOP && !count_is_zero && !count_is_one));

    always_ff @(posedge clk) begin
        if (f_past_valid && $past(rst_n) && rst_n) begin
            // "A nonzero bit in a required-zero position" faults
            if ($past(f_exec) && $past(f_bad_bits))   assert (fault);
            // "A branch address outside the instruction memory" faults
            if ($past(f_exec) && $past(f_bad_target)) assert (fault);
            // CLEAR_RX sets the RX shift register to 0x00
            if ($past(rx_clear))                      assert (rx_data == '0);
        end
    end
`endif

    // Reachability: load nothing, just start the (arbitrary) program over SPI
    always_ff @(posedge clk) begin
        if (f_past_valid && rst_n) begin
            cover (start);                                         // host sends start
            cover (done && !fault && pin_out != '0);              // program drives a pin, halts
            cover (fault);                                        // program faults
            cover (busy && opcode == OP_WAIT && pc_sel == PC_INC && wait_cycles == 12'd3);
        end
    end
endmodule

bind cwrupio_top cwrupio_top_props #(.DEPTH(DEPTH), .PIN_COUNT(PIN_COUNT)) u_props (.*);
