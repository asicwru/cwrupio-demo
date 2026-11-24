# CWRUPIO Assembler

Two-pass assembler for the CWRUPIO instruction set. It turns an assembly program into a hex file of 16-bit instruction words that can be loaded into instruction memory. The encodings follow [`docs/isa.md`](../docs/isa.md).

## Folder layout

| Path | Contents |
|---|---|
| `assembler.ml` | The assembler |
| `txt/` | Assembly programs (`.txt`) |
| `hexout/` | Generated hex files |

## Build

Needs OCaml and `ocamlfind` (Linux, macOS or WSL). From this folder:

```
ocamlfind ocamlopt -package str -linkpkg assembler.ml -o assembler
```

`ocamlfind` may print warnings about missing `stublibs` directories. They don't affect the build.

## Run

```
./assembler txt/spi.txt hexout/spi.hex
```

| Argument | Meaning | Default |
|---|---|---|
| 1 | Input program | `test1.txt` |
| 2 | Output hex file | `results.hex` |
| 3 | Instruction-memory depth in words (1–64) | `64` |

The assembler prints nothing when it succeeds.

## Output format

One 4-digit hex word per line, padded with `0000` (`HALT`) up to the memory depth. It loads directly with `$readmemh` in Verilog, or with `int(line, 16)` in Python.

## Syntax

- One instruction per line. Operands are separated by commas or spaces: `SET UIO3, 1`.
- Labels end with a colon and can sit on their own line or before an instruction (`bit: OUT_BIT UIO1`). Put a space after the colon, and use one label per line.
- `LOOP` and `JUMP` take a label or an address (0-63).
- Comments start with `#`, `;` or `//`.
- Numbers can be decimal, hex (`0x1F`), binary (`0b101`) or octal (`0o17`).
- Instruction and pin names are uppercase. Labels are case-sensitive.

## Instructions

| Instruction | Operands | Range |
|---|---|---|
| `HALT` | none | |
| `SET pin, value` | pin, value | value 0-1 |
| `WAIT cycles` | cycles | 1-4095 |
| `LOAD_TX` | none | |
| `OUT_BIT pin` | pin | |
| `SHIFT_TX` | none | |
| `CLEAR_RX` | none | |
| `SAMPLE pin` | pin | |
| `COUNT n` | n | 1-255 |
| `LOOP address` | label or address | 0 to depth - 1 |
| `JUMP address` | label or address | 0 to depth - 1 |

Each instruction is one 16-bit word: opcode in `[15:12]`, pin in `[11:7]`, value in `[6]` and address in `[5:0]`. `WAIT` uses `[11:0]` for its cycle count and `COUNT` uses `[7:0]`. See [`docs/isa.md`](../docs/isa.md) for the full encoding tables.

## Pins

| Names | Numbers | Direction |
|---|---|---|
| `UIO0`-`UIO7` | 0-7 | Bidirectional |
| `UI0`-`UI7` | 8-15 | Input only |
| `UO0`-`UO7` | 16-23 | Output only |

`SET` and `OUT_BIT` can't use `UI` pins, and `SAMPLE` can't use `UO` pins.

## Example

`txt/spi.txt` sends one byte over SPI (mode 0) and reads one back. It uses `UIO0` as the clock, `UIO1` as data out, `UIO2` as data in and `UIO3` as chip select.

```
    SET UIO3, 1
    SET UIO0, 0
    LOAD_TX
    CLEAR_RX
    SET UIO3, 0
    COUNT 8
bit:
    OUT_BIT UIO1
    WAIT 4
    SET UIO0, 1
    SAMPLE UIO2
    SHIFT_TX
    WAIT 2
    SET UIO0, 0
    LOOP bit
    SET UIO3, 1
    HALT
```

The first 16 lines of `hexout/spi.hex` are:

```
11C0 1000 3000 6000 1180 8008 4080 2004 1040 7100 5000 2002 1000 9006 11C0 0000
```