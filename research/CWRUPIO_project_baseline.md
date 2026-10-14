# CWRUPIO — Project Specification and Context

Status: draft, not frozen. Last updated: 2026-10-14.

This file records the decisions, architecture, and open items of the CWRUPIO project so far. Load it at the start of a new conversation (with a person or an AI assistant) to continue the work with the same context.

---

## 0. Instructions for an assistant loading this file

1. **Writing style.** Use ASD-STE100 (Simplified Technical English) as a guide:
   - Short sentences. Active voice.
   - Consistent terminology: one term for one thing. Use the signal and module names in this file exactly.
   - Relax the STE vocabulary rules when they make an explanation awkward.
   - Keep technical precision. State uncertainty explicitly. Mark assumptions as assumptions.
   - Define terms and notation explicitly. Do not replace precise terms with analogies or slang.
2. **Output format.** Prefer structured, reference-style output: tables, headings, documentation-ready Markdown.
3. **Design ownership.** Base suggestions on this design. Do not import ideas from reference projects (for example, Loom) unless the team asks. If a reference project seems relevant, say so and ask first.
4. **Frozen vs. open.** Treat everything marked *proposed*, *assumed*, or *open* as changeable. Do not present it as decided.

---

## 1. Project context

| Item | Value |
|---|---|
| Project name | CWRUPIO |
| Purpose | Entry in Jane Street's protocol emulator ASIC competition |
| ASIC target | Tiny Tapeout, IHP 130 nm |
| Submission deadline | 2027-01-18 |
| Working repository | `CWRUPIO-demo` (practice build: SPI first, then more protocols) |
| Team structure | Separate Digital Design and Digital Verification teams |
| Implementation order | FPGA first, then ASIC |
| First milestone | SPI Mode 0 working on the CWRUPIO datapath (FPGA) |
| Software reference model | Not used for now (decided) |

### Concept

CWRUPIO is a small programmable I/O controller. A short program in instruction memory controls four logical pins. The hardware is protocol-independent; the program defines the protocol. SPI is the first protocol. UART and I2C come later.

---

## 2. Notation

| Notation | Meaning |
|---|---|
| `A.x → B.y` | Output port `x` of module `A` drives input port `y` of module `B` |
| `A` (width) | Instruction-address width, `A = $clog2(depth)`. Memory depth is open. |
| Pulse | Signal asserted for exactly one clock cycle per instruction |
| Field | Value valid in the same cycle as its pulse; ignored otherwise |
| Level | Signal that holds its value across cycles |

All sequential modules also take `clk` and `rst`. Port lists below omit them.

---

## 3. Logical pins

| Pin | SPI role | Direction | Output enable |
|---|---|---|---|
| P0 | SCLK | Output | 1 |
| P1 | MOSI | Output | 1 |
| P2 | MISO | Input | 0 |
| P3 | CS (active low) | Output | 1 |

`pin_oe[3:0] = 4'b1011`, static for SPI. `fpga_top` maps P0–P3 to physical pins.

---

## 4. Instruction set (proposed, not frozen)

Each instruction is one 16-bit word. Bits `[15:12]` hold the opcode. A required-zero bit that is nonzero causes a fault. Opcodes `0xB`–`0xF` are unsupported and cause a fault.

| Instruction | Name | Description | Opcode |
|---|---|---|---|
| `HALT` | Halt | Stop execution and assert `done`. Pins keep their values. | `0x0` |
| `SET pin, value` | Set pin | Write 0 or 1 to the output register of a pin. | `0x1` |
| `WAIT cycles` | Wait | Stall for a number of system-clock cycles (1–4095). | `0x2` |
| `LOAD_TX` | Load TX | Copy the host byte into the TX shift register. | `0x3` |
| `OUT_BIT pin` | Output bit | Write `tx_reg[7]` to the output register of a pin. | `0x4` |
| `SHIFT_TX` | Shift TX | Shift the TX shift register left by one bit; insert 0 at bit 0. | `0x5` |
| `CLEAR_RX` | Clear RX | Set the RX shift register to `0x00`. | `0x6` |
| `SAMPLE pin` | Sample | Shift the RX shift register left; insert the pin value at bit 0. | `0x7` |
| `COUNT n` | Count | Load the loop counter with `n` (1–255). | `0x8` |
| `LOOP address` | Loop | Decrement the loop counter; branch to `address` if the count before the decrement is greater than 1. | `0x9` |
| `JUMP address` | Jump | Branch to `address` unconditionally. Optional; not used by the SPI program. | `0xA` |

