# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import os

import cocotb
from cocotb.triggers import Edge, First, RisingEdge, Timer, with_timeout
from cocotb.utils import get_sim_time
from cocotbext.axi import (
    AxiLiteBus,
    AxiLiteMaster,
    AxiStreamBus,
    AxiStreamFrame,
    AxiStreamSink,
    AxiStreamSource,
)


REG_CONTROL = 0x08
REG_STATUS = 0x0C
REG_TXDIVCNT = 0x10
REG_TIMECODE_TX = 0x14
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


class SpaceWireMonitor:
    """Decode the characters the DUT transmits on spw_do/spw_so. A faithful port
    of rtl/verilog/spwrecv.v's bit-level decoder, so it reuses the same NULL
    sync and parity/control framing. Each decoded character is appended to
    ``tokens`` as (kind, value, time_ns): kind in
    NULL/FCT/DATA/EOP/EEP/TIMECODE/ERRPAR/ERRESC."""

    def __init__(self, data_signal, strobe_signal):
        self.data = data_signal
        self.strobe = strobe_signal
        self.tokens = []
        self.null_seen = 0
        self.bitshift = 0
        self.bitcnt = 0
        self.parity = 0
        self.control = 0
        self.escaped = 0
        self.errpar = 0
        self.erresc = 0

    def feed_bit(self, inbit):
        now = get_sim_time("ns")
        inbit &= 1
        v_bitshift = self.bitshift
        v_bitcnt = self.bitcnt
        v_parity = self.parity
        v_control = self.control
        v_escaped = self.escaped
        new_errpar = 0
        new_erresc = 0

        if v_bitcnt & 1:
            if ((v_parity ^ inbit) & 1) == 0:
                new_errpar = 1
            else:
                if v_control:
                    cc = (v_bitshift >> 6) & 0x3  # bitshift[7:6]
                    if cc == 0b00:
                        self.tokens.append(("NULL" if self.escaped else "FCT", 0, now))
                        v_escaped = 0
                    elif cc == 0b10:
                        if self.escaped:
                            new_erresc = 1
                        else:
                            self.tokens.append(("EOP", 0, now))
                        v_escaped = 0
                    elif cc == 0b01:
                        if self.escaped:
                            new_erresc = 1
                        else:
                            self.tokens.append(("EEP", 0, now))
                        v_escaped = 0
                    else:  # 0b11 = ESC
                        if self.escaped:
                            new_erresc = 1
                        v_escaped = 1
                else:
                    if self.escaped:
                        self.tokens.append(("TIMECODE", v_bitshift & 0xFF, now))
                    else:
                        self.tokens.append(("DATA", v_bitshift & 0xFF, now))
                    v_escaped = 0
            v_parity = 0
            v_control = inbit
            v_bitcnt = 0b0000001000 if inbit else 0b1000000000
        else:
            v_bitcnt = v_bitcnt >> 1
            v_parity = v_parity ^ inbit

        if not self.null_seen:
            if v_bitshift == 0b000101110:
                self.null_seen = 1
                v_control = inbit
                v_parity = 0
                v_bitcnt = 0b0000001000

        v_bitshift = ((inbit << 8) | (v_bitshift >> 1)) & 0x1FF

        if new_errpar and not self.errpar:
            self.tokens.append(("ERRPAR", 0, now))
        if new_erresc and not self.erresc:
            self.tokens.append(("ERRESC", 0, now))

        self.bitshift = v_bitshift
        self.bitcnt = v_bitcnt
        self.parity = v_parity
        self.control = v_control
        self.escaped = v_escaped
        self.errpar = self.errpar | new_errpar
        self.erresc = self.erresc | new_erresc

    async def run(self):
        while True:
            await First(Edge(self.data), Edge(self.strobe))
            try:
                bit = int(self.data.value)
            except ValueError:
                continue  # unresolved (x/z) edge during bring-up; ignore
            self.feed_bit(bit)

    def kinds(self):
        return [t[0] for t in self.tokens]

    def data_bytes(self):
        return [value for kind, value, _ in self.tokens if kind == "DATA"]


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


def nchar_frame(payload, terminator=0x00):
    """Build an AXI-Stream frame whose last beat (TLAST) marks EOP/EEP; tuser[0]=1
    selects EEP. Matches the loopback scoreboard's frame convention."""
    return AxiStreamFrame(bytes([*payload, terminator]),
                          tuser=[0] * len(payload) + [terminator & 1])


