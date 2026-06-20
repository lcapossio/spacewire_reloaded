# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

"""STRICT_TIMECODES=1 behaviour (#1): the core emits tick_out (sets
REG_TIMECODE_RX valid) only for an in-sequence Time-Code (count == previous + 1
mod 64). An out-of-sequence Time-Code still updates the local count but must not
emit. Built with the loopback TB so a transmitted Time-Code loops back to the
receiver. The default (transparent) behaviour is covered by
axi_top_timecode_transparency_and_run_gating in spw_axi_top_cocotb.py."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotbext.axi import AxiLiteBus, AxiLiteMaster


REG_CONTROL = 0x08
REG_STATUS = 0x0C
REG_TXDIVCNT = 0x10
REG_TIMECODE_TX = 0x14
REG_TIMECODE_RX = 0x18
REG_ERROR = 0x1C


async def reset_dut(dut):
    dut.rst.value = 1
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
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def wait_running(axil):
    for _ in range(30000):
        if (await axil.read_dword(REG_STATUS)) & (1 << 2):
            return
    raise AssertionError("core did not reach Run")


async def send_timecode(axil, clk, value):
    """Request a Time-Code and report whether it was emitted on RX (valid bit),
    returning (emitted, received_value)."""
    await axil.write(REG_TIMECODE_RX + 3, bytes([0x80]))  # W1C the valid bit
    await axil.write_dword(REG_TIMECODE_TX, 0x80000000 | value)
    for _ in range(8000):
        rx = await axil.read_dword(REG_TIMECODE_RX)
        if rx & (1 << 31):
            return True, rx & 0x3F
        await RisingEdge(clk)
    return False, None


@cocotb.test()
async def strict_timecodes_emit_only_in_sequence(dut):
    cocotb.start_soon(Clock(dut.clk, 50, unit="ns").start())
    cocotb.start_soon(Clock(dut.rxclk, 20, unit="ns").start())
    cocotb.start_soon(Clock(dut.txclk, 20, unit="ns").start())
    await reset_dut(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    await axil.write_dword(REG_TXDIVCNT, 0x00000001)
    await axil.write_dword(REG_CONTROL, 0x00000006)
    await wait_running(axil)
    await axil.write(REG_ERROR, bytes([0x0F]))  # clear any startup sticky errors

    # last_time resets to 0x3F, so the in-sequence series starting at 0 emits.
    for value in (0x00, 0x01, 0x02, 0x03):
        emitted, rx = await send_timecode(axil, dut.clk, value)
        assert emitted, f"in-sequence Time-Code 0x{value:02x} was not emitted"
        assert rx == value, f"emitted Time-Code value 0x{rx:02x} != 0x{value:02x}"

    # An out-of-sequence jump must NOT emit (expected 0x04, sent 0x20)...
    emitted, _ = await send_timecode(axil, dut.clk, 0x20)
    assert not emitted, "out-of-sequence Time-Code was emitted in strict mode"

    # ...but it updated the local count, so the next in-sequence value (0x21)
    # emits again.
    emitted, rx = await send_timecode(axil, dut.clk, 0x21)
    assert emitted, "Time-Code following the jump (0x21 = 0x20+1) was not emitted"
    assert rx == 0x21

    # A repeat (same value, not previous+1) must not emit either.
    emitted, _ = await send_timecode(axil, dut.clk, 0x21)
    assert not emitted, "repeated Time-Code was emitted in strict mode"

    # Wrap-around across the 6-bit boundary stays in sequence: 0x3F -> 0x00.
    emitted, _ = await send_timecode(axil, dut.clk, 0x3E)
    # 0x3E is not 0x22, so it is out of sequence -> no emit, but updates count.
    assert not emitted
    emitted, rx = await send_timecode(axil, dut.clk, 0x3F)
    assert emitted and rx == 0x3F, "0x3F (0x3E+1) should emit"
    emitted, rx = await send_timecode(axil, dut.clk, 0x00)
    assert emitted and rx == 0x00, "wrap 0x3F->0x00 should emit"
