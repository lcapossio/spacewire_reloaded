# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout
from cocotbext.axi import AxiLiteBus, AxiLiteMaster


REG_CORE_ID = 0x00
REG_VERSION = 0x04
REG_CONTROL = 0x08
REG_STATUS = 0x0C
REG_TXDIVCNT = 0x10
REG_TIMECODE_TX = 0x14
REG_TIMECODE_RX = 0x18
REG_ERROR = 0x1C
REG_IRQ_ENABLE = 0x20


def value(signal):
    return int(signal.value)


def pause_cycles(pattern):
    while True:
        for paused in pattern:
            yield paused


async def reset_dut(dut):
    dut.rst.value = 1
    dut.tick_out.value = 0
    dut.ctrl_out.value = 0
    dut.time_out.value = 0
    dut.txrdy.value = 0
    dut.txhalff.value = 0
    dut.rxvalid.value = 0
    dut.rxhalff.value = 0
    dut.started.value = 0
    dut.connecting.value = 0
    dut.running.value = 0
    dut.errdisc.value = 0
    dut.errpar.value = 0
    dut.erresc.value = 0
    dut.errcred.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


def make_axil_master(dut):
    master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    master.write_if.aw_channel.set_pause_generator(pause_cycles([False, True, False, False]))
    master.write_if.w_channel.set_pause_generator(pause_cycles([False, False, True]))
    master.write_if.b_channel.set_pause_generator(pause_cycles([False, True, False]))
    master.read_if.ar_channel.set_pause_generator(pause_cycles([False, True, False, False]))
    master.read_if.r_channel.set_pause_generator(pause_cycles([False, False, True, False]))
    return master


async def axil_write_dword(master, addr, data):
    resp = await master.write_dword(addr, data)
    assert resp is None


async def axil_read_dword(master, addr):
    return await master.read_dword(addr)


@cocotb.test()
async def axi_lite_registers_drive_spw_controls(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    axil = make_axil_master(dut)
    await reset_dut(dut)

    assert await axil_read_dword(axil, REG_CORE_ID) == 0x53505752
    assert await axil_read_dword(axil, REG_VERSION) == 0x00010000

    await axil_write_dword(axil, REG_CONTROL, 0x0000000E)
    assert value(dut.core_rst) == 0
    assert value(dut.autostart) == 1
    assert value(dut.linkstart) == 1
    assert value(dut.linkdis) == 1
    assert await axil_read_dword(axil, REG_CONTROL) == 0x0000000E

    await axil_write_dword(axil, REG_TXDIVCNT, 0x0000003C)
    assert value(dut.txdivcnt) == 0x3C
    assert await axil_read_dword(axil, REG_TXDIVCNT) == 0x0000003C

    dut.txrdy.value = 1
    dut.rxvalid.value = 1
    dut.running.value = 1
    status = await axil_read_dword(axil, REG_STATUS)
    assert status & (1 << 2)
    assert status & (1 << 3)
    assert status & (1 << 5)


@cocotb.test()
async def axi_lite_timecodes_errors_and_irq_are_sticky_until_cleared(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    axil = make_axil_master(dut)
    await reset_dut(dut)

    write_task = cocotb.start_soon(axil.write_dword(REG_TIMECODE_TX, 0x80000095))
    saw_tick = False
    for _ in range(16):
        await RisingEdge(dut.clk)
        await Timer(1, units="ns")
        if value(dut.tick_in) == 1:
            saw_tick = True
            assert value(dut.ctrl_in) == 2
            assert value(dut.time_in) == 0x15
    await with_timeout(write_task, 100, "ns")
    assert saw_tick
    await RisingEdge(dut.clk)
    await Timer(1, units="ns")
    assert value(dut.tick_in) == 0

    dut.tick_out.value = 1
    dut.ctrl_out.value = 3
    dut.time_out.value = 0x2A
    await RisingEdge(dut.clk)
    dut.tick_out.value = 0
    rx_timecode = await axil_read_dword(axil, REG_TIMECODE_RX)
    assert rx_timecode == 0x800000EA
    await axil.write(REG_TIMECODE_RX + 3, bytes([0x80]))
    assert await axil_read_dword(axil, REG_TIMECODE_RX) == 0x000000EA

    await axil_write_dword(axil, REG_IRQ_ENABLE, 0x00000001)
    dut.errdisc.value = 1
    await RisingEdge(dut.clk)
    dut.errdisc.value = 0
    assert await axil_read_dword(axil, REG_ERROR) == 0x00000001
    assert value(dut.irq) == 1
    await axil.write(REG_ERROR, bytes([0x01]))
    assert await axil_read_dword(axil, REG_ERROR) == 0x00000000
    await Timer(1, units="ns")
    assert value(dut.irq) == 0