async def soft_loopback(dut, gate):
    """Mirror the core's transmitted D/S back onto its own receive inputs, so the
    core talks to itself. While gate['on'] is False the receive line freezes,
    which the core sees as a disconnect (unlike linkdis, this leaves txdiscard
    armed). Used to drop the link mid-packet and then restore it."""
    dut.spw_di_ext.value = int(dut.spw_do.value)
    dut.spw_si_ext.value = int(dut.spw_so.value)
    while True:
        await First(Edge(dut.spw_do), Edge(dut.spw_so))
        if gate["on"]:
            dut.spw_di_ext.value = int(dut.spw_do.value)
            dut.spw_si_ext.value = int(dut.spw_so.value)


@cocotb.test()
async def axi_top_external_line_tx_discards_tail_after_link_loss(dut):
    """TX-side packet recovery (a STAR-Dundee packet-level requirement and the
    counterpart to axi_top_external_line_truncated_packet_emits_eep): when the
    link is lost while a packet is mid-transmission, the untransmitted tail must
    be discarded through its EOP, and the NEXT packet queued afterwards must
    transmit cleanly -- never prefixed with the stale tail.

    Driven through a software loopback (the core's own TX mirrored to its RX) so
    the link can be broken mid-packet and restored, then observed on m_axis. If
    txdiscard did not work, the stale tail of packet A would reappear as a frame
    ahead of packet B."""
    sys_freq = env_float("SPW_SYS_CLOCK_FREQ", 20.0e6)
    rx_freq = env_float("SPW_RX_CLOCK_FREQ", 20.0e6)
    tx_freq = env_float("SPW_TX_CLOCK_FREQ", 20.0e6)
    tx_div = env_int("SPW_TX_CLOCK_DIV", 1)

    cocotb.start_soon(run_clock(dut.clk, sys_freq))
    cocotb.start_soon(run_clock(dut.rxclk, rx_freq))
    cocotb.start_soon(run_clock(dut.txclk, tx_freq))
    initialize_inputs(dut)
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)

    gate = {"on": True}
    cocotb.start_soon(soft_loopback(dut, gate))

    # Bring up the software-looped link.
    await axil.write_dword(REG_TXDIVCNT, tx_div & 0xFF)
    await axil.write_dword(REG_CONTROL, 0x00000006)  # autostart|linkstart
    await wait_running(axil, dut.clk)

    # Sanity: a normal packet round-trips through the software loopback.
    source.send_nowait(nchar_frame([0x10, 0x11, 0x12]))
    frame = await with_timeout(sink.recv(), 500, "us")
    assert bytes(frame.tdata) == bytes([0x10, 0x11, 0x12, 0x00])

    # Queue a long packet A, then break the link while it is still transmitting
    # (only a fraction of 64 bytes leaves at 10 Mbit/s in ~8 us -> txpacket set,
    # so the link loss arms txdiscard for the rest of A including its EOP).
    source.send_nowait(nchar_frame([i & 0xFF for i in range(64)]))
    await Timer(8, unit="us")
    gate["on"] = False
    await wait_not_running(axil, dut.clk)

    # Discard whatever truncated part of A the RX side received before the break.
    await Timer(40, unit="us")
    sink.clear()

    # Reconnect and resync the mirror, then send packet B.
    gate["on"] = True
    dut.spw_di_ext.value = int(dut.spw_do.value)
    dut.spw_si_ext.value = int(dut.spw_so.value)
    await wait_running(axil, dut.clk)

    b = [0x80 + i for i in range(8)]
    source.send_nowait(nchar_frame(b))
    frame = await with_timeout(sink.recv(), 500, "us")
    assert bytes(frame.tdata) == bytes([*b, 0x00]), (
        f"next packet corrupted by stale TX tail: got {bytes(frame.tdata).hex()}"
    )
    assert last_user_bit(frame) == 0, "next packet must end in a clean EOP"


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