### Encodings

| Instruction | Layout | Status |
|---|---|---|
| `HALT` | `0x0000` (all bits 0). A cleared memory word halts. | From `isa.md` |
| `SET` | `[15:12]=0001`, `[11:3]=0`, `[2:1]=pin`, `[0]=value`. Example: `SET P3, 0` = `0x1006` | From `isa.md` |
| `WAIT` | `[15:12]=0010`, `[11:0]=cycles`. `WAIT 0` faults. Example: `WAIT 100` = `0x2064` | From `isa.md` |
| `OUT_BIT`, `SAMPLE` | `[2:1]=pin`; `[11:3]` and `[0]` must be 0 | **Assumed** — check `isa.md` |
| `LOAD_TX`, `SHIFT_TX`, `CLEAR_RX` | `[11:0]` must be 0 | **Assumed** — check `isa.md` |
| `COUNT` | `[7:0]=n`; `[11:8]` must be 0; `n = 0` faults | **Assumed** — check `isa.md` |
| `LOOP`, `JUMP` | `[7:0]=address`; `[11:8]` must be 0 | **Assumed** — check `isa.md` |

Address field is `[7:0]`. If memory depth is less than 256 words, the unused upper address bits must be 0 (else fault).

### Primitives implemented by the ISA

| Primitive | Instructions |
|---|---|
| Drive a pin to a fixed level | `SET` |
| Hold a state for a defined time | `WAIT` |
| Serialize a byte | `LOAD_TX`, `OUT_BIT`, `SHIFT_TX` |
| Deserialize a byte | `CLEAR_RX`, `SAMPLE` |
| Repeat a step a fixed number of times | `COUNT`, `LOOP` |
| Repeat a program | `JUMP` |
| End a transfer and report it | `HALT` |

`SHIFT_TX` and `OUT_BIT` are separate on purpose: a program can change the data pin at a different time than it shifts the register.

---

## 5. SPI Mode 0 program (`programs/spi/mode0_transfer.asm`, reference form)

Verify against the file in the repository.

```text
        LOAD_TX            ; tx_reg <- host byte
        CLEAR_RX           ; rx_reg <- 0x00
        OUT_BIT P1         ; MOSI <- bit 7, before CS asserts
        SET     P3, 0      ; CS low
        WAIT    H          ; CS setup time
        COUNT   8          ; 8 bits
bit_loop:
        SET     P0, 1      ; SCLK rises; both sides sample
        SAMPLE  P2         ; rx_reg <- {rx_reg[6:0], MISO}
        WAIT    H          ; high half-period
        SET     P0, 0      ; SCLK falls; peripheral changes MISO
        SHIFT_TX           ; next bit to tx_reg[7]
        OUT_BIT P1         ; MOSI <- next bit
        WAIT    H          ; low half-period
        LOOP    bit_loop   ; branch while pre-decrement count > 1
        SET     P3, 1      ; CS high
        HALT
```

Hand trace (TX `0xA5`, peripheral returns `0x3C`): MOSI carries `10100101`, RX ends at `0x3C`. Mode 0 checks pass: CS low before the first edge, first MOSI bit valid before the first rising edge, MOSI changes only in the low phase, 8 rising edges, MSB first. Simulation is still required.

**Duty cycle note.** The high phase executes 3 instructions; the low phase executes 5. Equal `WAIT H` values give a low phase longer than the high phase. SPI requires minimum high and low times, not 50% duty cycle.

---

## 6. Architecture

### 6.1 Module list

