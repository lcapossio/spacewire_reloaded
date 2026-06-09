# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer, with_timeout
from cocotbext.axi import AxiStreamBus, AxiStreamSink
from tests.cocotb.axi_protocol_assertions import start_axis_assertions


def pause_cycles(pattern):
    while True:
        for paused in pattern:
            yield paused


async def reset_dut(dut):
    dut.rst.value = 1
    dut.rxvalid.value = 0
    dut.rxflag.value = 0
    dut.rxdata.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


async def send_rx_chars(dut, chars):
    dut.rxvalid.value = 1
    for data, flag in chars:
        dut.rxdata.value = data
        dut.rxflag.value = flag
        for _ in range(64):
            await Timer(1, units="ns")
            if dut.rxread.value == 1:
                await RisingEdge(dut.clk)
                break
            await RisingEdge(dut.clk)
        else:
            raise AssertionError("timed out waiting for rxread")

    dut.rxvalid.value = 0
    dut.rxflag.value = 0


def frame_user_bits(frame):
    if isinstance(frame.tuser, int):
        return [frame.tuser] * len(frame.tdata)
    return list(frame.tuser)


@cocotb.test()
async def axis_rx_maps_spw_rx_to_nchar_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    start_axis_assertions(cocotb, dut, "m_axis", reset_must_clear_valid=True)
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)
    sink.set_pause_generator(pause_cycles([True, False, False, True, False]))

    await send_rx_chars(dut, [(0x33, 0), (0x01, 1)])
    frame = await with_timeout(sink.recv(), 1, "us")
    assert bytes(frame.tdata) == bytes([0x33, 0x01])
    assert frame_user_bits(frame) == [0, 1]

    await send_rx_chars(dut, [(0x44, 0), (0x00, 1)])
    frame = await with_timeout(sink.recv(), 1, "us")
    assert bytes(frame.tdata) == bytes([0x44, 0x00])
    assert frame_user_bits(frame) == [0, 0]

    dut.rst.value = 1
    await Timer(1, units="ns")
    assert dut.m_axis_tvalid.value == 0
    assert dut.rxread.value == 0
