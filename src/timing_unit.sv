module timing_unit #(
    parameter int TIMER_WIDTH = 12
)(
    input logic clk,
    input logic rst_n,
    input logic timer_start,
    input logic [TIMER_WIDTH-1:0] timer_cycles,
    output logic timer_done 
);

    logic [TIMER_WIDTH-1:0] count;

    assign timer_done = (count == TIMER_WIDTH'(1));
    
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            count <= '0;
        end 
        else if (timer_start) begin
            count <= timer_cycles - 1'b1;
        end 
        else if (count != '0) begin
            count <= count - 1'b1;
        end
    end

endmodule