| Module | File | Function | Type |
|---|---|---|---|
| Package | `rtl/cwrupio_pkg.sv` | Opcode constants, field positions, address-width parameter `A` | Package |
| Top | `rtl/cwrupio_top.sv` | Connects all modules; exposes logical pins and host interface | Structural |
| Host interface | `rtl/host_interface.sv` | Supplies byte, `start`, `entry_addr`; returns `rx_data` and status | Sequential |
| Program counter | `rtl/program_counter.sv` | Holds `pc`; selects next PC from `pc_sel` | Sequential |
| Instruction decoder | `rtl/instruction_decoder.sv` | Extracts fields; detects static faults (`illegal`); generates pulses gated by `exec_en` | Combinational |
| Sequencer | `rtl/sequencer.sv` | FSM (`IDLE`, `EXEC`, `STALL`); selects `pc_sel`; drives `busy`, `done`, `fault`; detects dynamic faults | Sequential |
| Instruction memory | `rtl/instruction_memory.sv` | Program storage addressed by `pc` | Memory |
| TX shift register | `rtl/tx_shift_register.sv` | Parallel-in, serial-out; `tx_bit = tx_reg[7]` | Sequential (execution unit) |
| RX shift register | `rtl/rx_shift_register.sv` | Serial-in, parallel-out | Sequential (execution unit) |
| Pin control | `rtl/pin_control.sv` | Output registers, write-value mux, sample mux, output enables | Sequential (execution unit) |
| Timing unit | `rtl/timing_unit.sv` | Counts system-clock cycles for `WAIT` | Sequential (execution unit) |
| Loop counter | `rtl/loop_counter.sv` | Holds and decrements the iteration count | Sequential (execution unit) |

**Decision: separate control modules.** The program counter, instruction decoder, and sequencer are separate modules. `cwrupio_top` instantiates them directly; no wrapper module groups them. Reasons: the decoder is purely combinational and can be tested exhaustively (all 65,536 words); static and dynamic faults go to different modules; design and verification teams can work in parallel against frozen interfaces.

**Decision: no ALU.** The ISA has no arithmetic or logic operations on general registers. The execution units (TX, RX, pin control, timing unit, loop counter) are the "ALU equivalent". The only arithmetic is the loop-counter decrement and `pc + 1`.

**Why a timing unit and a loop counter.** Both save instruction words. `WAIT n` replaces up to 4095 idle cycles with one word. `COUNT`/`LOOP` replaces 8 copies of the bit sequence with one. The two counters run at the same time (bit count and half-period), so they cannot share one counter.

### 6.2 Ports and bus widths

**`host_interface`** (CWRUPIO side; host side not defined yet)

| Direction | Signals |
|---|---|
| Out | `start`, `entry_addr[A-1:0]`, `tx_data[7:0]` |
| In | `busy`, `done`, `fault`, `rx_data[7:0]` |

**`program_counter`**

| Direction | Signals |
|---|---|
| In | `pc_sel[1:0]`, `entry_addr[A-1:0]`, `target[A-1:0]` |
| Out | `pc[A-1:0]` (= `imem_addr`) |

| `pc_sel` | Name | Next PC |
|---|---|---|
| `2'b00` | `HOLD` | `pc` |
| `2'b01` | `INC` | `pc + 1` |
| `2'b10` | `TARGET` | `target` |
| `2'b11` | `ENTRY` | `entry_addr` |

**`instruction_memory`**

| Direction | Signals |
|---|---|
| In | `imem_addr[A-1:0]` |
| Out | `instruction[15:0]` |

**`instruction_decoder`**

| Direction | Signals |
|---|---|
| In | `instruction[15:0]`, `exec_en` |
| Out → execution units | `tx_load`, `tx_shift`, `rx_clear`, `rx_sample`, `sample_pin[1:0]`, `pin_write`, `pin_id[1:0]`, `pin_value`, `pin_use_tx`, `timer_start`, `timer_cycles[11:0]`, `count_load`, `count_value[7:0]`, `count_dec` |
| Out → sequencer | `is_halt`, `is_wait`, `is_loop`, `is_jump`, `illegal` |
| Out → PC | `target[A-1:0]` |

Each pulse = `exec_en & ~illegal & (opcode match)`. `illegal` covers unsupported opcodes, nonzero reserved bits, `WAIT 0`, `COUNT 0`, and address bits above `A-1`. The `is_*` flags must depend only on `instruction`, never on `exec_en` (else a combinational loop forms).

**`sequencer`**

| Direction | Signals |
|---|---|
| In | `start`, `is_halt`, `is_wait`, `is_loop`, `is_jump`, `illegal`, `timer_done`, `count_is_one`, `count_is_zero` |
| Out | `exec_en`, `pc_sel[1:0]`, `busy`, `done`, `fault` |

**`tx_shift_register`**

| Direction | Signals |
|---|---|
| In | `tx_data[7:0]`, `tx_load`, `tx_shift` |
| Out | `tx_bit` (= `tx_reg[7]`) |

Operations: `tx_load`: `tx_reg <= tx_data`. `tx_shift`: `tx_reg <= {tx_reg[6:0], 1'b0}`.

**`rx_shift_register`**

