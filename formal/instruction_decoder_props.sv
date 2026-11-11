// Formal properties for instruction_decoder (combinational), checked against docs/isa.md.
module instruction_decoder_props #(
    parameter ADDRESS_WIDTH = cwrupio_pkg::IMEM_ADDR_WIDTH
)(
    input logic [cwrupio_pkg::INSTRUCTION_WIDTH-1:0] instruction,
    input cwrupio_pkg::opcode_t                      opcode,
    input logic [1:0]                                pin_select,
    input logic                                      pin_value,
    input logic [11:0]                               wait_cycles,
    input logic [cwrupio_pkg::DATA_WIDTH-1:0]        count_value,
    input logic [ADDRESS_WIDTH-1:0]                  branch_target
);
    import cwrupio_pkg::*;

    always_comb begin
        // Fields
        assert (opcode        == opcode_t'(instruction[15:12]));
        assert (pin_value     == instruction[0]);
        assert (wait_cycles   == instruction[11:0]);
        assert (count_value   == instruction[7:0]);
        assert (branch_target == instruction[ADDRESS_WIDTH-1:0]);

        // Pin field position depends on the instruction
        case (instruction[15:12])
            OP_SET:                assert (pin_select == instruction[2:1]); // SET pin, value
            OP_OUT_BIT, OP_SAMPLE: assert (pin_select == instruction[1:0]); // OUT_BIT/SAMPLE pin
            default: ;                                                       // unused
        endcase

        // Examples from the ISA doc
        if (instruction == 16'h1006) assert (opcode == OP_SET && pin_select == 2'd3 && pin_value == 1'b0); // SET P3, 0
        if (instruction == 16'h2064) assert (opcode == OP_WAIT && wait_cycles == 12'd100);                // WAIT 100
        if (instruction == 16'h4001) assert (opcode == OP_OUT_BIT && pin_select == 2'd1);                 // OUT_BIT P1
        if (instruction == 16'h7002) assert (opcode == OP_SAMPLE && pin_select == 2'd2);                  // SAMPLE P2
        if (instruction == 16'h8008) assert (opcode == OP_COUNT && count_value == 8'd8);                  // COUNT 8
        if (instruction == 16'h9008) assert (opcode == OP_LOOP && branch_target == ADDRESS_WIDTH'(8));    // LOOP 8

        cover (opcode == OP_JUMP && branch_target == '1);
    end
endmodule

bind instruction_decoder instruction_decoder_props #(.ADDRESS_WIDTH(ADDRESS_WIDTH)) u_props (.*);
