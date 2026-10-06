# CWRUPIO ISA Reference

This is currently **unfinished**. Currently, we have 11 instructions supported by our ISA.

## Instructions

| Instruction | Name |
Description | Opcode |
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
| `JUMP address` | Jump | Branch to `address` unconditionally. | `0xA` |

Opcodes `0xB`–`0xF` are unsupported and cause a fault.

## Conventions

- Each instruction is one 16-bit word. Bits `[15:12]` hold the opcode.
- A `0` in an encoding table is a required zero bit. A nonzero value in that bit causes a fault.
- `pin` is a logical pin number, 0–3 (P0–P3).
- In the **Implementation** lines, `pc = pc + 1` follows every instruction unless the line changes `pc` or stops execution.
- `pin_out[p]` is the output register of pin `p`. `pin_in[p]` is the input value of pin `p`.
- The address field is `[7:0]`. If the instruction-memory depth is less than 256 words, the unused upper address bits must be 0.

## Logical pins

| Pin | SPI role | Direction |
|---|---|---|
| P0 | SCLK | Output |
| P1 | MOSI | Output |
| P2 | MISO | Input |
| P3 | CS (active low) | Output |

---

## halt

halt execution.

| 15-12 | 11-8 | 7-3 | 2 | 1 | 0 |
|---|---|---|---|---|---|
| 0000 | 0000 | 00000 | 0 | 0 | 0 |

**Format**


`HALT`


**Description**


Stops execution, asserts `done`, and deasserts `busy`. The output pins keep their programmed values. The program must set the pins to their idle state before `HALT`. The host reads `rx_data` after `done` asserts. The encoding is `0x0000`, so a cleared memory word halts execution.


**Implementation**
`done = 1; busy = 0`

## set

set pin.

| 15-12 | 11-8 | 7-3 | 2 | 1 | 0 |
|---|---|---|---|---|---|
| 0001 | 0000 | 00000 | pin[1] | pin[0] | value |

**Format**


`SET pin, value`


**Description**


Writes `value` (0 or 1) to the output register of `pin`. Used for clock edges, select signals, and frame bits. Example: `SET P3, 0` = `0x1006`.


**Implementation**


`pin_out[pin] = value`

## wait

wait cycles.

| 15-12 | 11-8 | 7-3 | 2 | 1 | 0 |
|---|---|---|---|---|---|
| 0010 | cycles[11:8] | cycles[7:3] | cycles[2] | cycles[1] | cycles[0] |

**Format**


`WAIT cycles`


**Description**


Stalls the PC for `cycles` system-clock cycles, 1–4095. Used for clock half-periods, bit periods, and setup and hold times. `WAIT 0` causes a fault. The cycle on which counting starts and completes is TBD. Example: `WAIT 100` = `0x2064`.

**Implementation**
`stall cycles; pc = pc + 1`

## load_tx

load TX shift register.

| 15-12 | 11-8 | 7-3 | 2 | 1 | 0 |
|---|---|---|---|---|---|
| 0011 | 0000 | 00000 | 0 | 0 | 0 |

**Format**


`LOAD_TX`

**Description**


Copies the host byte `tx_data` into the TX shift register. Used once per transmitted byte. Encoding: `0x3000`.

**Implementation**


`tx_reg = tx_data`

## out_bit

output bit.

| 15-12 | 11-8 | 7-3 | 2 | 1 | 0 |
|---|---|---|---|---|---|
| 0100 | 0000 | 00000 | 0 | pin[1] | pin[0] |

**Format**


`OUT_BIT pin`

**Description**


Writes bit 7 of the TX shift register to the output register of `pin`. Used for each data bit, MSB first. `OUT_BIT` does not shift the register. Example: `OUT_BIT P1` = `0x4001`.

**Implementation**


`pin_out[pin] = tx_reg[7]`

## shift_tx

shift TX shift register.

| 15-12 | 11-8 | 7-3 | 2 | 1 | 0 |
|---|---|---|---|---|---|
| 0101 | 0000 | 00000 | 0 | 0 | 0 |

**Format**


`SHIFT_TX`

**Description**


Shifts the TX shift register left by one bit and inserts 0 at bit 0. The next bit moves to bit 7. `SHIFT_TX` does not change any pin; the next `OUT_BIT` writes the new bit. Encoding: `0x5000`.

**Implementation**


`tx_reg = {tx_reg[6:0], 0}`

## clear_rx

clear RX shift register.

| 15-12 | 11-8 | 7-3 | 2 | 1 | 0 |
|---|---|---|---|---|---|
| 0110 | 0000 | 00000 | 0 | 0 | 0 |

**Format**


`CLEAR_RX`

**Description**


Sets the RX shift register to `0x00`. Used once before each received byte. Encoding: `0x6000`.

**Implementation**


`rx_reg = 0`

## sample

sample pin.

| 15-12 | 11-8 | 7-3 | 2 | 1 | 0 |
|---|---|---|---|---|---|
| 0111 | 0000 | 00000 | 0 | pin[1] | pin[0] |

**Format**


`SAMPLE pin`

**Description**


Shifts the RX shift register left by one bit and inserts the value of `pin` at bit 0. After 8 samples, the first sampled bit is at bit 7 (MSB first). If `pin_in` goes through a synchronizer, the sampled value is from 2 or more cycles earlier. Example: `SAMPLE P2` = `0x7002`.

**Implementation**


`rx_reg = {rx_reg[6:0], pin_in[pin]}`

## count

load loop counter.

| 15-12 | 11-8 | 7-3 | 2 | 1 | 0 |
|---|---|---|---|---|---|
| 1000 | 0000 | n[7:3] | n[2] | n[1] | n[0] |

**Format**


`COUNT n`

**Description**


Loads the loop counter with `n`, 1–255. Used before a bit loop; `COUNT 8` gives 8 iterations. `COUNT 0` causes a fault. Example: `COUNT 8` = `0x8008`.

**Implementation**


`count = n`

## loop

loop.

| 15-12 | 11-8 | 7-3 | 2 | 1 | 0 |
|---|---|---|---|---|---|
| 1001 | 0000 | address[7:3] | address[2] | address[1] | address[0] |

**Format**


`LOOP address`

**Description**


Decrements the loop counter. If the count before the decrement is greater than 1, branches to `address`. If the count before the decrement is 1, the counter becomes 0 and execution continues at the next instruction. If the count is 0, the instruction causes a fault. Example: `LOOP 8` = `0x9008`.

**Implementation**


`if (count == 0) fault; count = count - 1; if (count != 0) pc = address`

## jump

jump.

| 15-12 | 11-8 | 7-3 | 2 | 1 | 0 |
|---|---|---|---|---|---|
| 1010 | 0000 | address[7:3] | address[2] | address[1] | address[0] |

**Format**


`JUMP address`

**Description**


Branches to `address` unconditionally. Optional; the SPI transfer program does not use it. Example: `JUMP 0` = `0xA000`.

**Implementation**


`pc = address`

---

## Faults

The instruction engine asserts `fault` for these conditions:

- Unsupported opcode (`0xB`–`0xF`).
- A nonzero bit in a required-zero position.
- `WAIT 0` or `COUNT 0`.
- `LOOP` when the loop counter is 0.
- A branch address outside the instruction memory.

Fault behavior: TBD.

## Timing

| Item | Value |
|---|---|
| Instruction-memory depth | TBD |
| Instruction-memory read latency | TBD |
| Cycles per instruction | TBD |
| Extra cycles for a taken branch | TBD |
| `WAIT N` start and completion cycles | TBD |
| Input synchronizer latency | TBD |


