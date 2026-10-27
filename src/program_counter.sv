module program_counter #(
    parameter DEPTH = cwrupio_pkg::IMEM_DEPTH // instr mem depth
)(
    input logic clk,
    input logic rst_n,
    input cwrupio_pkg::pc_sel_t pc_sel, // from sequencer
    input logic [$clog2(DEPTH)-1:0] branch_target, // from decoder
    output logic [$clog2(DEPTH)-1:0] pc // current address
);

    localparam ADDRESS_WIDTH = $clog2(DEPTH);

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pc <= '0;
        end else begin
            case (pc_sel)
                cwrupio_pkg::PC_HOLD: begin
                    pc <= pc;
                end
                cwrupio_pkg::PC_INC: begin
                    pc <= pc + ADDRESS_WIDTH'(1);
                end
                cwrupio_pkg::PC_BRANCH: begin
                    pc <= branch_target;
                end
                cwrupio_pkg::PC_START: begin
                    pc <= '0;
                end
                default: begin
                    pc <= pc;
                end
            endcase
        end
    end

endmodule
