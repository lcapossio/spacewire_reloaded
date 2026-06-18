# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import os

import cocotb
from cocotb.triggers import Edge, First, RisingEdge, Timer, with_timeout
from cocotb.utils import get_sim_time
from cocotbext.axi import AxiLiteBus, AxiLiteMaster, AxiStreamBus, AxiStreamSink


REG_CONTROL = 0x08
REG_STATUS = 0x0C
REG_TXDIVCNT = 0x10
REG_ERROR = 0x1C

ERR_DISC = 0x1
ERR_PAR = 0x2
ERR_ESC = 0x4
ERR_CRED = 0x8


def env_float(name, default):
    return float(os.environ.get(name, default))


def env_int(name, default):
    return int(os.environ.get(name, default))


async def run_clock(signal, freq_hz):
    period_ps = max(2, round(1.0e12 / freq_hz))
    low_ps = period_ps // 2
    high_ps = period_ps - low_ps
    signal.value = 0
    while True:
        await Timer(low_ps, unit="ps")
        signal.value = 1
        await Timer(high_ps, unit="ps")
        signal.value = 0


class SpaceWireLineDriver:
    def __init__(self, data_signal, strobe_signal, bit_rate_hz):
        self.data = data_signal
        self.strobe = strobe_signal
        self.bit_period_ps = max(2, round(1.0e12 / bit_rate_hz))
        self.parity = 0

    def reset(self):
        self.data.value = 0
        self.strobe.value = 0
        self.parity = 0

    async def bit(self, value):
        value = int(value) & 1
        data_now = int(self.data.value)
        strobe_now = int(self.strobe.value)
        self.strobe.value = int(not (strobe_now ^ data_now ^ value))
        self.data.value = value
        await Timer(self.bit_period_ps, unit="ps")

    async def fct(self):
        await self.bit(self.parity)
        await self.bit(1)
        await self.bit(0)
        self.parity = 0
        await self.bit(0)

    async def esc(self):
        await self.bit(self.parity)
        await self.bit(1)
        await self.bit(1)
        self.parity = 0
        await self.bit(1)

    async def null(self):
        await self.esc()
        await self.fct()

    async def eop(self, eep=False):
        value = 1 if eep else 0
        await self.bit(self.parity)
        await self.bit(1)
        await self.bit(value)
        self.parity = 1
        await self.bit(int(not value))

    async def data_char(self, value, bad_parity=False):
        bits = [(value >> index) & 1 for index in range(8)]
        await self.bit(self.parity if bad_parity else int(not self.parity))
        await self.bit(0)
        for bit in bits[:7]:
            await self.bit(bit)
        self.parity = 0
        for bit in bits:
            self.parity ^= bit
        await self.bit(bits[7])

    async def timecode(self, value):
        # Time-Code = ESC followed by a data character carrying the 8-bit
        # control[7:6]+time[5:0] field.
        await self.esc()
        await self.data_char(value & 0xFF)

    async def null_stream(self):
        while True:
            await self.null()

    async def fct_stream(self):
        while True:
            await self.fct()

    async def esc_stream(self):
        while True:
            await self.esc()


async def reset_dut(dut):
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


def initialize_inputs(dut):
    dut.rst.value = 0
    dut.s_axi_awaddr.value = 0
    dut.s_axi_awvalid.value = 0
    dut.s_axi_wdata.value = 0
    dut.s_axi_wstrb.value = 0
    dut.s_axi_wvalid.value = 0
    dut.s_axi_bready.value = 0
    dut.s_axi_araddr.value = 0
    dut.s_axi_arvalid.value = 0
    dut.s_axi_rready.value = 0
    dut.s_axis_tdata.value = 0
    dut.s_axis_tvalid.value = 0
    dut.s_axis_tlast.value = 0
    dut.s_axis_tuser.value = 0
    dut.m_axis_tready.value = 0
    dut.spw_di_ext.value = 0
    dut.spw_si_ext.value = 0


