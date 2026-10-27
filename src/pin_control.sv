module pin_control #(
    parameter int PIN_COUNT = 4 // logical pins P0-P3
)(
    input logic clk,
    input logic rst_n,

    // sequencer
    input logic pin_set, // SET pin, value
    input logic pin_out_bit, // OUT_BIT pin

    // instruction decoder
    input logic [$clog2(PIN_COUNT)-1:0] pin_select,
    input logic pin_value,

    // tx/rx shift registers
    input logic tx_bit, // tx_reg[7]
    output logic sample_bit, // to rx_shift_reg serial input

    // host interface
    input logic [PIN_COUNT-1:0] pin_dir, // 1 = output, 0 = input

    // pads (uio)
    input logic [PIN_COUNT-1:0] pin_in,
    output logic [PIN_COUNT-1:0] pin_out,
    output logic [PIN_COUNT-1:0] pin_oe
);

    logic [PIN_COUNT-1:0] pin_sync_1;
    logic [PIN_COUNT-1:0] pin_sync_2;

    // output registers: written by SET and OUT_BIT
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pin_out <= '0;
        end 
        else if (pin_set) begin
            pin_out[pin_select] <= pin_value;
        end 
        else if (pin_out_bit) begin
            pin_out[pin_select] <= tx_bit;
        end
    end

    // output enable comes from the host direction register
    assign pin_oe = pin_dir;

    // 2-flop synchronizer on every input pin
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pin_sync_1 <= '0;
            pin_sync_2 <= '0;
        end 
        else begin
            pin_sync_1 <= pin_in;
            pin_sync_2 <= pin_sync_1;
        end
    end

    // SAMPLE reads the synchronized value of the selected pin
    assign sample_bit = pin_sync_2[pin_select];

endmodule
