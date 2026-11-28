// Formal properties for instruction_memory, attached with bind so the RTL stays untouched.
// Tracks one address the solver picks freely: since it can be any address, the
// proof covers all of them.
module instruction_memory_props #(
    parameter WIDTH = cwrupio_pkg::INSTRUCTION_WIDTH,
    parameter DEPTH = cwrupio_pkg::IMEM_DEPTH,
    parameter ADDRESS_WIDTH = $clog2(DEPTH)
)(
    input logic                     clk,
    input logic                     write_enable,
    input logic [ADDRESS_WIDTH-1:0] write_addr,
    input logic [WIDTH-1:0]         write_data,
    input logic [ADDRESS_WIDTH-1:0] pc,
    input logic [WIDTH-1:0]         instruction,
    input logic [WIDTH-1:0]         memory [DEPTH-1:0]   // internal array
);
    // No reset or initial value, so the solver picks its starting value;
    // it only ever reloads itself, so it stays constant after that.
    logic [ADDRESS_WIDTH-1:0] f_addr;
    always_ff @(posedge clk) f_addr <= f_addr;

    logic             f_written = 1'b0;
    logic [WIDTH-1:0] f_data;

    always_ff @(posedge clk) begin
        if (write_enable && write_addr == f_addr) begin
            f_written <= 1'b1;
            f_data    <= write_data;
        end
    end

    always_comb begin
        // The last value written to an address is what is stored there...
        if (f_written)
            assert (memory[f_addr] == f_data);
        // ...and what the fetch port returns for it
        if (f_written && pc == f_addr)
            assert (instruction == f_data);
    end

    // Reachability
    always_comb begin
        cover (f_written && pc == f_addr && instruction == 16'hBEEF);
    end
endmodule

bind instruction_memory instruction_memory_props #(
    .WIDTH(WIDTH), .DEPTH(DEPTH), .ADDRESS_WIDTH(ADDRESS_WIDTH)
) u_props (.*);
