module rx_shift_reg #(
    parameter WIDTH = 16
)(
    input logic clk,
    input logic rst_n,
    input logic shift_enable, //
    input logic rx_serial_in, 
    output logic [7:0] rx_data // output parallel data byte
);

    logic [WIDTH-1:0] rx_reg;

    assign rx_data = rx_reg;

    always_ff @(posedge clk) begin
        if (reset) begin
            rx_reg <= {WIDTH{1'b0}};
        end
        else if (shift_enable) begin
            rx_reg <= {rx_reg[WIDTH-2:0], rx_serial_in};
        end
    end

endmodule