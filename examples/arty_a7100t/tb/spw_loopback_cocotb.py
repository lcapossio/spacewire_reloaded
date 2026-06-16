# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""Functional sim of the Arty loopback example engine + SpaceWire core.

Drives the engine's AXI4 slave with single-beat transactions, exactly as the
fpgacapZero EJTAG-AXI bridge does on hardware, and checks: example ID, the
SpaceWire CORE_ID read back over AXI-Lite, automatic link bring-up, the fabric
self-check result/counters, and a host-driven data-mover loopback.
"""

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ReadOnly

# Register byte offsets (see spw_loopback_axi.v)
EXAMPLE_ID  = 0x00
EXAMPLE_VER = 0x04
SCRATCH     = 0x08
CTRL        = 0x0C
STATUS      = 0x10
SPW_COREID  = 0x14
SPW_STATUS  = 0x18
TXDATA      = 0x1C
RXDATA      = 0x20
TXCOUNT     = 0x24
RXCOUNT     = 0x28
ERRCOUNT    = 0x2C

# STATUS bits
ST_LINK_RUNNING  = 1 << 0
ST_SELFTEST_BUSY = 1 << 1
ST_SELFTEST_DONE = 1 << 2
ST_SELFTEST_PASS = 1 << 3
ST_BRINGUP_DONE  = 1 << 6

SELFTEST_LEN = 16


async def axi_write(dut, addr, data, strb=0xF):
    dut.s_axi_awaddr.value = addr
    dut.s_axi_awlen.value = 0
    dut.s_axi_awvalid.value = 1
    dut.s_axi_wdata.value = data
    dut.s_axi_wstrb.value = strb
    dut.s_axi_wlast.value = 1
    dut.s_axi_wvalid.value = 1
    dut.s_axi_bready.value = 1
    aw = w = False
    while True:
        await ReadOnly()
        aw_hs = (not aw) and dut.s_axi_awready.value == 1
        w_hs = (not w) and dut.s_axi_wready.value == 1
        await RisingEdge(dut.clk)
        if aw_hs:
            dut.s_axi_awvalid.value = 0
            aw = True
        if w_hs:
            dut.s_axi_wvalid.value = 0
            w = True
        if aw and w:
            break
    while True:
        await ReadOnly()
        b = dut.s_axi_bvalid.value == 1
        await RisingEdge(dut.clk)
        if b:
            dut.s_axi_bready.value = 0
            break


async def axi_read(dut, addr):
    dut.s_axi_araddr.value = addr
    dut.s_axi_arlen.value = 0
    dut.s_axi_arvalid.value = 1
    dut.s_axi_rready.value = 1
    ar = False
    data = 0
    while True:
        await ReadOnly()
        ar_hs = (not ar) and dut.s_axi_arready.value == 1
        r_hs = dut.s_axi_rvalid.value == 1
        if r_hs:
            data = int(dut.s_axi_rdata.value)
        await RisingEdge(dut.clk)
        if ar_hs:
            dut.s_axi_arvalid.value = 0
            ar = True
        if r_hs:
            dut.s_axi_rready.value = 0
            break
    return data


async def poll_until(dut, addr, mask, timeout=200000):
    for _ in range(timeout):
        val = await axi_read(dut, addr)
        if val & mask:
            return val
        await RisingEdge(dut.clk)
    raise TimeoutError(f"bit(s) {mask:#x} never set at {addr:#x} (last={val:#x})")


async def reset(dut):
    dut.rst.value = 1
    for sig in ("s_axi_awvalid", "s_axi_wvalid", "s_axi_bready",
                "s_axi_arvalid", "s_axi_rready", "s_axi_awlen", "s_axi_arlen",
                "s_axi_awaddr", "s_axi_wdata", "s_axi_wstrb", "s_axi_wlast",
                "s_axi_araddr"):
        getattr(dut, sig).value = 0
    for _ in range(16):
        await RisingEdge(dut.clk)
    dut.rst.value = 0
    for _ in range(4):
        await RisingEdge(dut.clk)


@cocotb.test()
async def test_loopback_selftest(dut):
    """Identity, AXI-Lite CORE_ID readback, link bring-up, fabric self-check."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    assert await axi_read(dut, EXAMPLE_ID) == 0x5350574C, "example ID mismatch"
    ver = await axi_read(dut, EXAMPLE_VER)
    # low byte is an ASCII HDL fingerprint ('V'=Verilog, 'H'=VHDL)
    assert (ver >> 8) == 0x000100, f"example version mismatch {ver:#010x}"
    assert (ver & 0xFF) in (ord("V"), ord("H")), f"unknown HDL tag {ver:#010x}"

    # Scratch register R/W sanity (what a host 'probe' would do first).
    await axi_write(dut, SCRATCH, 0xDEADBEEF)
    assert await axi_read(dut, SCRATCH) == 0xDEADBEEF, "scratch R/W failed"

    # The engine auto-brings up the link via AXI-Lite; CORE_ID is read back.
    await poll_until(dut, STATUS, ST_BRINGUP_DONE)
    assert await axi_read(dut, SPW_COREID) == 0x53505752, "spw CORE_ID readback wrong"

    # Link establishes in loopback, then the fabric self-check runs.
    await poll_until(dut, STATUS, ST_LINK_RUNNING)
    st = await poll_until(dut, STATUS, ST_SELFTEST_DONE)
    assert st & ST_SELFTEST_PASS, f"self-check did not pass (STATUS={st:#x})"

    txc = await axi_read(dut, TXCOUNT)
    rxc = await axi_read(dut, RXCOUNT)
    errc = await axi_read(dut, ERRCOUNT)
    assert txc == SELFTEST_LEN + 1, f"TXCOUNT={txc}"
    assert rxc == SELFTEST_LEN + 1, f"RXCOUNT={rxc}"
    assert errc == 0, f"ERRCOUNT={errc}"
    dut._log.info(f"self-check pass: TX={txc} RX={rxc} ERR={errc}")


@cocotb.test()
async def test_host_data_mover(dut):
    """Host-driven loopback through TXDATA/RXDATA after taking manual control."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Take manual control before the link comes up so the fabric self-check
    # never engages the AXI-Stream; then wait for link bring-up.
    await axi_write(dut, CTRL, 0x0)
    await poll_until(dut, STATUS, ST_LINK_RUNNING)
    for _ in range(50):
        await RisingEdge(dut.clk)

    # Push a packet: data bytes then EOP (tlast=1, tuser=0).
    payload = [0xA5, 0x5A, 0x00, 0xFF, 0x10]
    for b in payload:
        await axi_write(dut, TXDATA, b)            # data char
    await axi_write(dut, TXDATA, (1 << 8))         # EOP: tlast=1, data=0

    # Pop looped-back beats from RXDATA (bit31 = valid).
    got = []
    for _ in range(20000):
        val = await axi_read(dut, RXDATA)
        if val & (1 << 31):
            got.append(val & 0x3FF)  # {tuser,tlast,data}
            if val & (1 << 8):       # tlast -> end of packet
                break
        else:
            await RisingEdge(dut.clk)
    else:
        raise TimeoutError("no EOP received in data-mover loopback")

    rx_data = [g & 0xFF for g in got[:-1]]
    assert rx_data == payload, f"data-mover loopback mismatch: {rx_data} != {payload}"
    assert got[-1] & (1 << 8), "last beat not marked tlast"
    assert (got[-1] & (1 << 9)) == 0, "EOP should have tuser=0"
    dut._log.info(f"data-mover loopback ok: {rx_data}")
