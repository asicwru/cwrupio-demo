
module fifo_system #(
    parameter int DEPTH = 8
) (
    input logic clk,
    input logic rst_n,

    // Transmit interface: Host -> TX FIFO -> Engine
    input logic tx_wr_en,
    input logic tx_rd_en,
    input logic [7:0] tx_din,
    output logic [7:0] tx_dout,
    output logic tx_empty,
    output logic tx_full,

    // Receive interface: Engine -> RX FIFO -> Host
    input logic rx_wr_en,
    input logic rx_rd_en,
    input logic [7:0] rx_din,
    output logic [7:0] rx_dout,
    output logic rx_empty,
    output logic rx_full
);

    // Transmit FIFO
    fifo #(
        .DEPTH(DEPTH),
        .DWIDTH(8)
    ) tx_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(tx_wr_en),
        .rd_en(tx_rd_en),
        .din(tx_din),
        .dout(tx_dout),
        .empty(tx_empty),
        .full(tx_full)
    );

    // Receive FIFO
    fifo #(
        .DEPTH(DEPTH),
        .DWIDTH(8)
    ) rx_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(rx_wr_en),
        .rd_en(rx_rd_en),
        .din(rx_din),
        .dout(rx_dout),
        .empty(rx_empty),
        .full(rx_full)
    );

endmodule
