module timing_unit #(
    parameter TIMER_WIDTH = 12
)(
    input logic clk,
    input logic rst_n,
    input logic timer_start,
    input logic [N-1:0] timer_cycles,
    output logic timer_done
);

    logic [N-1:0] count;

    always_comb begin
        if (count == 'b0) begin
            timer_done = 1'b1;
        end else begin
            timer_done = 1'b0;
        end
    end
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            count <= 'b0;
        end else if (timer_start) begin
            count <= timer_cycles;
        end else if (count > 0) begin
            count <= count - 1;
        end
    end

endmodule