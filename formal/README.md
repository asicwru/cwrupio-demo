# Formal verification

This folder holds formal checks for every module in `src/`, run with
[SymbiYosys](https://github.com/YosysHQ/sby) (`sby`).

- [Quick start](#quick-start)
- [What formal verification is](#what-formal-verification-is)
- [How the checks are built](#how-the-checks-are-built)
- [Run modes: prove, bmc, cover](#run-modes-prove-bmc-cover)
- [What each module checks](#what-each-module-checks)
- [Known gaps vs docs/isa.md (`make spec`)](#known-gaps-vs-docsisamd-make-spec)
- [Reading results and debugging a failure](#reading-results-and-debugging-a-failure)
- [Adding or changing a check](#adding-or-changing-a-check)
- [Gotchas](#gotchas)
- [How we know the checks work](#how-we-know-the-checks-work)

---

## Quick start

### Install the tools (once)

Install the **OSS CAD Suite**. It bundles sby, yosys, the SMT solvers, and the
`yosys-slang` plugin used here to read SystemVerilog.

1. Download the latest build for your machine from
   https://github.com/YosysHQ/oss-cad-suite-build/releases/latest
   (Apple Silicon: `oss-cad-suite-darwin-arm64-YYYYMMDD.tgz`).
2. Extract it and clear the macOS quarantine flag:
   ```sh
   mkdir -p ~/tools
   tar xzf oss-cad-suite-*.tgz -C ~/tools
   cd ~/tools/oss-cad-suite && ./activate
   ```
3. Add it to `PATH` in each terminal where you run formal checks:
   ```sh
   export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
   ```
   Don't add this to `~/.zshrc` permanently. The bundle has its own Python and
   iverilog, which would take priority over the ones your cocotb tests use.

### Run

```sh
cd formal
make                  # every module (should all pass, ~15 s)
make sequencer        # one module
make spec             # ISA rules the RTL doesn't implement yet (fails for now)
make clean            # delete run output
```

A passing run ends each task with `DONE (PASS, rc=0)`.

---

## What formal verification is

A simulation test (like the cocotb tests in `test/` and `tb/`) runs the inputs
you write and checks the results. It only shows the design works for those
inputs.

Formal verification works the other way around. You write rules (**assertions**)
that must always be true, and a SAT/SMT solver searches every possible input
sequence for one that breaks a rule. If it finds one, you get a waveform of
that exact sequence. If it can't, the rule is proven.

| | Simulation (cocotb) | Formal (sby) |
|---|---|---|
| Inputs | Written by you | Every possible value, every cycle |
| Result | "Worked for these tests" | "Proven" or a counterexample waveform |
| Good for | Whole-system behavior, long programs | Small and medium blocks, corner cases |
| Weakness | Misses cases you didn't think of | Blows up on very large designs |

The two complement each other. Formal proves the building blocks are correct,
and cocotb tests real programs running on the whole chip.

### What sby does

1. Reads a `.sby` file listing the source files, the mode, and the solver.
2. Runs yosys to turn the SystemVerilog plus assertions into a flat circuit.
3. Hands that circuit to a solver (`boolector` here).
4. Reports PASS or FAIL. On a failure it writes a `.vcd` waveform.

---

## How the checks are built

### Files

Each module has two files:

| File | Purpose |
|---|---|
| `<module>_props.sv` | The properties (assertions, assumptions, covers) |
| `<module>.sby` | Run config: source files, modes, depth, solver |

Plus `Makefile` and this README.

### The RTL is not modified

The properties live in a separate checker module that is attached to the RTL
with SystemVerilog `bind`:

```systemverilog
bind loop_counter loop_counter_props #(.LOOP_WIDTH(LOOP_WIDTH)) u_props (.*);
```

This places a copy of `loop_counter_props` inside every `loop_counter`. The
`.*` connects every checker port to the signal with the same name in
`loop_counter`, **including internal signals** like the `count` register. So the
checker can see inside the module without any `ifdef FORMAL` code in `src/`.
Synthesis and the Tiny Tapeout flow never read `formal/`, so they don't see it.

### The pieces of a property file

Using `loop_counter_props.sv` as the example:

```systemverilog
// 1. "Has there been a previous cycle?" $past() is meaningless on cycle 0.
logic f_past_valid = 1'b0;
always_ff @(posedge clk) f_past_valid <= 1'b1;

// 2. Assumption: the design starts in reset. Flip-flops power up with any
//    value, so without this the solver would start from garbage states.
always_comb if (!f_past_valid) assume (!rst_n);

// 3. Assertions: rules that must always hold. $past(x) is x one cycle ago.
always_ff @(posedge clk) begin
    if (f_past_valid) begin
        if (!$past(rst_n))
            assert (count == '0);
        else if ($past(count_ld))
            assert (count == $past(count_val));
        ...
    end
end

// 4. Covers: states that must be reachable. If a cover can't be hit, the
//    assumptions are too strict, or the design can't do something it should.
cover (count_is_one && $past(count_dec));
```

| Keyword | Meaning | If it's wrong |
|---|---|---|
| `assert` | Must always be true | sby FAILs with a waveform |
| `assume` | Limits what the solver may try (rules about the inputs) | Too strict and real bugs are hidden; `cover` catches this |
| `cover` | Must be reachable | sby reports it "unreached" and FAILs |

Use assumptions sparingly. The only ones here are "start in reset", the
loop-counter flags in `sequencer_props.sv` (see below), and holding the free
address constant in `instruction_memory_props.sv`.

### Shadow models

Some checks keep a small model of what *should* happen and compare the design
against it. For example, `tx_shift_reg_props.sv` remembers the last byte loaded
(`f_byte`) and how many shifts have happened since (`f_k`), then asserts the
serial output equals `f_byte[7 - f_k]`. That checks the end-to-end
"MSB first" behavior, not just one cycle at a time. Signals that belong only to
the checker are prefixed with `f_`.

### Checking every address with one free variable

`instruction_memory_props.sv` checks "the value read from an address is the
last value written there" for **every** address at once. It tracks one address,
`f_addr`, whose starting value the solver picks freely and which never changes.
Since the solver can pick any address, a pass covers all of them. This avoids
modelling the whole memory.

---

## Run modes: prove, bmc, cover

Each `.sby` file defines tasks (the `[tasks]` section). The Makefile picks
which to run.

| Mode | Question it answers | Used for |
|---|---|---|
| `prove` | Can any assertion **ever** fail? | All modules except the top |
| `bmc` | Can any assertion fail in the first N cycles after reset? | `cwrupio_top` |
| `cover` | Can each `cover` be reached within N cycles? | All modules |

**`prove`** uses *k-induction*, which works in two steps:

1. **Base case:** no assertion fails in the first `depth` cycles after reset.
2. **Induction step:** if all assertions held for `depth` cycles in a row, from
   *any* state, they still hold on the next cycle.

Together these prove the assertions hold forever. Sometimes the induction step
fails on a state that can't actually happen. Then you add more assertions about
internal state to rule it out (see
[Debugging](#reading-results-and-debugging-a-failure)). The helper assertions
in `timing_unit_props.sv` and `tx_shift_reg_props.sv` are there for this.

**`bmc`** (bounded model checking) only does the base case. `cwrupio_top` uses
it because a full proof of the whole chip is too slow. The depth of 60 cycles
is enough for the solver to send a `start` command over SPI (about 35 cycles)
and run a short program. Long WAITs and long programs are covered by the
individual module proofs.

---

## What each module checks

### `loop_counter` (full proof)

- Reset sets the count to 0.
- A load wins when load and decrement happen together.
- A decrement subtracts exactly 1, and never goes below 0.
- Otherwise the count holds.
- `count_is_zero` and `count_is_one` always match the count and are never both 1.

### `program_counter` (full proof)

- Reset sets the PC to 0.
- `PC_HOLD` keeps the PC, `PC_INC` adds 1 (wrapping from 31 to 0), `PC_BRANCH`
  loads `branch_target`, and `PC_START` sets it to 0.

### `tx_shift_reg` (full proof)

- Reset, load, shift (inserting 0), and hold each do the right thing; load wins
  over shift.
- `tx_serial_out` is always bit 7 of the register.
- End to end: after loading byte D and k shifts, the output is `D[7-k]`
  (MSB first), and 0 after all 8 bits are shifted out.

### `rx_shift_reg` (full proof)

- Reset clears it. A shift moves the register left and puts the new bit in
  bit 0, so after 8 shifts the first bit sampled is in bit 7. Otherwise it
  holds.

### `timing_unit` (full proof)

- Reset, start (loads `cycles - 1`), and counting down to 0 without wrapping.
- `timer_done` is 1 exactly when the count is 1.
- End to end: after a start with N ≥ 2, `timer_done` pulses once, exactly N-1
  cycles later. With the start cycle that makes `WAIT N` take N cycles.
- N = 1 never pulses and N = 0 would wrap. The sequencer never starts the timer
  with those values (proven in `sequencer`).

### `instruction_decoder` (full proof, combinational)

- Opcode, `pin_value`, `wait_cycles`, `count_value`, and `branch_target` come
  from the right bits.
- `pin_select` is bits [2:1] for `SET` and bits [1:0] for `OUT_BIT`/`SAMPLE`.
- Every encoding example in `docs/isa.md` decodes as documented
  (`SET P3, 0` = `0x1006`, `WAIT 100` = `0x2064`, and so on).

### `instruction_memory` (full proof)

- For any address, the stored value and the value read through `pc` are the
  last value written to that address.

### `pin_control` (full proof)

- `SET` writes `pin_value` and `OUT_BIT` writes `tx_bit`, **only** to the
  selected pin; the other pins hold.
- `pin_oe` always equals `pin_dir`, so direction comes only from the host.
- The input synchronizer is exactly 2 flops, so `SAMPLE` sees the pin value
  from 2 cycles earlier.

### `sequencer` (full proof)

- At most one control strobe is active per cycle.
- `busy` is 1 exactly in the EXEC and STALL states.
- While idle or faulted: no strobes, and the PC is held at 0 (`PC_START`).
- In EXEC, every opcode produces exactly the strobes, PC select, and next state
  the ISA says, including:
  - `WAIT 0`, `COUNT 0`, `LOOP` with count 0, and opcodes `0xB`–`0xF` fault.
  - `WAIT 1` finishes in one cycle; `WAIT N ≥ 2` starts the timer and stalls.
  - `LOOP` branches if the count is above 1 and falls through when it's 1.
- In STALL: no strobes; the PC moves on and execution resumes on `timer_done`.
- Status: `fault` is 1 exactly in the FAULT state, a fault also sets `done`,
  and `busy` and `done` are never both 1. `start` clears both and is ignored
  while busy.
- Assumption: `count_is_zero` and `count_is_one` are never both 1. That is
  proven separately in `loop_counter`.

### `host_interface` (full proof)

The solver drives `host_sck`, `host_cs_n`, and `host_mosi` freely.

- `MISO` is 0 and nothing is received while chip select is inactive.
  Deselecting resets the byte receiver.
- The command byte is never treated as data.
- `start` is a 1-cycle pulse, and only comes from writing 1 to CTRL bit 0.
- `tx_data` and `pin_dir` change only when the host writes their registers.
- The IMEM write pointer goes up by 1 per instruction written, resets on CTRL
  bit 1, and otherwise holds.
- IMEM bytes alternate low/high, and the written word is `{high, low}`.
- No program writes while `busy`.
- Covers: the solver finds real SPI transactions that write `PIN_DIR`, send
  `start`, and load the instruction `SET P3, 0`.

### `cwrupio_top` (bounded, first 60 cycles)

Whole-chip rules, with the solver driving the real SPI and protocol pins.
Instruction memory starts with arbitrary contents, so the solver also picks the
program.

- Protocol pins only change while a program is running.
- Every program run starts at address 0.
- `WAIT N` holds the PC for exactly N cycles end to end (sequencer and timer
  together).
- The program can't be modified while running.
- `pin_oe` always equals `pin_dir`; a fault always means done and not busy.
- Covers: a `start` sent over SPI, a program that drives a pin and halts, a
  program that faults, and a finished `WAIT 3`.

---

## Known gaps vs docs/isa.md (`make spec`)

`make spec` runs the top-level check with extra rules from `docs/isa.md` that
the RTL doesn't implement yet. These are turned on by the `SPEC` define in
`cwrupio_top_props.sv`. **It currently fails on purpose.** It passes once the
RTL (or the doc) is updated.

| Rule in docs/isa.md | Current RTL behavior |
|---|---|
| `CLEAR_RX` sets the RX register to `0x00` | Does nothing: `rx_shift_reg` has no clear input (TODO in `cwrupio_top.sv`) |
| A nonzero bit in a required-zero position faults | Ignored; e.g. `SET` with junk in bits 11:3 still runs |
| A branch address outside instruction memory faults | `JUMP`/`LOOP` to e.g. `0x40` wraps to address 0 |

To keep `make` and `make spec` meaningful:

- When you fix one of these in the RTL, consider moving its assertion out of
  the `ifdef SPEC` block so `make` checks it from then on.
- If instead you change the ISA doc, delete that assertion.

---

## Reading results and debugging a failure

Each run prints a summary. The important lines:

```
summary: successful proof by k-induction.          <- prove passed
summary: reached cover statement ... step 35       <- cover hit, at cycle 35
summary: failed assertion ... props.sv:36 step 4   <- the rule at line 36 broke on cycle 4
summary: counterexample trace: <dir>/engine_0/trace.vcd
DONE (PASS, rc=0)   /   DONE (FAIL, rc=2)
```

To debug a failure:

1. Open the waveform: `gtkwave <module>_prove/engine_0/trace.vcd`.
   It shows the exact inputs, cycle by cycle, that break the rule.
2. Look at the assertion line from the summary and compare it to the waveform.
3. Decide which is wrong:
   - **The design**: fix the RTL.
   - **The property**: fix the assertion or make it more precise.
   - **The inputs are impossible** in the real chip: add an `assume`, but only
     if you're sure, and add a `cover` to check you didn't over-restrict.
4. If it fails **only in the induction step** (the log says `induction` and
   the trace starts from a weird state, not from reset), the solver started
   from a state that can't really happen. Add an `assert` linking the internal
   registers (for example "`count` equals what's left of the wait") so
   induction can rule it out.

Return codes: `0` pass, `2` fail, `4` unknown (usually the induction step failed
but no bug was found within `depth`), `16` error (often a SystemVerilog error;
see `<task>/model/design.log`).

Cover traces are useful even when everything passes. `<module>_cover/engine_0/trace*.vcd`
show *how* the design reaches each case, for example a full SPI transaction.

---

## Adding or changing a check

### For a new module `foo`

1. Create `foo_props.sv`. Copy one of the existing ones as a template. Its
   ports must use the **same names** as `foo`'s signals so `.*` connects them.
   Add internal signals you want to check as extra input ports.
2. End the file with `bind foo foo_props #(...) u_props (.*);`
3. Create `foo.sby`. Copy `loop_counter.sby` and replace `loop_counter` with
   `foo` everywhere.
4. Add `foo` to `MODULES` in the `Makefile`.
5. Run `make foo`. Then plant a bug in a copy of `foo.sv` and check the run
   fails (see below).

### Tips

- Gate `$past()` checks with `f_past_valid`, and register checks with "a reset
  has happened". Before the first reset, flip-flops hold arbitrary values.
- Give every important behavior a `cover`. A property that's never exercised
  passes for the wrong reason.
- Keep the `.sby` `depth` large enough to reach your covers. `host_interface`
  needs 70 for a three-byte SPI transaction.

---

## Gotchas

These came up while building the suite and are easy to hit again:

- **`(* anyconst *)` and undriven signals don't work with `read_slang`.**
  slang keeps the attribute only as a label, and treats each read of an
  undriven signal as a separate free value. For a free constant, use a register
  with no reset that reloads itself: `always_ff @(posedge clk) f_addr <= f_addr;`
- **Enum ports and `bind ... (.*)`.** slang refuses to connect an enum (like
  the sequencer's `state_t state`) to a plain `logic [1:0]` port. Connect it
  explicitly with a size cast: `.state(2'(state))`. Note that `logic'(x)` casts
  to **1 bit**, not "same width".
- **macOS `sed` doesn't support `\b`.** Use `perl -pe` for word-boundary
  replacements when generating `.sby` files.
- **The Tiny Tapeout flow can't use `read_slang`.** That doesn't matter here:
  the `.sby` files have their own yosys script.

---

## How we know the checks work

A check that never fails proves nothing. Each module's properties were tested
by planting a bug in a copy of the RTL and confirming the run fails:

| Planted bug | Caught by |
|---|---|
| TX shift inserts 1 instead of 0 | `tx_shift_reg` |
| RX shifts in from the wrong end | `rx_shift_reg` |
| Timer loads `cycles` instead of `cycles - 1` | `timing_unit` |
| Decoder uses bits [2:1] for `OUT_BIT` | `instruction_decoder` |
| Memory drops writes to odd addresses | `instruction_memory` |
| `SAMPLE` uses a 1-flop synchronizer | `pin_control` |
| `HALT` doesn't set `done` | `sequencer` |
| `LOOP` branches on its last iteration | `sequencer` |
| Program writes allowed while busy | `host_interface` |
| IMEM write pointer doesn't advance | `host_interface` |
| `WAIT` too short by 2 cycles | `cwrupio_top` |
| Program doesn't start at address 0 | `cwrupio_top` |

Repeat this after big property changes. If a planted bug passes, the property
for it is missing or too weak.
