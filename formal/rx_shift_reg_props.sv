// Formal properties for rx_shift_reg, attached with bind so the RTL stays untouched.
module rx_shift_reg_props #(
    parameter WIDTH = 8
)(
    input logic             clk,
    input logic             rst_n,
    input logic             shift,
    input logic             rx_serial_in,
    input logic [WIDTH-1:0] rx_parallel_out
);
    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;

    // Start in reset
    always_comb if (!f_past_valid) assume (!rst_n);

    // One-step behavior: shift left, new bit enters at bit 0, so after 8 shifts
    // the first sampled bit sits in the MSB.
    always_ff @(posedge clk) begin
        if (f_past_valid) begin
            if (!$past(rst_n))
                assert (rx_parallel_out == '0);
            else if ($past(shift))
                assert (rx_parallel_out == {$past(rx_parallel_out[WIDTH-2:0]), $past(rx_serial_in)});
            else
                assert (rx_parallel_out == $past(rx_parallel_out));
        end
    end

    // Reachability
    always_ff @(posedge clk) begin
        if (f_past_valid && rst_n) begin
            cover (rx_parallel_out == 8'hA5);
            cover (rx_parallel_out == 8'hFF);
        end
    end
endmodule

bind rx_shift_reg rx_shift_reg_props #(.WIDTH(WIDTH)) u_props (.*);
