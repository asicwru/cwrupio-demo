# SPI mode 0 byte transfer through the full CWRUPIO design.
#
# Host side : cocotb bit-bangs the host link (configuration port) like the demo-board MCU.
# Device side: cocotb models an SPI mode 0 target on P0-P3:
#              P0 = SCLK, P1 = MOSI, P2 = MISO, P3 = CS (active low).
# CWRUPIO is the SPI controller. Its program comes from the host, not from fixed logic.

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, Timer

CLK_NS = 20          # 50 MHz system clock
HOST_HALF_NS = 80    # host link SCK = 6.25 MHz (clk / 8)

# Host link registers (command byte = {rw, 000, addr[3:0]})
REG_CTRL, REG_STATUS, REG_TX_DATA, REG_RX_DATA, REG_IMEM, REG_PIN_DIR = 0, 1, 2, 3, 4, 5
WRITE = 0x80

# SPI mode 0 controller program (MSB first, 8 bits)
SPI_MODE0_PROGRAM = [
    0x1007,  # 0  SET P3,1      CS idle high
    0x1000,  # 1  SET P0,0      SCLK idle low (CPOL = 0)
    0x3000,  # 2  LOAD_TX
    0x6000,  # 3  CLEAR_RX
    0x1006,  # 4  SET P3,0      CS low
    0x8008,  # 5  COUNT 8
    0x4001,  # 6  OUT_BIT P1    MOSI = next bit, before the rising edge
    0x2004,  # 7  WAIT 4        setup time
    0x1001,  # 8  SET P0,1      SCLK rising edge (both sides sample, CPHA = 0)
    0x7002,  # 9  SAMPLE P2     read MISO
    0x5000,  # 10 SHIFT_TX
    0x2002,  # 11 WAIT 2
    0x1000,  # 12 SET P0,0      SCLK falling edge (device shifts out next bit)
    0x9006,  # 13 LOOP 6
    0x1007,  # 14 SET P3,1      CS high
    0x0000,  # 15 HALT
]
PIN_DIR_SPI = 0b1011  # P0, P1, P3 outputs; P2 input


async def host_byte(dut, tx):
    """One byte on the host link, mode 0, MSB first. Returns the byte read on host_miso."""
    rx = 0
    for i in range(7, -1, -1):
        dut.host_mosi.value = (tx >> i) & 1
        await Timer(HOST_HALF_NS, unit="ns")
        dut.host_sck.value = 1
        rx = (rx << 1) | int(dut.host_miso.value)
        await Timer(HOST_HALF_NS, unit="ns")
        dut.host_sck.value = 0
    return rx


async def host_transaction(dut, data):
    dut.host_cs_n.value = 0
    await Timer(2 * HOST_HALF_NS, unit="ns")
    rx = [await host_byte(dut, b) for b in data]
    await Timer(HOST_HALF_NS, unit="ns")
    dut.host_cs_n.value = 1
    await Timer(4 * HOST_HALF_NS, unit="ns")
    return rx


async def host_write(dut, reg, *data):
    await host_transaction(dut, [WRITE | reg, *data])


async def host_read(dut, reg):
    return (await host_transaction(dut, [reg, 0x00]))[1]


async def load_program(dut, program):
    await host_write(dut, REG_CTRL, 0x02)  # reset load pointer
    stream = []
    for word in program:
        stream += [word & 0xFF, word >> 8]  # low byte, high byte
    await host_write(dut, REG_IMEM, *stream)


class SpiMode0Device:
    """SPI mode 0 target on P0-P3. Samples MOSI on SCLK rising edges,
    puts the next MISO bit out when CS falls and on each SCLK falling edge."""

    def __init__(self, dut):
        self.dut = dut
        self.reply = 0
        self.received = []
        self.cs_frames = 0

    def _set_miso(self, bit):
        ext = int(self.dut.ext_in.value) & ~0b0100
        self.dut.ext_in.value = ext | (bit << 2)

    async def run(self):
        prev_sclk, prev_cs = 0, 1
        bits, shift_in, shift_out = 0, 0, 0
        while True:
            await RisingEdge(self.dut.clk)
            pad = int(self.dut.pad.value)
            sclk, mosi, cs = pad & 1, (pad >> 1) & 1, (pad >> 3) & 1
            if prev_cs and not cs:                    # CS falls: start of frame
                self.cs_frames += 1
                bits, shift_in, shift_out = 0, 0, self.reply
                self._set_miso((shift_out >> 7) & 1)
            elif not cs:
                if sclk and not prev_sclk:            # rising edge: sample MOSI
                    shift_in = ((shift_in << 1) | mosi) & 0xFF
                    bits += 1
                    if bits == 8:
                        self.received.append(shift_in)
                        bits = 0
                elif prev_sclk and not sclk:          # falling edge: next MISO bit
                    shift_out = (shift_out << 1) & 0xFF
                    self._set_miso((shift_out >> 7) & 1)
            if cs and sclk:
                raise AssertionError("SCLK high while CS is high (mode 0 idles low)")
            prev_sclk, prev_cs = sclk, cs


@cocotb.test()
async def spi_mode0_byte_transfer(dut):
    cocotb.start_soon(Clock(dut.clk, CLK_NS, unit="ns").start())
    dut.host_sck.value = 0
    dut.host_cs_n.value = 1
    dut.host_mosi.value = 0
    dut.ext_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 5)

    device = SpiMode0Device(dut)
    cocotb.start_soon(device.run())

    await load_program(dut, SPI_MODE0_PROGRAM)
    await host_write(dut, REG_PIN_DIR, PIN_DIR_SPI)

    # bit-order test bytes: not palindromes, so a reversed bit order fails
    for tx, reply in [(0x12, 0x3C), (0x01, 0x80), (0x80, 0x01), (0xA6, 0x59)]:
        device.reply = reply
        frames_before = device.cs_frames
        await host_write(dut, REG_TX_DATA, tx)
        await host_write(dut, REG_CTRL, 0x01)  # start

        for _ in range(100):  # poll STATUS until done
            status = await host_read(dut, REG_STATUS)
            if status & 0b010:
                break
        assert status == 0b010, f"status {status:#04x}: expected done=1, busy=0, fault=0"

        rx = await host_read(dut, REG_RX_DATA)
        dut._log.info(f"tx {tx:#04x} -> device got {device.received[-1]:#04x}; "
                      f"device sent {reply:#04x} -> rx_data {rx:#04x}")
        assert device.cs_frames == frames_before + 1, "expected exactly one CS frame"
        assert device.received[-1] == tx, "MOSI byte wrong (bit order or timing)"
        assert rx == reply, "MISO byte wrong (bit order or timing)"
        pad = int(dut.pad.value)
        assert (pad >> 3) & 1 == 1 and pad & 1 == 0, "after HALT: CS must be high, SCLK low"
