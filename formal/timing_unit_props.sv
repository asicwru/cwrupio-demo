// Formal properties for timing_unit, attached with bind so the RTL stays untouched.
module timing_unit_props #(
    parameter int TIMER_WIDTH = 12
)(
    input logic                   clk,
    input logic                   rst_n,
    input logic                   timer_start,
    input logic [TIMER_WIDTH-1:0] timer_cycles,
    input logic                   timer_done,
    input logic [TIMER_WIDTH-1:0] count          // internal register
);
    localparam int EW = TIMER_WIDTH + 1;         // elapsed counter, never overflows

    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;

    // Start in reset
    always_comb if (!f_past_valid) assume (!rst_n);

    always_comb assert (timer_done == (count == TIMER_WIDTH'(1)));

    // One-step behavior
    always_ff @(posedge clk) begin
        if (f_past_valid) begin
            if (!$past(rst_n))
                assert (count == '0);
            else if ($past(timer_start))
                assert (count == $past(timer_cycles) - 1'b1);
            else if ($past(count) != '0)
                assert (count == $past(count) - 1'b1);
            else
                assert (count == '0);                // stays idle, no wrap
        end
    end

    // End to end: after timer_start with N >= 2 (and no restart), timer_done pulses
    // exactly once, N-1 cycles later. Together with the start cycle that makes WAIT N
    // take N cycles. (N = 1 never pulses and N = 0 wraps; the sequencer handles both
    // without starting the timer.)
    logic                   f_armed = 1'b0;
    logic [TIMER_WIDTH-1:0] f_n;
    logic [EW-1:0]          f_elapsed;           // cycles since timer_start

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            f_armed <= 1'b0;
        end else if (timer_start) begin
            f_armed   <= (timer_cycles != '0);
            f_n       <= timer_cycles;
            f_elapsed <= EW'(1);
        end else if (f_armed && f_elapsed != '1) begin
            f_elapsed <= f_elapsed + 1'b1;
        end
    end

    always_comb begin
        if (f_armed) begin
            assert (f_elapsed != '0);
            // helper for induction: the count is exactly what is left of the wait
            assert (count == ((f_elapsed <= EW'(f_n)) ? TIMER_WIDTH'(EW'(f_n) - f_elapsed) : '0));
            if (f_n >= TIMER_WIDTH'(2))
                assert (timer_done == (f_elapsed == EW'(f_n) - 1'b1));
            else
                assert (!timer_done);
        end
    end

    // Reachability
    always_ff @(posedge clk) begin
        if (f_past_valid && rst_n) begin
            cover (f_armed && f_n == TIMER_WIDTH'(5) && timer_done);
            cover (f_armed && f_n == TIMER_WIDTH'(2) && timer_done);
        end
    end
endmodule

bind timing_unit timing_unit_props #(.TIMER_WIDTH(TIMER_WIDTH)) u_props (.*);