async def wait_running(axil, clock, cycles=50000):
    for _ in range(cycles):
        status = await axil.read_dword(REG_STATUS)
        if status & (1 << 2):
            return
        await RisingEdge(clock)
    raise AssertionError("AXI-wrapped SpaceWire core did not enter Run state with external line driver")


async def wait_not_running(axil, clock, cycles=50000):
    for _ in range(cycles):
        status = await axil.read_dword(REG_STATUS)
        if (status & (1 << 2)) == 0:
            return
        await RisingEdge(clock)
    raise AssertionError("AXI-wrapped SpaceWire core did not leave Run state")


async def read_status(axil):
    return await axil.read_dword(REG_STATUS)


async def wait_started(axil, clock, cycles=50000):
    for _ in range(cycles):
        status = await read_status(axil)
        if status & (1 << 0):
            return
        await RisingEdge(clock)
    raise AssertionError("AXI-wrapped SpaceWire core did not enter Started state")


async def drive_remote_startup(axil, clock, line):
    await wait_started(axil, clock)
    for _ in range(64):
        await line.null()
        status = await read_status(axil)
        if status & (1 << 1):
            break
    else:
        raise AssertionError("AXI-wrapped SpaceWire core did not enter Connecting state")

    for _ in range(64):
        await line.fct()
        status = await read_status(axil)
        if status & (1 << 2):
            return
    raise AssertionError("AXI-wrapped SpaceWire core did not enter Run state after FCT exchange")


async def start_external_link(dut, axil, line, tx_div=1):
    await axil.write_dword(REG_TXDIVCNT, tx_div & 0xFF)
    await axil.write_dword(REG_ERROR, 0x0000000F)
    await axil.write_dword(REG_CONTROL, 0x00000006)
    await drive_remote_startup(axil, dut.clk, line)
    await wait_running(axil, dut.clk)


async def wait_error(axil, clock, mask, cycles=50000):
    for _ in range(cycles):
        error = await axil.read_dword(REG_ERROR)
        if error & mask:
            return error
        await RisingEdge(clock)
    raise AssertionError(f"timed out waiting for error mask 0x{mask:x}")


async def collect_output_intervals(dut, count):
    intervals = []
    last_ps = None
    while len(intervals) < count:
        await First(Edge(dut.spw_do), Edge(dut.spw_so))
        now_ps = get_sim_time("ps")
        if last_ps is not None:
            interval = now_ps - last_ps
            if interval > 0:
                intervals.append(interval)
        last_ps = now_ps
    return intervals


async def assert_startup_output_rate(dut, axil):
    await axil.write_dword(REG_ERROR, 0x0000000F)
    await axil.write_dword(REG_CONTROL, 0x00000006)
    await wait_started(axil, dut.clk)
    intervals = await with_timeout(collect_output_intervals(dut, 16), 100, "us")
    max_period_ps = 112000
    min_period_ps = 90000
    for interval_ps in intervals[2:]:
        assert min_period_ps <= interval_ps <= max_period_ps, (
            f"startup TX bit period {interval_ps} ps outside 10 Mbit/s +/- 1 Mbit/s "
            f"period window [{min_period_ps}, {max_period_ps}] ps"
        )


@cocotb.test()
async def axi_top_startup_signals_at_10mbps_before_run(dut):
    sys_freq = env_float("SPW_SYS_CLOCK_FREQ", 20.0e6)
    rx_freq = env_float("SPW_RX_CLOCK_FREQ", 20.0e6)
    tx_freq = env_float("SPW_TX_CLOCK_FREQ", 20.0e6)

    cocotb.start_soon(run_clock(dut.clk, sys_freq))
    cocotb.start_soon(run_clock(dut.rxclk, rx_freq))
    cocotb.start_soon(run_clock(dut.txclk, tx_freq))
    initialize_inputs(dut)
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    await assert_startup_output_rate(dut, axil)


