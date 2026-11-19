"""cocotb testbench for sync_fifo.sv.

Timing convention used in this file (learn it - you'll reuse it):
    * inputs are DRIVEN just after a FALLING clock edge
    * the DUT samples them at the next RISING edge
    * outputs are READ at the following FALLING edge, when everything has settled
This avoids races between your testbench and the DUT at the rising edge.
See docs/04-verification-basics.md.

Provided for you: FifoModel (the reference model), start(), cycle(), check(),
and two finished tests as worked examples. You write the rest.
"""

import random
from collections import deque

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge

DEPTH = 8
DWIDTH = 8
MASK = (1 << DWIDTH) - 1


class FifoModel:
    """Plain-Python model of what the FIFO SHOULD do. The DUT is compared against this.

    Rules (same as the spec in README.md):
      - a write is accepted only if wr_en and the FIFO is not full
      - a read is accepted only if rd_en and the FIFO is not empty
      - both flags are judged BEFORE the clock edge
      - dout changes only on an accepted read; otherwise it holds
    """

    def __init__(self):
        self.q = deque()
        self.dout = 0

    @property
    def empty(self):
        return len(self.q) == 0

    @property
    def full(self):
        return len(self.q) == DEPTH

    def step(self, wr_en, rd_en, din):
        do_w = wr_en and not self.full
        do_r = rd_en and not self.empty
        if do_r:
            self.dout = self.q.popleft()
        if do_w:
            self.q.append(din & MASK)


async def start(dut):
    """Start clock, reset both FIFOs, and return two fresh models."""

    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst_n.value = 0

    # Initialize TX signals
    dut.tx_wr_en.value = 0
    dut.tx_rd_en.value = 0
    dut.tx_din.value = 0

    # Initialize RX signals
    dut.rx_wr_en.value = 0
    dut.rx_rd_en.value = 0
    dut.rx_din.value = 0

    for _ in range(3):
        await RisingEdge(dut.clk)

    await FallingEdge(dut.clk)
    dut.rst_n.value = 1

    await FallingEdge(dut.clk)

    return {
        "tx": FifoModel(),
        "rx": FifoModel()
    }


async def cycle(dut, models, fifo, wr_en=0, rd_en=0, din=0):
    """Run one clock cycle on the selected FIFO."""

    other = "rx" if fifo == "tx" else "tx"

    # Disable the other FIFO
    getattr(dut, f"{other}_wr_en").value = 0
    getattr(dut, f"{other}_rd_en").value = 0

    # Select the appropriate FIFO signals
    wr = getattr(dut, f"{fifo}_wr_en")
    rd = getattr(dut, f"{fifo}_rd_en")
    data_in = getattr(dut, f"{fifo}_din")

    wr.value = wr_en
    rd.value = rd_en
    data_in.value = din

    model = models[fifo]
    model.step(wr_en, rd_en, din)

    await RisingEdge(dut.clk)
    await FallingEdge(dut.clk)

    check(dut, model, fifo)


def check(dut, model, fifo):
    """Compare the selected FIFO's outputs against its reference model."""

    empty = getattr(dut, f"{fifo}_empty")
    full = getattr(dut, f"{fifo}_full")
    dout = getattr(dut, f"{fifo}_dout")

    assert int(empty.value) == int(model.empty), \
        f"{fifo} empty: got {empty.value}, expected {int(model.empty)}"

    assert int(full.value) == int(model.full), \
        f"{fifo} full: got {full.value}, expected {int(model.full)}"

    assert int(dout.value) == model.dout, \
        f"{fifo} dout: got {int(dout.value):#x}, expected {model.dout:#x}"


# --------------------------------------------------------------------------- worked examples


@cocotb.test()
async def test_reset_state(dut):
    """After reset, both FIFOs should be empty, not full, and dout should be 0."""

    await start(dut)

    for fifo in ["tx", "rx"]:
        assert int(getattr(dut, f"{fifo}_empty").value) == 1
        assert int(getattr(dut, f"{fifo}_full").value) == 0
        assert int(getattr(dut, f"{fifo}_dout").value) == 0


@cocotb.test()
async def test_write_then_read_in_order(dut):
    """Write three words to each FIFO and read them back in order."""

    models = await start(dut)

    values = [0x11, 0x22, 0x33]

    for fifo in ["tx", "rx"]:
        for v in values:
            await cycle(dut, models, fifo, wr_en=1, din=v)

        assert int(getattr(dut, f"{fifo}_empty").value) == 0

        for v in values:
            await cycle(dut, models, fifo, rd_en=1)
            assert int(getattr(dut, f"{fifo}_dout").value) == v

        assert int(getattr(dut, f"{fifo}_empty").value) == 1


