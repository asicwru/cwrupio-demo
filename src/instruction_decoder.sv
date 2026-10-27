module instruction_decoder #(
    parameter ADDRESS_WIDTH = cwrupio_pkg::IMEM_ADDR_WIDTH 
)(
    input logic [cwrupio_pkg::INSTRUCTION_WIDTH-1:0] instruction,
    output cwrupio_pkg::opcode_t opcode,
    output logic [1:0] pin_select,
    output logic pin_value,
    output logic [11:0] wait_cycles,
    output logic [cwrupio_pkg::DATA_WIDTH-1:0] count_value,
    output logic [ADDRESS_WIDTH-1:0] branch_target
);

    assign opcode = cwrupio_pkg::opcode_t'(instruction[15:12]);
    assign pin_value = instruction[0];
    assign wait_cycles = instruction[11:0];
    assign count_value = instruction[7:0];
    assign branch_target = instruction[ADDRESS_WIDTH-1:0];

    always_comb begin
        case (instruction[15:12])
            cwrupio_pkg::OP_SET: begin
                pin_select = instruction[2:1];
            end
            cwrupio_pkg::OP_OUT_BIT, cwrupio_pkg::OP_SAMPLE: begin
                pin_select = instruction[1:0];
            end
            default: begin
                pin_select = instruction[2:1];
            end
        endcase
    end

endmodule