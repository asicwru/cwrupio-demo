// Formal properties for sequencer, attached with bind so the RTL stays untouched.
// Checks every opcode against docs/isa.md, plus the busy/done/fault status rules.
module sequencer_props #(
    parameter int TIMER_WIDTH = 12,
    parameter int LOOP_WIDTH = 8
)(
    input logic                   clk,
    input logic                   rst_n,
    input logic                   start,
    input logic                   busy,
    input logic                   done,
    input logic                   fault,
    input cwrupio_pkg::opcode_t   opcode,
    input logic [TIMER_WIDTH-1:0] wait_cycles,
    input logic [LOOP_WIDTH-1:0]  count_value,
    input cwrupio_pkg::pc_sel_t   pc_sel,
    input logic                   timer_done,
    input logic                   timer_start,
    input logic                   count_is_zero,
    input logic                   count_is_one,
    input logic                   count_ld,
    input logic                   count_dec,
    input logic                   tx_load,
    input logic                   tx_shift,
    input logic                   rx_clear,
    input logic                   rx_shift,
    input logic                   pin_set,
    input logic                   pin_out_bit,
    input logic [1:0]             state            // internal state register
);
    import cwrupio_pkg::*;

    localparam logic [1:0] S_IDLE  = 2'b00;
    localparam logic [1:0] S_EXEC  = 2'b01;
    localparam logic [1:0] S_STALL = 2'b10;
    localparam logic [1:0] S_FAULT = 2'b11;

    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;

    // Start in reset
    always_comb if (!f_past_valid) assume (!rst_n);

    // The loop counter can't be 0 and 1 at once (proven in loop_counter)
    always_comb assume (!(count_is_zero && count_is_one));

    // All one-cycle strobes, in a fixed order
    logic [8:0] strobes;
    assign strobes = {timer_start, count_ld, count_dec, tx_load, tx_shift,
                      rx_clear, rx_shift, pin_set, pin_out_bit};

    // Expected strobes and PC select for each opcode in S_EXEC
    logic [8:0] f_exp_strobes;
    pc_sel_t    f_exp_pc_sel;
    logic       f_faults;                       // this instruction should fault

    always_comb begin
        f_exp_strobes = '0;
        f_exp_pc_sel  = PC_INC;
        f_faults      = 1'b0;
        case (opcode)
            OP_HALT:     f_exp_pc_sel = PC_HOLD;
            OP_SET:      f_exp_strobes = 9'b000000010;
            OP_WAIT: begin
                if (wait_cycles == '0)
                    f_faults = 1'b1;
                else if (wait_cycles != TIMER_WIDTH'(1)) begin
                    f_exp_strobes = 9'b100000000;
                    f_exp_pc_sel  = PC_HOLD;    // PC moves at the end of the stall
                end
            end
            OP_LOAD_TX:  f_exp_strobes = 9'b000100000;
            OP_OUT_BIT:  f_exp_strobes = 9'b000000001;
            OP_SHIFT_TX: f_exp_strobes = 9'b000010000;
            OP_CLEAR_RX: f_exp_strobes = 9'b000001000;
            OP_SAMPLE:   f_exp_strobes = 9'b000000100;
            OP_COUNT: begin
                if (count_value == '0) f_faults = 1'b1;
                else                   f_exp_strobes = 9'b010000000;
            end
            OP_LOOP: begin
                if (count_is_zero) f_faults = 1'b1;
                else begin
                    f_exp_strobes = 9'b001000000;
                    f_exp_pc_sel  = count_is_one ? PC_INC : PC_BRANCH; // branch if count was > 1
                end
            end
            OP_JUMP:     f_exp_pc_sel = PC_BRANCH;
            default:     f_faults = 1'b1;       // 0xB-0xF unsupported
        endcase
        if (f_faults) begin
            f_exp_strobes = '0;
            f_exp_pc_sel  = PC_HOLD;
        end
    end

    // Outputs in each state
    always_comb begin
        assert ((strobes & (strobes - 1'b1)) == '0);  // at most one strobe per cycle
        assert (busy == (state == S_EXEC || state == S_STALL));

        case (state)
            S_IDLE, S_FAULT: begin
                assert (strobes == '0);
                assert (pc_sel == PC_START);            // program always starts at 0
            end
            S_EXEC: begin
                assert (strobes == f_exp_strobes);
                assert (pc_sel == f_exp_pc_sel);
            end
            S_STALL: begin
                assert (strobes == '0);
                assert (pc_sel == (timer_done ? PC_INC : PC_HOLD));
            end
        endcase
    end

    // Status invariants (registers are only meaningful after the first reset)
    always_comb begin
        if (f_past_valid) begin
            assert (fault == (state == S_FAULT));       // fault flag matches the fault state
            assert (!fault || done);                    // a fault also sets done
            assert (!(busy && done));                   // never busy and done together
        end
    end

    // State transitions
    always_ff @(posedge clk) begin
        if (f_past_valid && $past(rst_n)) begin
            case ($past(state))
                S_IDLE, S_FAULT: begin
                    if ($past(start)) begin
                        assert (state == S_EXEC && !done && !fault);   // start clears status
                    end else begin
                        assert (state == $past(state));
                        assert (done == $past(done) && fault == $past(fault));
                    end
                end
                S_EXEC: begin
                    if ($past(opcode) == OP_HALT)
                        assert (state == S_IDLE && done && !fault);
                    else if ($past(f_faults))
                        assert (state == S_FAULT && done && fault);
                    else if ($past(opcode) == OP_WAIT && $past(wait_cycles) != TIMER_WIDTH'(1))
                        assert (state == S_STALL);
                    else
                        assert (state == S_EXEC);
                end
                S_STALL: begin
                    assert (state == ($past(timer_done) ? S_EXEC : S_STALL));
                end
            endcase
        end
    end

    // Reachability
    always_ff @(posedge clk) begin
        if (f_past_valid && rst_n && $past(rst_n)) begin
            cover ($past(state) == S_EXEC && $past(opcode) == OP_HALT && done);
            cover ($past(state) == S_STALL && state == S_EXEC);
            cover ($past(state) == S_EXEC && $past(opcode) == OP_LOOP && $past(pc_sel) == PC_BRANCH);
            cover (fault && $past(opcode) == OP_WAIT);
            cover (fault && $past(opcode) == OP_COUNT);
            cover (fault && $past(opcode) == OP_LOOP);
            cover (fault && $past(opcode) == opcode_t'(4'hF));
            cover ($past(state) == S_FAULT && state == S_EXEC);   // restart after a fault
        end
    end
endmodule

bind sequencer sequencer_props #(.TIMER_WIDTH(TIMER_WIDTH), .LOOP_WIDTH(LOOP_WIDTH)) u_props (.*, .state(2'(state)));
