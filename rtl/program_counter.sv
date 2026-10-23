module program_counter #(
    parameter DEPTH = 32 // TBD instr mem depth
    parameter ADDRESS_WIDTH = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst_n,
    input logic branch_enable,
    input logic [ADDRESS_WIDTH-1:0] target_address, // next address (PC + 4) or Branch
    output logic [ADDRESS_WIDTH-1:0] program_counter // current address
);

always_ff @(posedge clk) begin
    if (!rst_n) begin
        program_counter <= {ADDRESS_WIDTH{1'b0}};
    end
    else begin
        if (branch_enable) begin
            program_counter <= target_address;
        end
        else begin
            program_counter <= program_counter + (ADDRESS_WIDTH)'1;
        end
    end
end

endmodule

// Plan to implement some branching later