| Direction | Signals |
|---|---|
| In | `rx_clear`, `rx_sample`, `sample_bit` |
| Out | `rx_data[7:0]` (= `rx_reg`) |

Operations: `rx_clear`: `rx_reg <= 8'h00`. `rx_sample`: `rx_reg <= {rx_reg[6:0], sample_bit}`.

**`pin_control`**

| Direction | Signals |
|---|---|
| In | `pin_write`, `pin_id[1:0]`, `pin_value`, `pin_use_tx`, `tx_bit`, `sample_pin[1:0]`, `pin_in[3:0]` |
| Out | `pin_out[3:0]`, `pin_oe[3:0]`, `sample_bit` |

On `pin_write`: `pin_out[pin_id] <= pin_use_tx ? tx_bit : pin_value`. Always: `sample_bit = pin_in[sample_pin]`.

**`timing_unit`**

| Direction | Signals |
|---|---|
| In | `timer_start`, `timer_cycles[11:0]` |
| Out | `timer_done` |

**`loop_counter`**

| Direction | Signals |
|---|---|
| In | `count_load`, `count_value[7:0]`, `count_dec` |
| Out | `count_is_one`, `count_is_zero` |

### 6.3 Connection list (in order of first use in an SPI transfer)

| # | Source.port → Destination.port | Width | Type |
|---|---|---|---|
| 1 | `host_interface.start` → `sequencer.start` | 1 | Control |
| 2 | `host_interface.entry_addr` → `program_counter.entry_addr` | A | Control |
| 3 | `sequencer.pc_sel` → `program_counter.pc_sel` | 2 | Control |
| 4 | `sequencer.busy`, `.done`, `.fault` → `host_interface` | 1 each | Status |
| 5 | `program_counter.pc` → `instruction_memory.imem_addr` | A | Control |
| 6 | `instruction_memory.instruction` → `instruction_decoder.instruction` | 16 | Data |
| 7 | `instruction_decoder.is_halt`, `.is_wait`, `.is_loop`, `.is_jump`, `.illegal` → `sequencer` | 1 each | Status |
| 8 | `sequencer.exec_en` → `instruction_decoder.exec_en` | 1 | Control |
| 9 | `host_interface.tx_data` → `tx_shift_register.tx_data` | 8 | Data |
| 10 | `instruction_decoder.tx_load`, `.tx_shift` → `tx_shift_register` | 1 each | Control |
| 11 | `tx_shift_register.tx_bit` → `pin_control.tx_bit` | 1 | Data |
| 12 | `instruction_decoder.rx_clear`, `.rx_sample` → `rx_shift_register` | 1 each | Control |
| 13 | `instruction_decoder.pin_write`, `.pin_id`, `.pin_value`, `.pin_use_tx`, `.sample_pin` → `pin_control` | 1, 2, 1, 1, 2 | Control |
| 14 | `instruction_decoder.timer_start`, `.timer_cycles` → `timing_unit` | 1, 12 | Control |
| 15 | `timing_unit.timer_done` → `sequencer.timer_done` | 1 | Status |
| 16 | `instruction_decoder.count_load`, `.count_value`, `.count_dec` → `loop_counter` | 1, 8, 1 | Control |
| 17 | `pin_control.sample_bit` → `rx_shift_register.sample_bit` | 1 | Data |
| 18 | `instruction_decoder.target` → `program_counter.target` | A | Control |
| 19 | `loop_counter.count_is_one`, `.count_is_zero` → `sequencer` | 1 each | Status |
| 20 | `rx_shift_register.rx_data` → `host_interface.rx_data` | 8 | Data |
| — | `pin_control.pin_out[0,1,3]` → SCLK, MOSI, CS; MISO → `pin_control.pin_in[2]` | 1 each | Data |

### 6.4 Control signals

| Signal | Type | Target | Asserted by |
|---|---|---|---|
| `tx_load` | Pulse | TX | `LOAD_TX` |
| `tx_shift` | Pulse | TX | `SHIFT_TX` |
| `rx_clear` | Pulse | RX | `CLEAR_RX` |
| `rx_sample` | Pulse | RX | `SAMPLE` |
| `sample_pin` | Field | Pin control | `SAMPLE` |
| `pin_write` | Pulse | Pin control | `SET`, `OUT_BIT` |
| `pin_id` | Field | Pin control | `SET`, `OUT_BIT` |
| `pin_value` | Field | Pin control | `SET` |
| `pin_use_tx` | Field | Pin control | `OUT_BIT` (1), `SET` (0) |
| `timer_start` | Pulse | Timing unit | `WAIT`, first cycle only |
| `timer_cycles` | Field | Timing unit | `WAIT` |
| `count_load` | Pulse | Loop counter | `COUNT` |
| `count_value` | Field | Loop counter | `COUNT` |
| `count_dec` | Pulse | Loop counter | `LOOP` |
| `busy` | Level | Host | 1 while a program runs |
| `done` | Level | Host | `HALT`; holds until next `start` |
| `fault` | Level | Host | Fault; holds until next `start` |