@cocotb.test()
async def axi_top_external_line_early_null_in_errorwait_connects(dut):
    """A peer that powers up first legitimately streams NULLs while this node is
    still in its post-error "exchange of silence" (ErrorReset/ErrorWait). The
    local transmitter stays silent during that window, but the *receiver* is
    enabled throughout ErrorWait, so those early NULLs are tolerated -- they must
    NOT be treated as an error (only FCT/N-Char/Time-Code abort ErrorWait/Ready)
    -- and they latch gotNULL. The link must therefore advance Started ->
    Connecting on that early-latched NULL and reach Run once the peer follows with
    a genuine FCT.

    This is the standard-conformant behaviour and the direct counter-evidence for
    BUGS.md "Bug 19": an early NULL during ErrorWait is expected, not a fault. The
    distinction from the other bring-up tests is that NULLs begin flowing *before*
    Started, i.e. during the silence window."""
    axil, line = await begin_external_bringup(dut)
    # NULLs flow from ErrorReset onward; they begin landing the moment the link
    # enters ErrorWait (receiver enabled). Drive until Connecting is reached,
    # which can only happen if the (early) NULL was latched and tolerated.
    for _ in range(400):
        await line.null()
        if (await read_status(axil)) & (1 << 1):  # Connecting
            break
    else:
        raise AssertionError("early NULLs during ErrorWait did not reach Connecting")
    # A genuine FCT now completes the handshake into Run.
    for _ in range(64):
        await line.fct()
        if (await read_status(axil)) & (1 << 2):  # Run
            break
    await wait_running(axil, dut.clk)


@cocotb.test()
async def axi_top_external_line_early_null_alone_never_runs(dut):
    """Safety counterpart to the test above (and the real answer to BUGS.md
    "Bug 19"): an early NULL latched during ErrorWait lets the link advance to
    Connecting, but it can NOT by itself carry the link into Run. Reaching Run
    still requires a fresh FCT from a genuinely live peer (gotFCT is a single
    cycle pulse, never latched). If the peer that emitted the early NULL then goes
    silent, the link must self-correct via the Connecting timeout / disconnect and
    never reach Run -- so the latched NULL cannot fabricate a spurious link."""
    axil, line = await begin_external_bringup(dut)
    # Drive NULLs (landing during ErrorWait) until the link reaches Connecting,
    # proving the early NULL was consumed to advance past Started.
    reached_connecting = False
    for _ in range(400):
        await line.null()
        if (await read_status(axil)) & (1 << 1):  # Connecting
            reached_connecting = True
            break
    assert reached_connecting, "early NULL did not advance the link to Connecting"
    # The peer now falls silent: no FCT will ever follow. The link must drop back
    # and never reach Run on the strength of the already-latched NULL alone.
    line.reset()
    await assert_never_runs(axil, dut, cycles=6000)


async def bringup_soft_loopback(dut, with_monitor=False):
    """Bring the core up talking to itself through a software loopback (its own TX
    mirrored to its RX). When with_monitor is set, a SpaceWireMonitor is started
    BEFORE bring-up so it captures the startup NULL/FCT handshake. Returns
    (axil, source, sink, gate, monitor)."""
    sys_freq = env_float("SPW_SYS_CLOCK_FREQ", 20.0e6)
    rx_freq = env_float("SPW_RX_CLOCK_FREQ", 20.0e6)
    tx_freq = env_float("SPW_TX_CLOCK_FREQ", 20.0e6)
    tx_div = env_int("SPW_TX_CLOCK_DIV", 1)

    cocotb.start_soon(run_clock(dut.clk, sys_freq))
    cocotb.start_soon(run_clock(dut.rxclk, rx_freq))
    cocotb.start_soon(run_clock(dut.txclk, tx_freq))
    initialize_inputs(dut)
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)

    gate = {"on": True}
    cocotb.start_soon(soft_loopback(dut, gate))
    monitor = None
    if with_monitor:
        monitor = SpaceWireMonitor(dut.spw_do, dut.spw_so)
        cocotb.start_soon(monitor.run())

    await axil.write_dword(REG_TXDIVCNT, tx_div & 0xFF)
    await axil.write_dword(REG_CONTROL, 0x00000006)  # autostart|linkstart
    await wait_running(axil, dut.clk)
    return axil, source, sink, gate, monitor


