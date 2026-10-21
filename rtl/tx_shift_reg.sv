module tx_shift_reg #(
    parameter WIDTH = 8
)(
    input logic clk,
    input logic rst_n,
    input logic load,
    input logic shift, //
    input logic [WIDTH-1:0] tx_parallel_in, // tx data
    output logic tx_serial_out // output parallel data byte
);

    logic [WIDTH-1:0] tx_reg;

    assign tx_serial_out = tx_reg[WIDTH-1];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            tx_reg <= {WIDTH{1'b0}};
        end
        else if (load) begin
            tx_reg <= tx_parallel_in;
        end
        else if (shift) begin
            tx_reg <= {tx_reg[WIDTH-2:0], 1'b0};
        end
    end

endmodule