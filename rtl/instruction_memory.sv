module instruction_memory import cwrupio_pkg::*; #(
    parameter WIDTH = INSTRUCTION_WIDTH, // TBD
    parameter DEPTH = IMEM_DEPTH, // TBD instr mem depth
    parameter ADDRESS_WIDTH = $clog2(DEPTH),
    parameter PATH = "" // FILE PATH for the HEX FILE (FPGA/SIMULATION ONLY)
)(
    input logic clk,
    input logic write_enable,
    input logic [ADDRESS_WIDTH-1:0] write_addr,
    input logic [WIDTH-1:0] write_data,
    input logic [ADDRESS_WIDTH-1:0] pc, // program counter
    output logic [WIDTH-1:0] instruction
);

    logic [WIDTH-1:0] memory [DEPTH-1:0]; // memorpy TBD 16 bit 

    initial begin
        if (PATH != "") begin
            $readmemh(PATH, memory);
        end
    end

    always_ff @(posedge clk) begin
        if (write_enable) begin
            memory[write_addr] <= write_data;
        end
    end

    assign instruction = memory[pc];
endmodule

    