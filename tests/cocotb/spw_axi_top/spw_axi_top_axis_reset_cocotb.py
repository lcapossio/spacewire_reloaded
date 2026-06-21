# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

"""AXI-Stream compliance: a CONTROL[0] soft reset must not retract m_axis TVALID
mid-beat. AXI-Stream requires TVALID, once asserted, to stay asserted with stable
payload until TREADY completes the handshake; the only exception is the AXI bus
reset (ARESETn). The soft reset is a CSR bit, not the bus reset, so dropping
TVALID because of it (while rst is deasserted and TREADY is low) is illegal."""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotbext.axi import AxiLiteBus, AxiLiteMaster, AxiStreamBus, AxiStreamFrame, AxiStreamSource

REG_CONTROL = 0x08
REG_STATUS = 0x0C
REG_TXDIVCNT = 0x10


@cocotb.test()
async def m_axis_tvalid_not_retracted_by_soft_reset(dut):
    cocotb.start_soon(Clock(dut.clk, 50, unit="ns").start())
    cocotb.start_soon(Clock(dut.rxclk, 20, unit="ns").start())
    cocotb.start_soon(Clock(dut.txclk, 20, unit="ns").start())

    dut.rst.value = 1
    for sig in ("s_axi_awaddr", "s_axi_awvalid", "s_axi_wdata", "s_axi_wstrb",
                "s_axi_wvalid", "s_axi_bready", "s_axi_araddr", "s_axi_arvalid",
                "s_axi_rready", "s_axis_tdata", "s_axis_tvalid", "s_axis_tlast",
                "s_axis_tuser", "m_axis_tready"):
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

    await axil.write_dword(REG_TXDIVCNT, 0x00000001)
    await axil.write_dword(REG_CONTROL, 0x00000006)  # autostart|linkstart
    for _ in range(30000):
        if (await axil.read_dword(REG_STATUS)) & (1 << 2):
            break
        await RisingEdge(dut.clk)

    # m_axis_tready stays 0 (downstream backpressure). Loop a packet back so the
    # RX FIFO presents a beat that is held on m_axis.
    source.send_nowait(AxiStreamFrame(b"\x10\x11\x12\x00", tuser=[0, 0, 0, 0]))
    for _ in range(30000):
        await RisingEdge(dut.clk)
        if int(dut.m_axis_tvalid.value) == 1:
            break
    assert int(dut.m_axis_tvalid.value) == 1, "no held m_axis beat to test"
    assert int(dut.m_axis_tready.value) == 0
    assert int(dut.rst.value) == 0

    # Issue the CONTROL[0] soft reset while the beat is held and watch TVALID.
    await axil.write_dword(REG_CONTROL, 0x00000001)
    for _ in range(64):
        await RisingEdge(dut.clk)
        if int(dut.rst.value) != 0:
            return  # a real bus reset would legitimately clear TVALID
        if int(dut.m_axis_tready.value) == 1:
            return  # a handshake legitimately completes the beat
        assert int(dut.m_axis_tvalid.value) == 1, (
            "AXI-Stream violation: m_axis TVALID retracted by a CONTROL[0] soft "
            "reset without a handshake (rst deasserted, TREADY low)"
        )
