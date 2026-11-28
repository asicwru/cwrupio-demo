// Formal properties for program_counter, attached with bind so the RTL stays untouched.
module program_counter_props #(
    parameter DEPTH = cwrupio_pkg::IMEM_DEPTH
)(
    input logic                       clk,
    input logic                       rst_n,
    input cwrupio_pkg::pc_sel_t       pc_sel,
    input logic [$clog2(DEPTH)-1:0]   branch_target,
    input logic [$clog2(DEPTH)-1:0]   pc
);
    import cwrupio_pkg::*;
    localparam int AW = $clog2(DEPTH);

    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;

    // Start in reset
    always_comb if (!f_past_valid) assume (!rst_n);

    always_ff @(posedge clk) begin
        if (f_past_valid) begin
            if (!$past(rst_n))
                assert (pc == '0);
            else begin
                case ($past(pc_sel))
                    PC_HOLD:   assert (pc == $past(pc));
                    PC_INC:    assert (pc == ($past(pc) == AW'(DEPTH-1) ? '0 : $past(pc) + 1'b1));
                    PC_BRANCH: assert (pc == $past(branch_target));
                    PC_START:  assert (pc == '0);
                    default:   assert (pc == $past(pc));
                endcase
            end
        end
    end

    // Reachability
    always_ff @(posedge clk) begin
        if (f_past_valid && rst_n && $past(rst_n)) begin
            cover ($past(pc) == AW'(DEPTH-1) && $past(pc_sel) == PC_INC && pc == '0); // wrap
            cover ($past(pc_sel) == PC_BRANCH && pc == AW'(DEPTH-1));
        end
    end
endmodule

bind program_counter program_counter_props #(.DEPTH(DEPTH)) u_props (.*);
