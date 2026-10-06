package cwrupio_pkg;

  localparam int INSTR_WIDTH = 16;
  localparam int DATA_WIDTH  = 8;
  localparam int IMEM_DEPTH = 32;  // Placeholder: depth TBD (determines how much will we allocate for memory, utilize SRAM macros later on)
  localparam int IMEM_ADDR_WITH = $clog2(IMEM_DEPTH); 

  typedef enum logic [3:0] {
    OP_HALT     = 4'b0,
    OP_SET      = 4'h1
    OP_WAIT     = 4'h2
    OP_LOAD_TX  = 4'h3,
    OP_OUT_BIT  = 4'h4,
    OP_SHIFT_TX = 4'h5,
    OP_CLEAR_RX = 4'h6,
    OP_SAMPLE   = 4'h7,
    OP_COUNT    = 4'h8,
    OP_LOOP     = 4'h9,
    OP_JUMP     = 4'hA
  } opcode_t;

endpackage : cwrupio_pkg