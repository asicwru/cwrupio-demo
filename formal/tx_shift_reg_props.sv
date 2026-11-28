// Formal properties for tx_shift_reg, attached with bind so the RTL stays untouched.
module tx_shift_reg_props #(
    parameter WIDTH = 8
)(
    input logic             clk,
    input logic             rst_n,
    input logic             load,
    input logic             shift,
    input logic [WIDTH-1:0] tx_parallel_in,
    input logic             tx_serial_out,
    input logic [WIDTH-1:0] tx_reg          // internal register
);
    localparam int KW = $clog2(WIDTH + 1);

    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;

    // Start in reset
    always_comb if (!f_past_valid) assume (!rst_n);

    always_comb assert (tx_serial_out == tx_reg[WIDTH-1]);

    // One-step behavior
    always_ff @(posedge clk) begin
        if (f_past_valid) begin
            if (!$past(rst_n))
                assert (tx_reg == '0);
            else if ($past(load))                       // load beats shift
                assert (tx_reg == $past(tx_parallel_in));
            else if ($past(shift))
                assert (tx_reg == {$past(tx_reg[WIDTH-2:0]), 1'b0});
            else
                assert (tx_reg == $past(tx_reg));
        end
    end

    // End to end: after loading byte D and k shifts, the serial output is D[WIDTH-1-k]
    // (MSB first), and 0 once all bits are shifted out.
    logic             f_loaded = 1'b0;
    logic [WIDTH-1:0] f_byte;
    logic [KW-1:0]    f_k;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            f_loaded <= 1'b0;
        end else if (load) begin
            f_loaded <= 1'b1;
            f_byte   <= tx_parallel_in;
            f_k      <= '0;
        end else if (shift && f_k < KW'(WIDTH)) begin
            f_k <= f_k + 1'b1;
        end
    end

    always_comb begin
        if (f_loaded) begin
            assert (f_k <= KW'(WIDTH));
            assert (tx_reg == (f_byte << f_k));
            assert (tx_serial_out == ((f_k < KW'(WIDTH)) ? f_byte[WIDTH-1-f_k] : 1'b0));
        end
    end

    // Reachability
    always_ff @(posedge clk) begin
        if (f_past_valid && rst_n) begin
            cover (f_loaded && f_byte == 8'hA5 && f_k == KW'(WIDTH-1)); // last bit of a byte
            cover (f_loaded && f_k == KW'(WIDTH));                      // fully shifted out
        end
    end
endmodule

bind tx_shift_reg tx_shift_reg_props #(.WIDTH(WIDTH)) u_props (.*);
