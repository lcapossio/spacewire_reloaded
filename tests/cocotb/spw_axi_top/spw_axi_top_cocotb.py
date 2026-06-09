# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout
from cocotbext.axi import (
    AxiLiteBus,
    AxiLiteMaster,
    AxiStreamBus,
    AxiStreamFrame,
    AxiStreamSink,
    AxiStreamSource,
)
from tests.cocotb.axi_protocol_assertions import start_axil_assertions, start_axis_assertions


REG_CONTROL = 0x08
REG_STATUS = 0x0C
REG_TXDIVCNT = 0x10
REG_TIMECODE_TX = 0x14
REG_TIMECODE_RX = 0x18
REG_ERROR = 0x1C


def pause_cycles(pattern):
    while True:
        for paused in pattern:
            yield paused


async def reset_dut(dut):
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def wait_running(axil):
    for _ in range(30000):
        status = await axil.read_dword(REG_STATUS)
        if status & (1 << 2):
            return
    raise AssertionError("AXI-wrapped SpaceWire core did not enter Run state")


async def configure_running(axil):
    await axil.write_dword(REG_TXDIVCNT, 0x00000001)
    await axil.write_dword(REG_CONTROL, 0x00000006)
    await wait_running(axil)


def nchar_frame(payload, terminator=0x00):
    return AxiStreamFrame(bytes([*payload, terminator]), tuser=[0] * len(payload) + [1])


async def expect_frame(sink, payload, terminator=0x00, timeout="2ms"):
    received = await with_timeout(sink.recv(), 2, timeout[-2:] if timeout.endswith("ms") else "ms")
    expected = bytes([*payload, terminator])
    assert bytes(received.tdata) == expected
    assert list(received.tuser) == [0] * len(payload) + [1]


async def send_and_scoreboard(source, sink, packets):
    expected = []
    for payload, terminator in packets:
        source.send_nowait(nchar_frame(payload, terminator))
        expected.append((payload, terminator))

    for payload, terminator in expected:
        received = await with_timeout(sink.recv(), 2, "ms")
        assert bytes(received.tdata) == bytes([*payload, terminator])
        assert list(received.tuser) == [0] * len(payload) + [1]


def start_common_assertions(dut):
    start_axil_assertions(cocotb, dut)
    start_axis_assertions(cocotb, dut, "s_axis")
    start_axis_assertions(cocotb, dut, "m_axis")


@cocotb.test()
async def axi_top_loops_axis_packet_through_spw_link(dut):
    cocotb.start_soon(Clock(dut.clk, 50, units="ns").start())
    cocotb.start_soon(Clock(dut.rxclk, 20, units="ns").start())
    cocotb.start_soon(Clock(dut.txclk, 20, units="ns").start())
    start_common_assertions(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)

    axil.write_if.aw_channel.set_pause_generator(pause_cycles([False, True, False, False]))
    axil.write_if.w_channel.set_pause_generator(pause_cycles([False, False, True]))
    axil.write_if.b_channel.set_pause_generator(pause_cycles([False, True, False]))
    axil.read_if.ar_channel.set_pause_generator(pause_cycles([False, False, True, False]))
    axil.read_if.r_channel.set_pause_generator(pause_cycles([False, True, False]))
    source.set_pause_generator(pause_cycles([False, False, True, False]))
    sink.set_pause_generator(pause_cycles([True, False, False, False, True, False]))

    await reset_dut(dut)
    await configure_running(axil)

    payload = bytes([0x40 + i for i in range(12)] + [0x00])
    frame = AxiStreamFrame(payload, tuser=[0] * 12 + [1])
    await source.send(frame)
    received = await with_timeout(sink.recv(), 2, "ms")

    assert bytes(received.tdata) == payload
    assert list(received.tuser) == [0] * 12 + [1]

    write_task = cocotb.start_soon(axil.write_dword(REG_TIMECODE_TX, 0x80000095))
    await with_timeout(write_task, 100, "us")
    rx_timecode = 0
    for _ in range(5000):
        rx_timecode = await axil.read_dword(REG_TIMECODE_RX)
        if rx_timecode & (1 << 31):
            break
        await RisingEdge(dut.clk)

    assert rx_timecode == 0x80000095
    await axil.write(REG_TIMECODE_RX + 3, bytes([0x80]))
    assert await axil.read_dword(REG_TIMECODE_RX) == 0x00000095


@cocotb.test()
async def axi_top_scores_multiple_packets_eop_eep_and_boundary_stalls(dut):
    cocotb.start_soon(Clock(dut.clk, 50, units="ns").start())
    cocotb.start_soon(Clock(dut.rxclk, 20, units="ns").start())
    cocotb.start_soon(Clock(dut.txclk, 20, units="ns").start())
    start_common_assertions(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)

    axil.write_if.aw_channel.set_pause_generator(pause_cycles([False, True, False, False, False]))
    axil.write_if.w_channel.set_pause_generator(pause_cycles([False, False, True, False]))
    axil.write_if.b_channel.set_pause_generator(pause_cycles([True, False, False, True, False]))
    axil.read_if.ar_channel.set_pause_generator(pause_cycles([False, False, True, False]))
    axil.read_if.r_channel.set_pause_generator(pause_cycles([False, True, False, False]))
    source.set_pause_generator(pause_cycles([False, False, True, False, True, False, False]))
    sink.set_pause_generator(pause_cycles([True, True, False, False, True, False]))

    await reset_dut(dut)
    await configure_running(axil)

    packets = [
        ([], 0x00),
        ([0x11], 0x00),
        ([0x20 + i for i in range(5)], 0x00),
        ([0x80 + i for i in range(9)], 0x01),
        ([0xA5, 0x5A, 0x00, 0xFF], 0x00),
        ([((i * 37) + 11) & 0xFF for i in range(15)], 0x00),
    ]
    await send_and_scoreboard(source, sink, packets)


@cocotb.test()
async def axi_top_recovers_from_stream_reset_and_link_reconnect(dut):
    cocotb.start_soon(Clock(dut.clk, 50, units="ns").start())
    cocotb.start_soon(Clock(dut.rxclk, 20, units="ns").start())
    cocotb.start_soon(Clock(dut.txclk, 20, units="ns").start())
    start_common_assertions(dut)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)
    source.set_pause_generator(pause_cycles([False, True, False, False]))
    sink.set_pause_generator(pause_cycles([False, False, True, False]))

    await reset_dut(dut)
    await configure_running(axil)

    partial = cocotb.start_soon(source.send(nchar_frame([0x30 + i for i in range(10)], 0x00)))
    for _ in range(8):
        await RisingEdge(dut.clk)
    dut.rst.value = 1
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    partial.kill()
    source.clear()
    sink.clear()

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)
    source.set_pause_generator(pause_cycles([False, False, True, False]))
    sink.set_pause_generator(pause_cycles([True, False, False, False]))

    await configure_running(axil)
    await send_and_scoreboard(source, sink, [([0x55, 0xAA, 0x12], 0x00)])

    await axil.write_dword(REG_CONTROL, 0x0000000E)
    for _ in range(100):
        await RisingEdge(dut.clk)
    await axil.write_dword(REG_CONTROL, 0x00000006)
    await wait_running(axil)
    await axil.write(REG_ERROR, bytes([0x0F]))
    assert (await axil.read_dword(REG_ERROR)) & 0x0E == 0

    await send_and_scoreboard(
        source,
        sink,
        [
            ([0xC0 + i for i in range(3)], 0x00),
            ([0xD0 + i for i in range(4)], 0x01),
        ],
    )
