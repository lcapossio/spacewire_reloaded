# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

"""End-to-end proof that the cocotbext-axi fork's built-in handshake checker
(``check_protocol=True``) catches the Bug 26 AXI-Stream violation on the real
DUT.

Unlike spw_axi_top_axis_reset_cocotb (which controls m_axis_tready by hand and
asserts inline), this test wires a real ``AxiStreamSink`` to m_axis with the
fork's protocol checker enabled and holds it paused (TREADY=0). A received beat
is presented on m_axis and held; a CONTROL[0] soft reset is then issued. The
verdict is delegated entirely to the fork's background ``check_handshake``
coroutine: if the DUT retracts TVALID without a handshake, the fork raises and
fails the test. With the register-slice RX bridge in place the beat survives and
the test passes."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
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


@cocotb.test()
async def fork_checker_catches_soft_reset_tvalid_retraction(dut):
    cocotb.start_soon(Clock(dut.clk, 50, unit="ns").start())
    cocotb.start_soon(Clock(dut.rxclk, 20, unit="ns").start())
    cocotb.start_soon(Clock(dut.txclk, 20, unit="ns").start())

    dut.rst.value = 1
    for sig in ("s_axi_awaddr", "s_axi_awvalid", "s_axi_wdata", "s_axi_wstrb",
                "s_axi_wvalid", "s_axi_bready", "s_axi_araddr", "s_axi_arvalid",
                "s_axi_rready", "s_axis_tdata", "s_axis_tvalid", "s_axis_tlast",
                "s_axis_tuser"):
        getattr(dut, sig).value = 0
    if hasattr(dut, "spw_di_ext"):
        dut.spw_di_ext.value = 0
        dut.spw_si_ext.value = 0
    for _ in range(3):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    await RisingEdge(dut.clk)

    axil = AxiLiteMaster(AxiLiteBus.from_prefix(dut, "s_axi"), dut.clk, dut.rst)
    source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.clk, dut.rst)
    # The fork's handshake checker is the judge for this test.
    sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.clk, dut.rst,
                         check_protocol=True)
    # Hold downstream backpressure: TREADY stays 0 so a received beat is held.
    sink.pause = True

    await axil.write_dword(REG_TXDIVCNT, 0x00000001)
    await axil.write_dword(REG_CONTROL, 0x00000006)  # autostart|linkstart
    for _ in range(30000):
        if (await axil.read_dword(REG_STATUS)) & (1 << 2):
            break
        await RisingEdge(dut.clk)

    # Loop a packet back so the RX FIFO presents a beat that is held on m_axis.
    source.send_nowait(AxiStreamFrame(b"\x10\x11\x12\x00", tuser=[0, 0, 0, 0]))
    for _ in range(30000):
        await RisingEdge(dut.clk)
        if int(dut.m_axis_tvalid.value) == 1:
            break

    # Precondition: a beat must actually be held (TVALID=1, TREADY=0, no bus rst)
    # so that the soft reset below exercises the retraction path.
    assert int(dut.m_axis_tvalid.value) == 1, "no held m_axis beat to test"
    assert int(dut.m_axis_tready.value) == 0, "sink should be backpressuring"
    assert int(dut.rst.value) == 0, "bus reset must be deasserted"

    # Issue the CONTROL[0] soft reset while the beat is held. The fork's
    # check_handshake coroutine watches m_axis every cycle; an illegal TVALID
    # retraction (rst low, TREADY low, no handshake) raises and fails the test.
    await axil.write_dword(REG_CONTROL, 0x00000001)
    for _ in range(64):
        await RisingEdge(dut.clk)
        if int(dut.rst.value) != 0:
            break  # a real bus reset would legitimately clear TVALID
        if int(dut.m_axis_tready.value) == 1:
            break  # a handshake legitimately completes the beat
