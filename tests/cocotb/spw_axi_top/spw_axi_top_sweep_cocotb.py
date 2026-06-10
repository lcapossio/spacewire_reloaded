# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import os

import cocotb
from cocotb.triggers import RisingEdge, Timer, with_timeout
from cocotbext.axi import AxiLiteBus, AxiLiteMaster, AxiStreamBus, AxiStreamFrame, AxiStreamSink, AxiStreamSource


REG_CONTROL = 0x08
REG_STATUS = 0x0C
REG_TXDIVCNT = 0x10
REG_TIMECODE_TX = 0x14
REG_TIMECODE_RX = 0x18


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


async def reset_dut(dut):
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


def initialize_bus_inputs(dut):
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
    if hasattr(dut, "spw_di_ext"):
        dut.spw_di_ext.value = 0
        dut.spw_si_ext.value = 0


async def wait_running(axil, clock, cycles=30000):
    for _ in range(cycles):
        status = await axil.read_dword(REG_STATUS)
        if status & (1 << 2):
            return
        await RisingEdge(clock)
    raise AssertionError("AXI-wrapped SpaceWire core did not enter Run state")


def frame_user_bits(frame):
    if isinstance(frame.tuser, int):
        return [frame.tuser] * len(frame.tdata)
    return list(frame.tuser)


@cocotb.test()
async def axi_top_spwlink_configuration_smoke(dut):
    sys_freq = env_float("SPW_SYS_CLOCK_FREQ", 20.0e6)
    rx_freq = env_float("SPW_RX_CLOCK_FREQ", 20.0e6)
    tx_freq = env_float("SPW_TX_CLOCK_FREQ", 20.0e6)
    tx_div = env_int("SPW_TX_CLOCK_DIV", 1)
    case_id = env_int("SPW_SWEEP_CASE", 0)

    cocotb.start_soon(run_clock(dut.clk, sys_freq))
    cocotb.start_soon(run_clock(dut.rxclk, rx_freq))
    cocotb.start_soon(run_clock(dut.txclk, tx_freq))

    initialize_bus_inputs(dut)
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)

    await axil.write_dword(REG_TXDIVCNT, tx_div & 0xFF)
    await axil.write_dword(REG_CONTROL, 0x00000006)
    await wait_running(axil, dut.clk)

    payload = [case_id & 0xFF, env_int("SPW_RXIMPL", 0), env_int("SPW_TXIMPL", 0), env_int("SPW_RXCHUNK", 1)]
    await source.send(AxiStreamFrame(bytes([*payload, 0x00]), tuser=[0, 0, 0, 0, 0]))
    received = await with_timeout(sink.recv(), 2, "ms")
    assert bytes(received.tdata) == bytes([*payload, 0x00])
    assert frame_user_bits(received) == [0, 0, 0, 0, 0]

    await with_timeout(axil.write_dword(REG_TIMECODE_TX, 0x80000080 | (case_id & 0x3F)), 100, "us")
    for _ in range(5000):
        rx_timecode = await axil.read_dword(REG_TIMECODE_RX)
        if rx_timecode & (1 << 31):
            assert rx_timecode == (0x80000080 | (case_id & 0x3F))
            return
        await RisingEdge(dut.clk)
    raise AssertionError("timed out waiting for looped-back timecode")
