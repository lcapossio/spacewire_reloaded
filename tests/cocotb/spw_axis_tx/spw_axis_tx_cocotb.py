# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotbext.axi import AxiStreamBus, AxiStreamFrame, AxiStreamSource
from tests.cocotb.axi_protocol_assertions import start_axis_assertions


async def reset_dut(dut):
    dut.rst.value = 1
    dut.txrdy.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)


@cocotb.test()
async def axis_tx_maps_nchars_to_spw_tx(dut):
    cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
    await reset_dut(dut)
    start_axis_assertions(cocotb, dut, "s_axis")
    source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)

    dut.txrdy.value = 0
    source.send_nowait(AxiStreamFrame([0x5A, 0x00], tuser=[1, 0]))

    accepted = []
    for cycle in range(24):
        dut.txrdy.value = 1 if cycle not in {1, 2, 7} else 0
        await Timer(1, units="ns")
        if dut.txwrite.value == 1:
            accepted.append((int(dut.txdata.value), int(dut.txflag.value)))
        await RisingEdge(dut.clk)

    assert accepted == [(0x5A, 0), (0x00, 1)]
    await source.wait()
    assert source.empty()

    source.send_nowait(AxiStreamFrame([0xA5, 0x01], tuser=[0, 1]))
    accepted = []
    for _ in range(8):
        dut.txrdy.value = 1
        await Timer(1, units="ns")
        if dut.txwrite.value == 1:
            accepted.append((int(dut.txdata.value), int(dut.txflag.value)))
        await RisingEdge(dut.clk)

    assert accepted == [(0xA5, 0), (0x01, 1)]
    await source.wait()
    assert source.empty()

    dut.txrdy.value = 0
    await Timer(1, units="ns")
    assert dut.s_axis_tready.value == 0
    assert dut.txwrite.value == 0

    dut.rst.value = 1
    await Timer(1, units="ns")
    assert dut.s_axis_tready.value == 0
    assert dut.txwrite.value == 0