@cocotb.test()
async def axi_top_tx_only_case_uses_external_spacewire_line_driver(dut):
    sys_freq = env_float("SPW_SYS_CLOCK_FREQ", 20.0e6)
    rx_freq = env_float("SPW_RX_CLOCK_FREQ", 20.0e6)
    tx_freq = env_float("SPW_TX_CLOCK_FREQ", 20.0e6)
    input_rate = env_float("SPW_INPUT_RATE", 10.0e6)
    tx_div = env_int("SPW_TX_CLOCK_DIV", 1)

    cocotb.start_soon(run_clock(dut.clk, sys_freq))
    cocotb.start_soon(run_clock(dut.rxclk, rx_freq))
    cocotb.start_soon(run_clock(dut.txclk, tx_freq))
    initialize_inputs(dut)
    await reset_dut(dut)

    line = SpaceWireLineDriver(dut.spw_di_ext, dut.spw_si_ext, input_rate)
    line.reset()
    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)

    await axil.write_dword(REG_TXDIVCNT, tx_div & 0xFF)
    await axil.write_dword(REG_CONTROL, 0x00000006)
    await drive_remote_startup(axil, dut.clk, line)
    await wait_running(axil, dut.clk)
    line_task = cocotb.start_soon(line.null_stream())

    intervals = await with_timeout(collect_output_intervals(dut, 32), 500, "us")
    expected_ps = round(1.0e12 * (tx_div + 1) / tx_freq)
    tolerance_ps = 1500
    checked = intervals[4:]
    assert checked, "no SpaceWire output bit intervals collected"
    for interval_ps in checked:
        assert abs(interval_ps - expected_ps) <= tolerance_ps, (
            f"TX bit period {interval_ps} ps outside expected {expected_ps} ps +/- {tolerance_ps} ps"
        )

    line_task.kill()


async def setup_default_external_dut(dut):
    sys_freq = env_float("SPW_SYS_CLOCK_FREQ", 20.0e6)
    rx_freq = env_float("SPW_RX_CLOCK_FREQ", 20.0e6)
    tx_freq = env_float("SPW_TX_CLOCK_FREQ", 20.0e6)
    input_rate = env_float("SPW_INPUT_RATE", 10.0e6)
    tx_div = env_int("SPW_TX_CLOCK_DIV", 1)

    cocotb.start_soon(run_clock(dut.clk, sys_freq))
    cocotb.start_soon(run_clock(dut.rxclk, rx_freq))
    cocotb.start_soon(run_clock(dut.txclk, tx_freq))
    initialize_inputs(dut)
    await reset_dut(dut)

    line = SpaceWireLineDriver(dut.spw_di_ext, dut.spw_si_ext, input_rate)
    line.reset()
    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    await start_external_link(dut, axil, line, tx_div=tx_div)
    return axil, line


@cocotb.test()
async def axi_top_external_line_reports_disconnect_error(dut):
    axil, line = await setup_default_external_dut(dut)
    line.reset()
    error = await wait_error(axil, dut.clk, ERR_DISC)
    assert error & ERR_DISC
    await wait_not_running(axil, dut.clk)


@cocotb.test()
async def axi_top_external_line_reports_escape_error(dut):
    axil, line = await setup_default_external_dut(dut)
    esc_task = cocotb.start_soon(line.esc_stream())
    try:
        error = await wait_error(axil, dut.clk, ERR_ESC)
        assert error & ERR_ESC
        await wait_not_running(axil, dut.clk)
    finally:
        esc_task.kill()


@cocotb.test()
async def axi_top_external_line_reports_parity_error(dut):
    axil, line = await setup_default_external_dut(dut)
    await line.data_char(0x55)
    await line.data_char(0xAA, bad_parity=True)
    error = await wait_error(axil, dut.clk, ERR_PAR)
    assert error & ERR_PAR
    await wait_not_running(axil, dut.clk)


@cocotb.test()
async def axi_top_external_line_reports_credit_error(dut):
    axil, line = await setup_default_external_dut(dut)
    for _ in range(12):
        await line.fct()
    error = await wait_error(axil, dut.clk, ERR_CRED)
    assert error & ERR_CRED
    await wait_not_running(axil, dut.clk)


def frame_len(frame):
    return 1 if isinstance(frame.tdata, int) else len(frame.tdata)