# --------------------------------------------------------------------------- your tests


@cocotb.test()
async def test_fill_to_full(dut):
    models = await start(dut)

    for fifo in ["tx", "rx"]:
        for i in range(DEPTH):
            await cycle(dut, models, fifo, wr_en=1, din=i)

            if i != DEPTH - 1:
                assert int(getattr(dut, f"{fifo}_full").value) == 0
            else:
                assert int(getattr(dut, f"{fifo}_full").value) == 1

        for i in range(DEPTH):
            await cycle(dut, models, fifo, rd_en=1)
            assert int(getattr(dut, f"{fifo}_dout").value) == i

        assert int(getattr(dut, f"{fifo}_empty").value) == 1


@cocotb.test()
async def test_write_when_full_is_ignored(dut):
    models = await start(dut)

    for fifo in ["tx", "rx"]:
        for i in range(DEPTH):
            await cycle(dut, models, fifo, wr_en=1, din=i)

        assert int(getattr(dut, f"{fifo}_full").value) == 1

        await cycle(dut, models, fifo, wr_en=1, din=100)

        for i in range(DEPTH):
            await cycle(dut, models, fifo, rd_en=1)
            assert int(getattr(dut, f"{fifo}_dout").value) == i

        assert int(getattr(dut, f"{fifo}_empty").value) == 1




@cocotb.test()
async def test_read_when_empty_is_ignored(dut):
    models = await start(dut)

    for fifo in ["tx", "rx"]:
        for _ in range(2):
            await cycle(dut, models, fifo, rd_en=1)

        assert int(getattr(dut, f"{fifo}_dout").value) == 0
        assert int(getattr(dut, f"{fifo}_empty").value) == 1
        assert int(getattr(dut, f"{fifo}_full").value) == 0

        await cycle(dut, models, fifo, wr_en=1, din=1)
        assert int(getattr(dut, f"{fifo}_empty").value) == 0

        await cycle(dut, models, fifo, rd_en=1)
        assert int(getattr(dut, f"{fifo}_dout").value) == 1



@cocotb.test()
async def test_simultaneous_read_write(dut):
    models = await start(dut)

    for fifo in ["tx", "rx"]:
        for i in range(3):
            await cycle(dut, models, fifo, wr_en=1, din=i)

        for i in range(10):
            await cycle(dut, models, fifo, wr_en=1, rd_en=1, din=i)

        for i in range(3):
            await cycle(dut, models, fifo, rd_en=1)
            assert int(getattr(dut, f"{fifo}_dout").value) == i + 7



@cocotb.test()
async def test_pointer_wraparound(dut):
    models = await start(dut)

    for fifo in ["tx", "rx"]:
        for _ in range(3):
            for j in range(DEPTH):
                await cycle(dut, models, fifo, wr_en=1, din=j)

            assert int(getattr(dut, f"{fifo}_full").value) == 1

            for j in range(DEPTH):
                await cycle(dut, models, fifo, rd_en=1)
                assert int(getattr(dut, f"{fifo}_dout").value) == j

            assert int(getattr(dut, f"{fifo}_full").value) == 0
            assert int(getattr(dut, f"{fifo}_empty").value) == 1



@cocotb.test()
async def test_random_traffic(dut):
    models = await start(dut)

    num = random.Random(67)

    for fifo in ["tx", "rx"]:
        for i in range(1000):
            await cycle(
                dut,
                models,
                fifo,
                wr_en=num.randint(0, 1),
                rd_en=num.randint(0, 1),
                din=num.randint(0, MASK)
            )


@cocotb.test()
async def test_both_fifos_independently(dut):
    models = await start(dut)

    # Write to both FIFOs at the same time
    for i in range(3):
        tx_value = 100 + i
        rx_value = 200 + i

        dut.tx_wr_en.value = 1
        dut.tx_rd_en.value = 0
        dut.tx_din.value = tx_value

        dut.rx_wr_en.value = 1
        dut.rx_rd_en.value = 0
        dut.rx_din.value = rx_value

        models["tx"].step(1, 0, tx_value)
        models["rx"].step(1, 0, rx_value)

        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)

        check(dut, models["tx"], "tx")
        check(dut, models["rx"], "rx")

    # Stop writing and read from both FIFOs at the same time
    for i in range(3):
        dut.tx_wr_en.value = 0
        dut.tx_rd_en.value = 1

        dut.rx_wr_en.value = 0
        dut.rx_rd_en.value = 1

        models["tx"].step(0, 1, 0)
        models["rx"].step(0, 1, 0)

        await RisingEdge(dut.clk)
        await FallingEdge(dut.clk)

        check(dut, models["tx"], "tx")
        check(dut, models["rx"], "rx")