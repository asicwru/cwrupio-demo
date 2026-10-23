module loop_counter #(
    parameter N = 8
)
(
    input logic count_ld,
    input logic count_dec,
    input logic [N-1:0] count_val,
    output logic count_is_one,
    output logic count_is_zero,
    input logic clk,
    input logic rst_n
);
    logic [N-1:0] count;
    assign count_is_one = (count == 1);
    assign count_is_zero = (count == 0);
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            count <= 'b0;
        end else if (count_ld) begin
            count <= count_val;
        end else if (count_dec && count > 0) begin
            count <= count - 1;
        end
    end

endmodule