def last_user_bit(frame):
    return frame.tuser if isinstance(frame.tuser, int) else list(frame.tuser)[-1]


async def relink_external(dut, axil, line, tx_div):
    """Re-establish the external link from scratch after an error."""
    line.reset()
    for _ in range(20):
        await RisingEdge(dut.clk)
    await start_external_link(dut, axil, line, tx_div=tx_div)


@cocotb.test()
async def axi_top_external_line_error_burst(dut):
    """Several link errors in succession, each followed by a clean re-link, to
    confirm the link error/recovery path survives back-to-back faults."""
    axil, line = await setup_default_external_dut(dut)
    tx_div = env_int("SPW_TX_CLOCK_DIV", 1)

    # 1) parity error
    await line.data_char(0x55)
    await line.data_char(0xAA, bad_parity=True)
    assert (await wait_error(axil, dut.clk, ERR_PAR)) & ERR_PAR
    await wait_not_running(axil, dut.clk)
    await relink_external(dut, axil, line, tx_div)

    # 2) escape error
    esc_task = cocotb.start_soon(line.esc_stream())
    try:
        assert (await wait_error(axil, dut.clk, ERR_ESC)) & ERR_ESC
        await wait_not_running(axil, dut.clk)
    finally:
        esc_task.kill()
    await relink_external(dut, axil, line, tx_div)

    # 3) credit error
    for _ in range(12):
        await line.fct()
    assert (await wait_error(axil, dut.clk, ERR_CRED)) & ERR_CRED
    await wait_not_running(axil, dut.clk)
    await relink_external(dut, axil, line, tx_div)

    # 4) disconnect error
    line.reset()
    assert (await wait_error(axil, dut.clk, ERR_DISC)) & ERR_DISC
    await wait_not_running(axil, dut.clk)
    await relink_external(dut, axil, line, tx_div)

    assert (await axil.read_dword(REG_STATUS)) & (1 << 2), "link not running after burst"


