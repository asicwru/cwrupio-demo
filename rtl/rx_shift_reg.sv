module rx_shift_reg #(
    parameter WIDTH = 8
)(
    input logic clk,
    input logic rst_n,
    input logic shift, //
    input logic rx_serial_in, 
    output logic [WIDTH-1:0] rx_parallel_out // output parallel data byte
);

    logic [WIDTH-1:0] rx_reg;

    assign rx_parallel_out = rx_reg;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rx_reg <= {WIDTH{1'b0}};
        end
        else if (shift) begin
            rx_reg <= {rx_reg[WIDTH-2:0], rx_serial_in};
        end
    end

endmodule