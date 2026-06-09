# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
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


@cocotb.test()
async def axis_rx_maps_spw_rx_to_nchar_stream(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    start_axis_assertions(cocotb, dut, "m_axis")
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst)
    sink.set_pause_generator(pause_cycles([True, False, False, True, False]))
    await reset_dut(dut)

    dut.rxvalid.value = 1
    dut.rxflag.value = 0
    dut.rxdata.value = 0x33

    while dut.rxread.value == 0:
        await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rxflag.value = 1
    dut.rxdata.value = 0x01

    while dut.rxread.value == 0:
        await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rxvalid.value = 0

    frame = await sink.recv()
    assert bytes(frame.tdata) == bytes([0x33, 0x01])
    assert list(frame.tuser) == [0, 1]

    dut.rst.value = 1
    await Timer(1, units="ns")
    assert dut.m_axis_tvalid.value == 0
    assert dut.rxread.value == 0