@cocotb.test()
async def axi_top_external_line_tx_monitor_self_check(dut):
    """Validate SpaceWireMonitor against a known packet over software loopback:
    the decoder must recover exactly the transmitted data bytes + EOP, and must
    have decoded NULLs and FCTs during startup, with no spurious parity/escape
    errors. This underpins the handshake-order and priority tests below."""
    axil, source, sink, gate, mon = await bringup_soft_loopback(dut, with_monitor=True)
    payload = [0xA5, 0x3C, 0x7E, 0x01]
    source.send_nowait(nchar_frame(payload))
    # The TLAST beat becomes the EOP on the wire (its data byte is the EOP marker,
    # not transmitted), so the decoder should see exactly the payload + an EOP.
    for _ in range(40000):
        if "EOP" in mon.kinds() and len(mon.data_bytes()) >= len(payload):
            break
        await RisingEdge(dut.clk)
    assert mon.data_bytes() == payload, f"decoder data mismatch: {mon.data_bytes()}"
    assert "EOP" in mon.kinds(), "decoder did not see the EOP"
    assert "NULL" in mon.kinds(), "startup NULLs not decoded"
    assert "FCT" in mon.kinds(), "startup FCTs not decoded"
    assert "ERRPAR" not in mon.kinds(), "spurious parity error from decoder"
    assert "ERRESC" not in mon.kinds(), "spurious escape error from decoder"


@cocotb.test()
async def axi_top_external_line_emits_null_then_fct_before_run(dut):
    """Rev.1 handshake order (Sent NULL / Sent FCT gating): the core must emit at
    least one NULL before it emits any FCT, and at least one FCT before it reaches
    Run, and it must not emit any N-Char/Time-Code before that first FCT. Decoded
    directly from the transmitted character stream captured from bring-up."""
    axil, source, sink, gate, mon = await bringup_soft_loopback(dut, with_monitor=True)
    kinds = mon.kinds()
    assert "NULL" in kinds, "core emitted no NULL during startup"
    assert "FCT" in kinds, "core reached Run without emitting an FCT"
    first_null = kinds.index("NULL")
    first_fct = kinds.index("FCT")
    assert first_null < first_fct, "core emitted an FCT before any NULL"
    for premature in ("DATA", "EOP", "EEP", "TIMECODE"):
        assert premature not in kinds[:first_fct], (
            f"core emitted {premature} before its first FCT"
        )
    assert "ERRPAR" not in kinds and "ERRESC" not in kinds, "decode error during handshake"


@cocotb.test()
async def axi_top_external_line_timecode_preempts_pending_data(dut):
    """Character priority (Time-Code > N-Char): a Time-Code requested while a long
    data packet is still transmitting must be emitted ahead of the remaining
    queued data (not after it), and promptly. Decoded from the transmit stream."""
    axil, source, sink, gate, mon = await bringup_soft_loopback(dut, with_monitor=True)

    source.send_nowait(nchar_frame([i & 0xFF for i in range(40)]))
    # Let several data chars go out, then request a Time-Code mid-packet.
    while len(mon.data_bytes()) < 4:
        await RisingEdge(dut.clk)
    request_ns = get_sim_time("ns")
    await axil.write_dword(REG_TIMECODE_TX, 0x80000000 | 0x2A)

    for _ in range(80000):
        if "EOP" in mon.kinds():
            break
        await RisingEdge(dut.clk)
    kinds = mon.kinds()
    assert "TIMECODE" in kinds, "time-code was never transmitted"

    tc_idx = kinds.index("TIMECODE")
    last_data_idx = len(kinds) - 1 - kinds[::-1].index("DATA")
    assert tc_idx < last_data_idx, (
        "time-code did not preempt the remaining queued data (lower priority than N-Char)"
    )

    tc_kind, tc_val, tc_ns = next(t for t in mon.tokens if t[0] == "TIMECODE")
    assert tc_val == 0x2A, f"time-code value corrupted: 0x{tc_val:02x}"
    # Latency: the time-code should jump the queue within a few character times,
    # not wait for the whole packet (40 chars ~ 400 us at 10 Mbit/s).
    assert tc_ns - request_ns < 50_000, (
        f"time-code latency {tc_ns - request_ns} ns too high; it did not preempt"
    )


async def far_end_nulls_with_fct(line, ctrl):
    """Keep the far end alive with NULLs, emitting an FCT whenever ctrl['fct'] > 0
    (one per request). Lets a test grant SpaceWire credit (8 N-Chars per FCT) at
    precise moments while the link stays up."""
    while True:
        if ctrl["fct"] > 0:
            await line.fct()
            ctrl["fct"] -= 1
        else:
            await line.null()


