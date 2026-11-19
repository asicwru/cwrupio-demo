// Synchronous FIFO -- see sync_fifo/README.md for the full behavioral spec.
//
// Ports and parameter names are fixed: the cocotb testbench and CI use them.
module fifo #(
    parameter int DEPTH  = 8,    // number of words stored; must be a power of two
    parameter int DWIDTH = 16    // bits per word
) (
    input  logic              clk,
    input  logic              rst_n,    // synchronous, active-low reset
    input  logic              wr_en,
    input  logic              rd_en,
    input  logic [DWIDTH-1:0] din,
    output logic [DWIDTH-1:0] dout,
    output logic              empty,
    output logic              full
);

    localparam int AW = $clog2(DEPTH);   // address bits: which of the DEPTH slots

    // Storage: DEPTH words, each DWIDTH bits wide
    logic [DWIDTH-1:0] mem [DEPTH];

    // Pointers have ONE MORE BIT than the address needs. The low AW bits pick the slot
    // (wptr[AW-1:0], rptr[AW-1:0]); the top bit flips each time the pointer wraps past the
    // end. That extra "lap" bit is what lets us tell full from empty:
    //   empty: pointers identical                    (same slot, same lap)
    //   full:  same slot but different lap bits      (writer is one whole lap ahead)
    logic [AW:0] wptr, rptr;

    // TODO: drive `empty` from wptr and rptr.
    always_comb begin
    if (wptr == rptr) begin
        empty = 1'b1;
    end else begin
        empty = 1'b0;
    end
    end

    // TODO: drive `full` from wptr and rptr (see the comment above).
    always_comb begin
    if (wptr[AW-1:0] == rptr[AW-1:0] && wptr[AW] != rptr[AW]) begin
        full = 1'b1;
    end else begin
        full = 1'b0;
    end
    end

    // A write happens only if requested AND there is room; a read only if requested AND
    // there is data. Requests made when full/empty are silently ignored.
    // TODO: define do_write and do_read from wr_en, rd_en, full, empty.
    logic do_write, do_read;
    assign do_write = wr_en && ~full;
    assign do_read = rd_en && ~empty;


    // Write side
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wptr <= '0;
        end else if (do_write) begin
            // TODO: store din in mem at the slot wptr points to, then advance wptr
            mem[wptr[AW-1:0]] <= din;
            wptr <= wptr + 1;
        end
    end

    // Read side. dout is REGISTERED: after an accepted read, the word appears on dout
    // one clock edge later (the edge that accepts the read). dout holds its value otherwise.
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            rptr <= '0;
            dout <= '0;
        end else if (do_read) begin
            // TODO: load dout from mem at the slot rptr points to, then advance rptr
            dout <= mem[rptr[AW-1:0]];
            rptr <= rptr + 1;
        end
    end

endmodule
