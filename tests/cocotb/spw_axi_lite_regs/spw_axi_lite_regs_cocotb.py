# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout
from cocotbext.axi import AxiLiteBus, AxiLiteMaster
from tests.cocotb.axi_protocol_assertions import start_axil_assertions


REG_CORE_ID = 0x00
REG_VERSION = 0x04
REG_CONTROL = 0x08
REG_STATUS = 0x0C
REG_TXDIVCNT = 0x10
REG_TIMECODE_TX = 0x14
REG_TIMECODE_RX = 0x18
REG_ERROR = 0x1C
REG_IRQ_ENABLE = 0x20
REG_IRQ_STATUS = 0x24


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


def start_common_assertions(dut):
    start_axil_assertions(cocotb, dut)


def make_axil_master(dut):
    master = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    master.write_if.aw_channel.set_pause_generator(pause_cycles([False, True, False, False]))
    master.write_if.w_channel.set_pause_generator(pause_cycles([False, False, True]))
    master.write_if.b_channel.set_pause_generator(pause_cycles([False, True, False]))
    master.read_if.ar_channel.set_pause_generator(pause_cycles([False, True, False, False]))
    master.read_if.r_channel.set_pause_generator(pause_cycles([False, False, True, False]))
    return master


def initialize_manual_axil_signals(dut):
    dut.s_axi_awaddr.value = 0
    dut.s_axi_awvalid.value = 0
    dut.s_axi_wdata.value = 0
    dut.s_axi_wstrb.value = 0
    dut.s_axi_wvalid.value = 0
    dut.s_axi_bready.value = 0
    dut.s_axi_araddr.value = 0
    dut.s_axi_arvalid.value = 0
    dut.s_axi_rready.value = 0


async def axil_write_dword(master, addr, data):
    resp = await master.write_dword(addr, data)
    assert resp is None


async def axil_read_dword(master, addr):
    return await master.read_dword(addr)


async def wait_handshake(dut, valid, ready, name, max_cycles=64):
    for _ in range(max_cycles):
        await Timer(1, units="ns")
        if value(valid) and value(ready):
            await RisingEdge(dut.clk)
            return
        await RisingEdge(dut.clk)
    raise AssertionError(f"timed out waiting for {name} handshake")


async def wait_signal_high(dut, signal, name, max_cycles=64):
    for _ in range(max_cycles):
        await Timer(1, units="ns")
        if value(signal):
            return
        await RisingEdge(dut.clk)
    raise AssertionError(f"timed out waiting for {name}")


async def manual_write_aw_then_w(dut, addr, data, wstrb=0xF, aw_delay=0, w_delay=4, bready_delay=3):
    dut.s_axi_awaddr.value = addr
    dut.s_axi_awvalid.value = 0
    dut.s_axi_wdata.value = data
    dut.s_axi_wstrb.value = wstrb
    dut.s_axi_wvalid.value = 0
    dut.s_axi_bready.value = 0

    for _ in range(aw_delay):
        await RisingEdge(dut.clk)
    dut.s_axi_awvalid.value = 1
    await wait_handshake(dut, dut.s_axi_awvalid, dut.s_axi_awready, "AW")
    dut.s_axi_awvalid.value = 0

    for _ in range(w_delay):
        await RisingEdge(dut.clk)
    dut.s_axi_wvalid.value = 1
    await wait_handshake(dut, dut.s_axi_wvalid, dut.s_axi_wready, "W")
    dut.s_axi_wvalid.value = 0

    for _ in range(bready_delay):
        await RisingEdge(dut.clk)
    dut.s_axi_bready.value = 1
    await wait_signal_high(dut, dut.s_axi_bvalid, "BVALID")
    assert value(dut.s_axi_bresp) == 0
    await RisingEdge(dut.clk)
    dut.s_axi_bready.value = 0


async def manual_write_w_then_aw(dut, addr, data, wstrb=0xF, w_delay=0, aw_delay=4, bready_delay=3):
    dut.s_axi_awaddr.value = addr
    dut.s_axi_awvalid.value = 0
    dut.s_axi_wdata.value = data
    dut.s_axi_wstrb.value = wstrb
    dut.s_axi_wvalid.value = 0
    dut.s_axi_bready.value = 0

    for _ in range(w_delay):
        await RisingEdge(dut.clk)
    dut.s_axi_wvalid.value = 1
    await wait_handshake(dut, dut.s_axi_wvalid, dut.s_axi_wready, "W")
    dut.s_axi_wvalid.value = 0

    for _ in range(aw_delay):
        await RisingEdge(dut.clk)
    dut.s_axi_awvalid.value = 1
    await wait_handshake(dut, dut.s_axi_awvalid, dut.s_axi_awready, "AW")
    dut.s_axi_awvalid.value = 0

    for _ in range(bready_delay):
        await RisingEdge(dut.clk)
    dut.s_axi_bready.value = 1
    await wait_signal_high(dut, dut.s_axi_bvalid, "BVALID")
    assert value(dut.s_axi_bresp) == 0
    await RisingEdge(dut.clk)
    dut.s_axi_bready.value = 0


