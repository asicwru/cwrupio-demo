module instruction_memory #(
    parameter WIDTH = 16 // TBD
    parameter DEPTH = 32 // TBD instr mem depth
    parameter ADDRESS_WIDTH = $clog2(DEPTH)
    parameter PATH = "" // FILE PATH for the HEX FILE (FPGA/SIMULATION ONLY)
)(
    input logic clk,
    input logic write_enable,
    input logic [ADDRESS_WIDTH-1:0] write_addr,
    input logic [WIDTH-1:0] write_data,
    input logic [ADDRESS_WIDTH-1:0] pc, // program counter
    output logic [WIDTH-1:0] instruction
);

    logic [W-1:0] memory [DEPTH-1:0]; // memorpy TBD 16 bit 

    initial begin
        if (PATH !== "") begin
            $readmemh(PATH, mem);
        end
    end

    always_ff @(posedge clk) begin
        if (write_enable) begin
            mem[write_addr] <= write_data;
        end
    end

    assign instruction = mem[pc];
endmodule

    