### 6.5 Sequencer behavior

| State / condition | `exec_en` | `pc_sel` | Next state / effect |
|---|---|---|---|
| `IDLE`, `start = 0` | 0 | `HOLD` | `IDLE` |
| `IDLE`, `start = 1` | 0 | `ENTRY` | `EXEC`; clear `done`, `fault` |
| `EXEC`, `illegal` or (`is_loop & count_is_zero`) | 0 | `HOLD` | `IDLE`; set `fault` |
| `EXEC`, `is_halt` | 1 | `HOLD` | `IDLE`; set `done` |
| `EXEC`, `is_wait` | 1 | `HOLD` | `STALL` |
| `EXEC`, `is_loop & count_is_one` | 1 | `INC` | `EXEC` |
| `EXEC`, `is_loop & ~count_is_one` | 1 | `TARGET` | `EXEC` |
| `EXEC`, `is_jump` | 1 | `TARGET` | `EXEC` |
| `EXEC`, other instruction | 1 | `INC` | `EXEC` |
| `STALL`, `timer_done = 0` | 0 | `HOLD` | `STALL` |
| `STALL`, `timer_done = 1` | 0 | `INC` | `EXEC` |

`busy = (state != IDLE)`. `exec_en = 0` in `STALL` guarantees one `timer_start` pulse per `WAIT`.

### 6.6 RTL rules

- Pulses are combinational outputs of `state` and `instruction` (`always_comb`). `state`, `pc`, `done`, `fault` are registered (`always_ff`). Registered pulses would arrive one cycle late.
- Every state-changing control fires once per instruction.
- `LOOP` reads `count_is_one` in the same cycle that it asserts `count_dec`. The loop counter updates on the clock edge, after the flag is sampled.
- PC overflow (`pc = depth − 1` with no branch or `HALT`) is not handled. Decide: fault or wrap.

---

## 7. SPI byte transfer walkthrough

Example: host sends `0xA5`, peripheral returns `0x3C`, Mode 0, MSB first.

**Start.** *The host gives CWRUPIO a byte and tells it to run.* `host_interface.tx_data → tx_shift_register.tx_data` = `0xA5`. `host_interface.entry_addr → program_counter.entry_addr`. `host_interface.start → sequencer.start` = 1. The sequencer leaves `IDLE` and drives `sequencer.pc_sel → program_counter.pc_sel` = `ENTRY`. `sequencer.busy → host_interface.busy` = 1.

**Fetch, every instruction.** *CWRUPIO reads one instruction, identifies it, and selects the next.* `program_counter.pc → instruction_memory.imem_addr`. `instruction_memory.instruction → instruction_decoder.instruction`. `instruction_decoder.is_* / .illegal → sequencer`. `sequencer.exec_en → instruction_decoder.exec_en`. `sequencer.pc_sel → program_counter.pc_sel`, normally `INC`.

**Setup.** *Prepare data, put the first bit on MOSI, select the peripheral, wait, set the bit count.* `LOAD_TX` (`tx_load`) loads `0xA5`; `tx_bit → pin_control.tx_bit` = `tx_reg[7]` from then on. `CLEAR_RX` (`rx_clear`) sets `rx_reg = 0x00`. `OUT_BIT P1` (`pin_write`, `pin_id = 1`, `pin_use_tx = 1`) sets MOSI = 1. `SET P3, 0` (`pin_write`, `pin_id = 3`, `pin_value = 0`) drives CS low. `WAIT H` (`timer_start`, `timer_cycles = H`) puts the sequencer in `STALL` with `pc_sel = HOLD`, `exec_en = 0` until `timer_done`. `COUNT 8` (`count_load`, `count_value = 8`).

