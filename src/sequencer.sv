module sequencer import cwrupio_pkg::*; #(
    parameter int TIMER_WIDTH = 12, // same as timing_unit
    parameter int LOOP_WIDTH = 8 // same as loop_counter
)(
    input logic clk,
    input logic rst_n,

    // host interface
    input logic start, // TODO: confirm handshake (1-cycle pulse?)
    output logic busy,
    output logic done,
    output logic fault,

    // instruction decoder
    input opcode_t opcode,
    input logic [TIMER_WIDTH-1:0] wait_cycles,
    input logic [LOOP_WIDTH-1:0] count_value,

    // program counter
    output pc_sel_t pc_sel,

    // timing unit
    input logic timer_done,
    output logic timer_start,

    // loop counter
    input logic count_is_zero,
    input logic count_is_one,
    output logic count_ld,
    output logic count_dec,

    // tx shift register
    output logic tx_load,
    output logic tx_shift,

    // rx shift register
    output logic rx_clear, // TODO: rx_shift_reg has no clear input yet
    output logic rx_shift,

    // pin control
    output logic pin_set,
    output logic pin_out_bit
);

    typedef enum logic [1:0] {
        S_IDLE = 2'b00, // wait for start, PC held at 0
        S_EXEC = 2'b01, // execute instruction at pc in 1 cycle
        S_STALL = 2'b10, // WAIT in progress
        S_FAULT = 2'b11 // TODO: fault response is open
    } state_t;

    state_t state;
    state_t next_state;

    logic set_done; // from EXEC on HALT
    logic set_fault; // from EXEC on a fault

    // ---------------------------------------------------------------
    // State register
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end 
        else begin
            state <= next_state;
        end
    end

    // ---------------------------------------------------------------
    // Status registers (done, fault)
    // ---------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            done <= 1'b0;
            fault <= 1'b0;
        end 
        else begin
            // TODO: set done on set_done, clear it on start
            // TODO: set fault on set_fault, decide when it clears (start? reset only?)
        end
    end

    // TODO: busy = 1 in S_EXEC and S_STALL
    assign busy = 1'b0;

    // ---------------------------------------------------------------
    // Next state and control outputs
    // ---------------------------------------------------------------
    always_comb begin
        // defaults: every strobe is a 1-cycle pulse, PC holds, state holds
        next_state = state;
        pc_sel = PC_HOLD;
        set_done = 1'b0;
        set_fault = 1'b0;
        timer_start = 1'b0;
        count_ld = 1'b0;
        count_dec = 1'b0;
        tx_load = 1'b0;
        tx_shift = 1'b0;
        rx_clear = 1'b0;
        rx_shift = 1'b0;
        pin_set = 1'b0;
        pin_out_bit = 1'b0;

        case (state)
            S_IDLE: begin
                // TODO: drive PC_START every cycle so pc = 0 when the program starts
                // TODO: on start, go to S_EXEC
            end

            S_EXEC: begin
                case (opcode)
                    OP_HALT: begin
                        // TODO: set_done, PC_HOLD, go to S_IDLE
                    end
                    OP_SET: begin
                        // TODO: pin_set, PC_INC
                    end
                    OP_WAIT: begin
                        // TODO: fault if wait_cycles == 0
                        // TODO: timer_start, PC_HOLD, go to S_STALL
                        // TODO: if timer option C, handle WAIT 1 (skip S_STALL)
                    end
                    OP_LOAD_TX: begin
                        // TODO: tx_load, PC_INC
                    end
                    OP_OUT_BIT: begin
                        // TODO: pin_out_bit, PC_INC
                    end
                    OP_SHIFT_TX: begin
                        // TODO: tx_shift, PC_INC
                    end
                    OP_CLEAR_RX: begin
                        // TODO: rx_clear, PC_INC
                    end
                    OP_SAMPLE: begin
                        // TODO: rx_shift, PC_INC
                    end
                    OP_COUNT: begin
                        // TODO: fault if count_value == 0
                        // TODO: count_ld, PC_INC
                    end
                    OP_LOOP: begin
                        // TODO: count_is_zero -> fault
                        // TODO: count_is_one  -> count_dec, PC_INC
                        // TODO: otherwise     -> count_dec, PC_BRANCH
                    end
                    OP_JUMP: begin
                        // TODO: PC_BRANCH
                    end
                    default: begin
                        // TODO: opcodes 0xB-0xF: go to S_FAULT, or act as HALT? (open)
                    end
                endcase
            end

            S_STALL: begin
                // TODO: PC_HOLD while the timer runs
                // TODO: on timer_done, PC_INC and go to S_EXEC
                // TODO: confirm timer option (A: n+2, B: n+1, C: exactly n cycles)
            end

            S_FAULT: begin
                // TODO: decide fault response (stay here until start? until reset?)
            end

            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

endmodule