@cocotb.test()
async def axi_top_external_line_functional_coverage(dut):
    """Drive one comprehensive scenario and report MEASURED functional coverage
    of the observable SpaceWire behaviours, asserting every cover-point is hit.

    This is cover-point (functional) coverage, achievable with the installed
    simulators. RTL line/branch/toggle coverage would need Verilator or a gcov
    GHDL build (neither installed); see README for that path."""
    cover = {
        name: False
        for name in (
            "state_started",
            "state_connecting",
            "state_running",
            "recovered_after_error",
            "err_disc",
            "err_par",
            "err_esc",
            "err_cred",
            "rx_data_char",
            "rx_eop",
            "rx_eep",
            "rx_timecode",
        )
    }

    sys_freq = env_float("SPW_SYS_CLOCK_FREQ", 20.0e6)
    rx_freq = env_float("SPW_RX_CLOCK_FREQ", 20.0e6)
    tx_freq = env_float("SPW_TX_CLOCK_FREQ", 20.0e6)
    input_rate = env_float("SPW_INPUT_RATE", 10.0e6)
    tx_div = env_int("SPW_TX_CLOCK_DIV", 1)

    cocotb.start_soon(run_clock(dut.clk, sys_freq))
    cocotb.start_soon(run_clock(dut.rxclk, rx_freq))
    cocotb.start_soon(run_clock(dut.txclk, tx_freq))
    initialize_inputs(dut)
    await reset_dut(dut)

    line = SpaceWireLineDriver(dut.spw_di_ext, dut.spw_si_ext, input_rate)
    line.reset()
    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)

    # --- bring-up: started -> connecting -> running ---
    await axil.write_dword(REG_TXDIVCNT, tx_div & 0xFF)
    await axil.write_dword(REG_ERROR, 0x0000000F)
    await axil.write_dword(REG_CONTROL, 0x00000006)
    await wait_started(axil, dut.clk)
    cover["state_started"] = True
    await drive_remote_startup(axil, dut.clk, line)  # asserts connecting + running
    cover["state_connecting"] = True
    cover["state_running"] = True
    await wait_running(axil, dut.clk)

    # --- RX stimulus, sent back-to-back so the line never goes idle (an idle
    # line would disconnect): a data packet ending in EOP, one ending in EEP,
    # and a time-code, then NULLs to flush while the chars drain. ---
    for value in (0x11, 0x22, 0x33):
        await line.data_char(value)
    await line.eop(eep=False)
    await line.data_char(0x44)
    await line.eop(eep=True)
    await line.timecode(0x2A)
    for _ in range(8):
        await line.null()

    # frames were captured by the sink in the background; drain them now
    frame = await with_timeout(sink.recv(), 300, "us")
    if frame_len(frame) > 1:
        cover["rx_data_char"] = True
    if last_user_bit(frame) == 0:
        cover["rx_eop"] = True
    frame = await with_timeout(sink.recv(), 300, "us")
    if last_user_bit(frame) == 1:
        cover["rx_eep"] = True
    for _ in range(2000):
        if (await axil.read_dword(REG_STATUS)) & (1 << 7):  # rx tick valid
            cover["rx_timecode"] = True
            break
        await RisingEdge(dut.clk)

    # the idle AXI reads above may have disconnected the line; re-link cleanly
    # before the deliberate error sweep.
    await relink_external(dut, axil, line, tx_div)

    # --- all four link errors, re-linking after each (recovery) ---
    await line.data_char(0x55)
    await line.data_char(0xAA, bad_parity=True)
    if (await wait_error(axil, dut.clk, ERR_PAR)) & ERR_PAR:
        cover["err_par"] = True
    await wait_not_running(axil, dut.clk)
    await relink_external(dut, axil, line, tx_div)
    cover["recovered_after_error"] = True

    esc_task = cocotb.start_soon(line.esc_stream())
    try:
        if (await wait_error(axil, dut.clk, ERR_ESC)) & ERR_ESC:
            cover["err_esc"] = True
        await wait_not_running(axil, dut.clk)
    finally:
        esc_task.kill()
    await relink_external(dut, axil, line, tx_div)

    for _ in range(12):
        await line.fct()
    if (await wait_error(axil, dut.clk, ERR_CRED)) & ERR_CRED:
        cover["err_cred"] = True
    await wait_not_running(axil, dut.clk)
    await relink_external(dut, axil, line, tx_div)

    line.reset()
    if (await wait_error(axil, dut.clk, ERR_DISC)) & ERR_DISC:
        cover["err_disc"] = True
    await wait_not_running(axil, dut.clk)
    await relink_external(dut, axil, line, tx_div)

    hit = sum(1 for v in cover.values() if v)
    total = len(cover)
    dut._log.info("=== spw_axi_top functional coverage ===")
    for name, value in cover.items():
        dut._log.info(f"  [{'x' if value else ' '}] {name}")
    dut._log.info(f"covered {hit}/{total} cover-points")
    missing = [name for name, value in cover.items() if not value]
    assert not missing, f"uncovered functional cover-points: {missing}"


@cocotb.test()
async def axi_top_external_line_illegal_escape_before_eop(dut):
    """ESC immediately followed by EOP is an illegal escape sequence and must
    raise erresc (spwrecv treats ESC+EOP / ESC+EEP as escape errors)."""
    axil, line = await setup_default_external_dut(dut)
    await line.esc()
    await line.eop(eep=False)
    for _ in range(4):  # keep the line active so the escaped EOP is decoded
        await line.null()
    assert (await wait_error(axil, dut.clk, ERR_ESC)) & ERR_ESC
    await wait_not_running(axil, dut.clk)


@cocotb.test()
async def axi_top_external_line_illegal_escape_before_eep(dut):
    """ESC immediately followed by EEP is also an illegal escape -> erresc."""
    axil, line = await setup_default_external_dut(dut)
    await line.esc()
    await line.eop(eep=True)
    for _ in range(4):  # keep the line active so the escaped EEP is decoded
        await line.null()
    assert (await wait_error(axil, dut.clk, ERR_ESC)) & ERR_ESC
    await wait_not_running(axil, dut.clk)