**Bit loop, 8 iterations.** *Clock rises and both sides read; clock falls and both sides output the next bit.* `SET P0, 1` raises SCLK; the peripheral reads MOSI. `SAMPLE P2` (`sample_pin = 2`, `sample_bit → rx_shift_register.sample_bit`, `rx_sample`) shifts MISO into `rx_reg`. `WAIT H`. `SET P0, 0` lowers SCLK; the peripheral changes MISO. `SHIFT_TX` (`tx_shift`) moves the next bit to `tx_bit`. `OUT_BIT P1` writes it to MOSI. `WAIT H`. `LOOP` (`count_dec`, `target → program_counter.target`): `count_is_one = 0` → `TARGET`; `count_is_one = 1` → `INC`. `count_is_zero` stays 0.

**End.** *Release the peripheral, stop, hand over the result.* `SET P3, 1` drives CS high. `HALT` (`is_halt`) returns the sequencer to `IDLE`, sets `done = 1`, `busy = 0`. The host reads `rx_shift_register.rx_data → host_interface.rx_data` = `0x3C`.

---

## 8. Extension to other protocols

The core is protocol-independent. SPI Modes 1–3 need only a different program. UART and I2C need additions:

| Gap | Needed by | Possible change |
|---|---|---|
| LSB-first bit order | UART, some SPI devices | Direction control on TX/RX shift registers, or LSB-first instruction variants |
| Wait on a pin value | UART RX (start bit), I2C clock stretching | New stall instruction on `pin_in[p]`, likely with timeout |
| Branch on a pin or bit value | I2C ACK/NACK | New conditional branch |
| Dynamic output enable / open drain | I2C | Writable `pin_oe` or per-pin open-drain mode |
| Multi-byte transfers | All protocols | Per-byte host handshake or small TX/RX FIFOs |

Expected module impact: decoder, sequencer, pin control, shift registers, host interface change. PC, instruction memory, timing unit, loop counter should not change. Free opcodes: `0xB`–`0xF`. Decide UART/I2C additions before freezing the encoding.

---

## 9. Repository structure (`CWRUPIO-demo`)

```text
cwrupio-demo/
├── README.md
├── .gitignore                        # build/, *.vcd, *.fst, tool run directories
├── docs/
│   ├── architecture.md               # Module map, signal connections, pin roles
│   ├── isa.md                        # Opcodes, encodings, timing contract
│   └── fpga_bringup.md               # Board setup, pin mapping, test procedure
├── programs/
│   ├── README.md
│   └── spi/
│       └── mode0_transfer.asm
├── rtl/
│   ├── cwrupio_pkg.sv
│   ├── cwrupio_top.sv
│   ├── program_counter.sv
│   ├── instruction_decoder.sv
│   ├── sequencer.sv
│   ├── instruction_memory.sv
│   ├── host_interface.sv
│   ├── timing_unit.sv
│   ├── loop_counter.sv
│   ├── tx_shift_register.sv
│   ├── rx_shift_register.sv
│   └── pin_control.sv
├── tb/
│   └── README.md
├── synth/
│   ├── fpga/<board>/                 # fpga_top.sv, demo_control.sv, constraints, build script
│   └── ihp-cmos5l/                   # ASIC wrapper and config come later
└── build/                            # Generated; ignored by Git
```

Notes: `<board>` is a placeholder until the FPGA board is chosen. `.asm` → `.hex` conversion: either an assembler in `tools/`, or hand-encoded `.hex` next to the `.asm`. Empty folders need a `.gitkeep`.

---

## 10. Open items

| Item | Effect |
|---|---|
| Instruction-memory depth | Sets `A` and all address widths |
| Memory read latency (async vs. sync) | Sync read adds a fetch state to the sequencer |
| Cycle timing of each instruction | Sets SCLK half-periods and duty cycle |
| Exact `WAIT n` cycle count (start and completion cycle) | TBD in timing contract |
| Encodings of instructions other than `HALT`, `SET`, `WAIT` | Assumed; verify against `isa.md` |
| `LOOP` with count 0 | Draft treats it as a fault (only use of `count_is_zero`) |
| PC overflow | Fault or wrap |
| Reset values of `pin_out` (idle levels: CS high, SCLK low for Mode 0) | Not decided |
| MISO synchronizer (2 flip-flops on `pin_in[2]`) | Adds 2-cycle latency; timing contract must include it |
| Host side of `host_interface` | Not defined |
| FPGA board | Sets `fpga_top`, constraints, build flow |
| Keep or drop `JUMP` | Not used by SPI |
| Assembler vs. hand-encoded hex | Decides whether `tools/` exists |