@cocotb.test()
async def axi_lite_registers_drive_spw_controls(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    start_common_assertions(dut)
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
    start_common_assertions(dut)
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


@cocotb.test()
async def axi_lite_randomized_register_backpressure_and_strobes(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    start_common_assertions(dut)
    axil = make_axil_master(dut)
    await reset_dut(dut)

    expected_control = 0
    expected_txdiv = 0
    seed = 0xACE1

    for _ in range(32):
        seed = ((seed * 1103515245) + 12345) & 0xFFFFFFFF
        if seed & 1:
            data = (seed >> 4) & 0x0F
            await axil_write_dword(axil, REG_CONTROL, data)
            expected_control = data
            assert await axil_read_dword(axil, REG_CONTROL) == expected_control
            assert value(dut.autostart) == ((expected_control >> 1) & 1)
            assert value(dut.linkstart) == ((expected_control >> 2) & 1)
            assert value(dut.linkdis) == ((expected_control >> 3) & 1)
        else:
            data = (seed >> 8) & 0xFF
            await axil.write(REG_TXDIVCNT, bytes([data]))
            expected_txdiv = data
            assert await axil_read_dword(axil, REG_TXDIVCNT) == expected_txdiv
            assert value(dut.txdivcnt) == expected_txdiv

        dut.started.value = (seed >> 3) & 1
        dut.connecting.value = (seed >> 4) & 1
        dut.running.value = (seed >> 5) & 1
        dut.txrdy.value = (seed >> 6) & 1
        dut.txhalff.value = (seed >> 7) & 1
        dut.rxvalid.value = (seed >> 8) & 1
        dut.rxhalff.value = (seed >> 9) & 1
        await RisingEdge(dut.clk)
        status = await axil_read_dword(axil, REG_STATUS)
        assert (status & 0x7F) == (
            value(dut.started)
            | (value(dut.connecting) << 1)
            | (value(dut.running) << 2)
            | (value(dut.txrdy) << 3)
            | (value(dut.txhalff) << 4)
            | (value(dut.rxvalid) << 5)
            | (value(dut.rxhalff) << 6)
        )

    dut.errdisc.value = 1
    dut.errpar.value = 1
    dut.erresc.value = 1
    dut.errcred.value = 1
    await RisingEdge(dut.clk)
    dut.errdisc.value = 0
    dut.errpar.value = 0
    dut.erresc.value = 0
    dut.errcred.value = 0
    assert await axil_read_dword(axil, REG_ERROR) == 0x0000000F
    await axil.write(REG_ERROR, bytes([0x05]))
    assert await axil_read_dword(axil, REG_ERROR) == 0x0000000A
    await axil.write(REG_IRQ_STATUS, bytes([0x01]))
    assert await axil_read_dword(axil, REG_ERROR) == 0x00000000


@cocotb.test()
async def axi_lite_recovers_from_reset_with_response_pending(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    start_common_assertions(dut)
    axil = make_axil_master(dut)
    await reset_dut(dut)

    axil.write_if.b_channel.set_pause_generator(pause_cycles([True]))
    pending_write = cocotb.start_soon(axil.write_dword(REG_CONTROL, 0x0000000E))

    for _ in range(16):
        await RisingEdge(dut.clk)
        if value(dut.s_axi_bvalid) == 1:
            break
    assert value(dut.s_axi_bvalid) == 1

    dut.rst.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    pending_write.kill()

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)

    assert await axil_read_dword(axil, REG_CORE_ID) == 0x53505752
    assert await axil_read_dword(axil, REG_CONTROL) == 0x00000000
    assert value(dut.autostart) == 0
    assert value(dut.linkstart) == 0
    assert value(dut.linkdis) == 0


@cocotb.test()
async def axi_lite_accepts_independent_aw_w_ordering(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    start_common_assertions(dut)
    initialize_manual_axil_signals(dut)
    await reset_dut(dut)

    await manual_write_aw_then_w(dut, REG_CONTROL, 0x00000006, w_delay=7, bready_delay=5)
    assert value(dut.autostart) == 1
    assert value(dut.linkstart) == 1
    assert value(dut.linkdis) == 0

    await manual_write_w_then_aw(dut, REG_CONTROL, 0x00000008, aw_delay=7, bready_delay=5)
    assert value(dut.autostart) == 0
    assert value(dut.linkstart) == 0
    assert value(dut.linkdis) == 1

    await manual_write_aw_then_w(dut, REG_TXDIVCNT, 0x000000A5, wstrb=0x1, w_delay=5)
    assert value(dut.txdivcnt) == 0xA5

    await manual_write_w_then_aw(dut, REG_TXDIVCNT, 0x0000003C, wstrb=0x1, aw_delay=5)
    assert value(dut.txdivcnt) == 0x3C

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    assert await axil_read_dword(axil, REG_TXDIVCNT) == 0x0000003C