@cocotb.test()
async def axi_top_external_line_rx_credit_underflow(dut):
    """Sending more N-Chars than the receiver has granted credit for (the RX
    FIFO is never drained here, so no fresh FCTs are issued) must raise errcred
    via the RX-credit-underflow path, distinct from the FCT-overflow path."""
    axil, line = await setup_default_external_dut(dut)
    # 70 > the ~56 chars granted by the startup FCTs for a 64-entry RX FIFO.
    for index in range(70):
        await line.data_char(index & 0xFF)
    assert (await wait_error(axil, dut.clk, ERR_CRED)) & ERR_CRED
    await wait_not_running(axil, dut.clk)


@cocotb.test()
async def axi_top_external_line_truncated_packet_emits_eep(dut):
    """A link drop in the middle of a packet must terminate the partially
    received packet on the RX stream with an EEP (error end of packet)."""
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)
    axil, line = await setup_default_external_dut(dut)
    for value in (0x71, 0x72, 0x73):  # data chars, no EOP -> packet in progress
        await line.data_char(value)
    line.reset()  # disconnect mid-packet
    frame = await with_timeout(sink.recv(), 400, "us")
    assert last_user_bit(frame) == 1, "truncated packet must end in EEP (tuser=1)"
    await wait_not_running(axil, dut.clk)


async def begin_external_bringup(dut):
    """Set up clocks + line driver and issue linkstart, WITHOUT completing the
    remote handshake -- used to exercise the bring-up error-reset paths."""
    cocotb.start_soon(run_clock(dut.clk, env_float("SPW_SYS_CLOCK_FREQ", 20.0e6)))
    cocotb.start_soon(run_clock(dut.rxclk, env_float("SPW_RX_CLOCK_FREQ", 20.0e6)))
    cocotb.start_soon(run_clock(dut.txclk, env_float("SPW_TX_CLOCK_FREQ", 20.0e6)))
    initialize_inputs(dut)
    await reset_dut(dut)
    line = SpaceWireLineDriver(dut.spw_di_ext, dut.spw_si_ext,
                               env_float("SPW_INPUT_RATE", 10.0e6))
    line.reset()
    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    await axil.write_dword(REG_TXDIVCNT, env_int("SPW_TX_CLOCK_DIV", 1) & 0xFF)
    await axil.write_dword(REG_CONTROL, 0x00000006)  # autostart|linkstart
    return axil, line


async def assert_never_runs(axil, dut, cycles=4000):
    for _ in range(cycles):
        assert not (await axil.read_dword(REG_STATUS)) & (1 << 2), \
            "link reached Run despite a broken bring-up"
        await RisingEdge(dut.clk)


@cocotb.test()
async def axi_top_external_line_started_times_out(dut):
    """With no remote response, the link drops out of Started back to error
    reset and never reaches Run (exercises the Started timeout/error path)."""
    axil, _line = await begin_external_bringup(dut)
    await wait_started(axil, dut.clk)
    await assert_never_runs(axil, dut)


@cocotb.test()
async def axi_top_external_line_connecting_aborts_on_char(dut):
    """An N-Char arriving while Connecting (before the FCT handshake) aborts the
    bring-up back to error reset."""
    axil, line = await begin_external_bringup(dut)
    await wait_started(axil, dut.clk)
    for _ in range(64):
        await line.null()
        if (await read_status(axil)) & (1 << 1):  # Connecting
            break
    await line.data_char(0x5A)  # unexpected N-Char during Connecting
    await assert_never_runs(axil, dut)


@cocotb.test()
async def axi_top_external_line_early_fct_aborts_bringup(dut):
    """FCTs arriving during ErrorWait/Ready (before Started) are early activity
    that forces the link back to error reset, so it never comes up."""
    axil, line = await begin_external_bringup(dut)
    fct_task = cocotb.start_soon(line.fct_stream())
    try:
        await assert_never_runs(axil, dut, cycles=6000)
    finally:
        fct_task.kill()
