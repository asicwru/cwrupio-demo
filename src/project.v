/*
 * Copyright (c) 2026 ASICWRU
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

// Tiny Tapeout wrapper for CWRUPIO.
// Pin map:
//   ui_in[0]  host_sck      host link (configuration port), SPI target, mode 0
//   ui_in[1]  host_cs_n
//   ui_in[2]  host_mosi
//   uo_out[0] host_miso
//   uo_out[7:1] unused (0); status is read over the host link (STATUS register)
//   uio[3:0]  P0-P3         programmable protocol pins (direction from PIN_DIR)
//   uio[7:4]  unused (inputs)
module tt_um_asicwru_cwrupio (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  wire       host_miso;
  wire [3:0] pin_out;
  wire [3:0] pin_oe;

  cwrupio_top u_cwrupio_top (
      .clk      (clk),
      .rst_n    (rst_n),
      .host_sck (ui_in[0]),
      .host_cs_n(ui_in[1]),
      .host_mosi(ui_in[2]),
      .host_miso(host_miso),
      .pin_in   (uio_in[3:0]),
      .pin_out  (pin_out),
      .pin_oe   (pin_oe)
  );

  assign uo_out  = {7'b0000000, host_miso};
  assign uio_out = {4'b0000, pin_out};
  assign uio_oe  = {4'b0000, pin_oe};

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, ui_in[7:3], uio_in[7:4], 1'b0};

endmodule
