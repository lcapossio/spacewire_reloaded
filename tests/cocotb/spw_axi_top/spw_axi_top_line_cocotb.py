# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import os

import cocotb
from cocotb.triggers import Edge, First, RisingEdge, Timer, with_timeout
from cocotb.utils import get_sim_time
from cocotbext.axi import AxiLiteBus, AxiLiteMaster


REG_CONTROL = 0x08
REG_STATUS = 0x0C
REG_TXDIVCNT = 0x10


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

    async def null_stream(self):
        self.reset()
        while True:
            await self.null()


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