async def bringup_external_keepalive(dut, with_monitor=False):
    """Bring up via the external line driver using a NULL keepalive + on-demand
    FCT grants, so the link stays up and the test controls TX credit exactly.
    Returns (axil, source, ctrl, monitor)."""
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
    source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
    ctrl = {"fct": 0}
    cocotb.start_soon(far_end_nulls_with_fct(line, ctrl))
    monitor = None
    if with_monitor:
        monitor = SpaceWireMonitor(dut.spw_do, dut.spw_so)
        cocotb.start_soon(monitor.run())

    await axil.write_dword(REG_TXDIVCNT, tx_div & 0xFF)
    await axil.write_dword(REG_CONTROL, 0x00000006)
    # Grant exactly one FCT once Connecting so the DUT reaches Run with a small,
    # bounded TX credit (never near the overflow threshold).
    for _ in range(50000):
        status = await read_status(axil)
        if status & (1 << 2):
            break
        if (status & (1 << 1)) and ctrl["fct"] == 0:
            ctrl["fct"] = 1
        await RisingEdge(dut.clk)
    await wait_running(axil, dut.clk)
    return axil, line, source, ctrl, monitor


async def wait_tx_stall(mon, dut, idle_cycles=400):
    """Wait until the decoded DATA count stops growing for idle_cycles (the TX has
    run out of credit and is sending only NULLs); return the stable DATA count."""
    last = len(mon.data_bytes())
    stable = 0
    while stable < idle_cycles:
        await RisingEdge(dut.clk)
        now = len(mon.data_bytes())
        if now == last:
            stable += 1
        else:
            stable = 0
            last = now
    return last


@cocotb.test()
async def axi_top_external_line_one_fct_grants_eight_nchars(dut):
    """Flow control: one received FCT grants exactly eight N-Chars of TX credit.
    Drain the startup credit to a stall, then grant one FCT at a time and confirm
    exactly eight more N-Chars are transmitted per FCT (decoded from the wire)."""
    axil, line, source, ctrl, mon = await bringup_external_keepalive(dut, with_monitor=True)

    # Queue far more data than any credit grant; transmission is credit-limited.
    source.send_nowait(nchar_frame([i & 0xFF for i in range(200)]))
    baseline = await wait_tx_stall(mon, dut)

    ctrl["fct"] += 1
    after_one = await wait_tx_stall(mon, dut)
    assert after_one - baseline == 8, f"one FCT released {after_one - baseline} N-Chars, expected 8"

    ctrl["fct"] += 1
    after_two = await wait_tx_stall(mon, dut)
    assert after_two - after_one == 8, f"second FCT released {after_two - after_one} N-Chars, expected 8"


@cocotb.test()
async def axi_top_external_line_eop_consumes_rx_credit(dut):
    """EOP/EEP count as N-Chars for flow control: a burst of EOPs (empty packets)
    with the RX stream undrained exhausts the granted RX credit and raises errcred,
    proving end-of-packet markers consume credit exactly like data N-Chars (if they
    did not, no credit error could occur)."""
    axil, line = await setup_default_external_dut(dut)
    for _ in range(100):
        await line.eop()
    assert (await wait_error(axil, dut.clk, ERR_CRED)) & ERR_CRED
    await wait_not_running(axil, dut.clk)


@cocotb.test()
async def axi_top_external_line_noise_never_reaches_run(dut):
    """Auto-start hardening: random line activity (noise) must never carry the link
    to Run -- only a legal NULL-then-FCT handshake may. With autostart|linkstart
    enabled, drive a deterministic pseudo-random bit stream into the receiver and
    assert the link never reaches Run; parity/escape/disconnect errors keep
    resetting the bring-up. (The core advances on decoded NULL/FCT characters, not
    on raw bit activity: gotBit only feeds disconnect timing, never Run.)"""
    axil, line = await begin_external_bringup(dut)  # autostart|linkstart issued
    lfsr = 0xACE1
    for index in range(4000):
        feedback = ((lfsr >> 15) ^ (lfsr >> 13) ^ (lfsr >> 12) ^ (lfsr >> 10)) & 1
        lfsr = ((lfsr << 1) | feedback) & 0xFFFF
        await line.bit(lfsr & 1)
        if (index & 0x3F) == 0:
            assert not (await read_status(axil)) & (1 << 2), "line noise drove the link to Run"
    assert not (await read_status(axil)) & (1 << 2), "line noise drove the link to Run"
