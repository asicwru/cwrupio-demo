// Formal properties for pin_control, attached with bind so the RTL stays untouched.
module pin_control_props #(
    parameter int PIN_COUNT = 4
)(
    input logic                         clk,
    input logic                         rst_n,
    input logic                         pin_set,
    input logic                         pin_out_bit,
    input logic [$clog2(PIN_COUNT)-1:0] pin_select,
    input logic                         pin_value,
    input logic                         tx_bit,
    input logic                         sample_bit,
    input logic [PIN_COUNT-1:0]         pin_dir,
    input logic [PIN_COUNT-1:0]         pin_in,
    input logic [PIN_COUNT-1:0]         pin_out,
    input logic [PIN_COUNT-1:0]         pin_oe,
    input logic [PIN_COUNT-1:0]         pin_sync_1,   // internal
    input logic [PIN_COUNT-1:0]         pin_sync_2    // internal
);
    logic f_past_valid = 1'b0;
    always_ff @(posedge clk) f_past_valid <= 1'b1;

    // Start in reset
    always_comb if (!f_past_valid) assume (!rst_n);

    always_comb begin
        assert (pin_oe == pin_dir);                       // direction comes only from the host
        assert (sample_bit == pin_sync_2[pin_select]);
    end

    // Output registers: SET / OUT_BIT change only the selected pin
    always_ff @(posedge clk) begin
        if (f_past_valid) begin
            if (!$past(rst_n)) begin
                assert (pin_out == '0);
            end else begin
                for (int i = 0; i < PIN_COUNT; i++) begin
                    if (($past(pin_set) || $past(pin_out_bit)) && i == $past(pin_select))
                        assert (pin_out[i] == ($past(pin_set) ? $past(pin_value) : $past(tx_bit)));
                    else
                        assert (pin_out[i] == $past(pin_out[i]));
                end
            end
        end
    end

    // Input synchronizer: SAMPLE sees the pin value from exactly 2 cycles earlier
    always_ff @(posedge clk) begin
        if (f_past_valid) begin
            if (!$past(rst_n)) begin
                assert (pin_sync_1 == '0 && pin_sync_2 == '0);
            end else begin
                assert (pin_sync_1 == $past(pin_in));
                assert (pin_sync_2 == $past(pin_sync_1));
            end
        end
    end

    // Reachability
    always_ff @(posedge clk) begin
        if (f_past_valid && rst_n) begin
            cover (pin_out == 4'b1010);
            cover (sample_bit && pin_select == 2'd2);
        end
    end
endmodule

bind pin_control pin_control_props #(.PIN_COUNT(PIN_COUNT)) u_props (.*);
