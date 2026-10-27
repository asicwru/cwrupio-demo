package cwrupio_pkg;

  localparam INSTRUCTION_WIDTH = 16;
  localparam DATA_WIDTH  = 8;
  localparam IMEM_DEPTH = 32;  // Placeholder: depth TBD (determines how much will we allocate for memory, utilize SRAM macros later on)
  localparam IMEM_ADDR_WIDTH = $clog2(IMEM_DEPTH); 

  typedef enum logic [3:0] {
    OP_HALT = 4'b0,
    OP_SET = 4'h1,
    OP_WAIT = 4'h2,
    OP_LOAD_TX = 4'h3,
    OP_OUT_BIT = 4'h4,
    OP_SHIFT_TX = 4'h5,
    OP_CLEAR_RX = 4'h6,
    OP_SAMPLE = 4'h7,
    OP_COUNT = 4'h8,
    OP_LOOP = 4'h9,
    OP_JUMP = 4'hA
  } opcode_t;

  // Program counter next-state select (driven by the sequencer)
  typedef enum logic [1:0] {
    PC_HOLD   = 2'b00,  // pc_next = pc
    PC_INC    = 2'b01,  // pc_next = pc + 1 (wraps from DEPTH-1 to 0)
    PC_BRANCH = 2'b10,  // pc_next = branch_target
    PC_START  = 2'b11   // pc_next = 0 (fixed program start)
  } pc_sel_t;

endpackage : cwrupio_pkg
