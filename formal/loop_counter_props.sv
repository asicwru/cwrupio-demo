// Formal properties for loop_counter, attached with bind so the RTL stays untouched.
module loop_counter_props #(
    parameter int LOOP_WIDTH = 8
)(
    input logic                  clk,
    input logic                  rst_n,
    input logic                  count_ld,
    input logic                  count_dec,
    input logic [LOOP_WIDTH-1:0] count_val,
    input logic                  count_is_one,
    input logic                  count_is_zero,
    input logic [LOOP_WIDTH-1:0] count          // internal register
);
    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;

    // Start in reset
    always_comb if (!f_past_valid) assume (!rst_n);

    // Status flags always match the count
    always_comb begin
        assert (count_is_zero == (count == '0));
        assert (count_is_one  == (count == LOOP_WIDTH'(1)));
        assert (!(count_is_one && count_is_zero));
    end

    always_ff @(posedge clk) begin
        if (f_past_valid) begin
            if (!$past(rst_n))
                assert (count == '0);
            else if ($past(count_ld))                          // load beats decrement
                assert (count == $past(count_val));
            else if ($past(count_dec) && $past(count) != '0)
                assert (count == $past(count) - 1'b1);
            else                                               // includes: no underflow at 0
                assert (count == $past(count));
        end
    end

    // Reachability: these must be hit or the assumptions are too strict
    always_ff @(posedge clk) begin
        if (f_past_valid && rst_n) begin
            cover (count_is_one && $past(count_dec));
            cover (count_is_zero && $past(count_is_one) && $past(count_dec));
            cover (&count);                                    // max value
        end
    end
endmodule

bind loop_counter loop_counter_props #(.LOOP_WIDTH(LOOP_WIDTH)) u_props (.*);
