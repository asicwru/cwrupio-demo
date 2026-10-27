module sequencer import cwrupio_pkg::*; #(
    parameter int TIMER_WIDTH = 12, // same as timing_unit
    parameter int LOOP_WIDTH = 8 // same as loop_counter
)(
    input logic clk,
    input logic rst_n,

    // host interface
    input logic start, // 1-cycle pulse, ignored while busy
    output logic busy,
    output logic done, // level, set by HALT or fault, cleared by start
    output logic fault, // level, set by fault, cleared by start

    // instruction decoder
    input opcode_t opcode,
    input logic [TIMER_WIDTH-1:0] wait_cycles,
    input logic [LOOP_WIDTH-1:0] count_value,

    // program counter
    output pc_sel_t pc_sel,

    // timing unit
    input logic timer_done, // 1-cycle pulse on the last WAIT cycle
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
    output logic rx_clear, // rx_shift_reg has no clear input yet
    output logic rx_shift,

    // pin control
    output logic pin_set,
    output logic pin_out_bit
);

    typedef enum logic [1:0] {
        S_IDLE = 2'b00, // wait for start, PC held at 0
        S_EXEC = 2'b01, // execute instruction at pc in 1 cycle
        S_STALL = 2'b10, // WAIT in progress
        S_FAULT = 2'b11 // stopped on a fault, wait for start
    } state_t;

    state_t state;
    state_t next_state;

    logic set_done; // from EXEC on HALT
    logic set_fault; // from EXEC on a fault
    logic accept_start; // start is accepted only in S_IDLE or S_FAULT

    assign accept_start = start && ((state == S_IDLE) || (state == S_FAULT));
    assign busy = (state == S_EXEC) || (state == S_STALL);

    // state register
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
        end 
        else begin
            state <= next_state;
        end
    end

    // status registers (done, fault)
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            done <= 1'b0;
            fault <= 1'b0;
        end 
        else if (accept_start) begin
            done <= 1'b0;
            fault <= 1'b0;
        end 
        else if (set_fault) begin
            done <= 1'b1;
            fault <= 1'b1;
        end 
        else if (set_done) begin
            done <= 1'b1;
        end
    end

    // next state and control outputs
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
            S_IDLE, S_FAULT: begin
                pc_sel = PC_START; // pc = 0 when the program starts
                if (accept_start) begin
                    next_state = S_EXEC;
                end
            end
            S_EXEC: begin
                case (opcode)
                    OP_HALT: begin
                        set_done = 1'b1;
                        next_state = S_IDLE;
                    end
                    OP_SET: begin
                        pin_set = 1'b1;
                        pc_sel = PC_INC;
                    end
                    OP_WAIT: begin
                        if (wait_cycles == '0) begin
                            set_fault = 1'b1;
                            next_state = S_FAULT;
                        end 
                        else if (wait_cycles == TIMER_WIDTH'(1)) begin
                            pc_sel = PC_INC; // WAIT 1 is this cycle only
                        end 
                        else begin
                            timer_start = 1'b1;
                            next_state = S_STALL;
                        end
                    end
                    OP_LOAD_TX: begin
                        tx_load = 1'b1;
                        pc_sel = PC_INC;
                    end
                    OP_OUT_BIT: begin
                        pin_out_bit = 1'b1;
                        pc_sel = PC_INC;
                    end
                    OP_SHIFT_TX: begin
                        tx_shift = 1'b1;
                        pc_sel = PC_INC;
                    end
                    OP_CLEAR_RX: begin
                        rx_clear = 1'b1;
                        pc_sel = PC_INC;
                    end
                    OP_SAMPLE: begin
                        rx_shift = 1'b1;
                        pc_sel = PC_INC;
                    end
                    OP_COUNT: begin
                        if (count_value == '0) begin
                            set_fault = 1'b1;
                            next_state = S_FAULT;
                        end 
                        else begin
                            count_ld = 1'b1;
                            pc_sel = PC_INC;
                        end
                    end
                    OP_LOOP: begin
                        if (count_is_zero) begin
                            set_fault = 1'b1;
                            next_state = S_FAULT;
                        end 
                        else if (count_is_one) begin
                            count_dec = 1'b1;
                            pc_sel = PC_INC;
                        end 
                        else begin
                            count_dec = 1'b1;
                            pc_sel = PC_BRANCH;
                        end
                    end
                    OP_JUMP: begin
                        pc_sel = PC_BRANCH;
                    end
                    default: begin
                        // opcodes 0xB-0xF are unsupported
                        set_fault = 1'b1;
                        next_state = S_FAULT;
                    end
                endcase
            end
            S_STALL: begin
                if (timer_done) begin
                    pc_sel = PC_INC;
                    next_state = S_EXEC;
                end
            end
            default: begin
                next_state = S_IDLE;
            end
        endcase
    end

endmodule
