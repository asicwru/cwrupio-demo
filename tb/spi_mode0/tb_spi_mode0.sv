`default_nettype none
`timescale 1ns / 1ps

// Wraps cwrupio_top and models the pads: a driven pin shows pin_out,
// an undriven pin shows the external value that cocotb drives on ext_in.
module tb_spi_mode0 ();

  initial begin
    $dumpfile("tb_spi_mode0.fst");
    $dumpvars(0, tb_spi_mode0);
  end

  logic clk;
  logic rst_n;
  logic host_sck;
  logic host_cs_n;
  logic host_mosi;
  logic host_miso;
  logic [3:0] ext_in;
  logic [3:0] pin_in;
  logic [3:0] pin_out;
  logic [3:0] pin_oe;
  logic [3:0] pad;

  assign pad = (pin_oe & pin_out) | (~pin_oe & ext_in);
  assign pin_in = pad;

  cwrupio_top dut (
      .clk(clk),
      .rst_n(rst_n),
      .host_sck(host_sck),
      .host_cs_n(host_cs_n),
      .host_mosi(host_mosi),
      .host_miso(host_miso),
      .pin_in(pin_in),
      .pin_out(pin_out),
      .pin_oe(pin_oe)
  );

endmodule
