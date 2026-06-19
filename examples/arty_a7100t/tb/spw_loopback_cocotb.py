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
PKTCOUNT    = 0x30
ERRINJ      = 0x34
TIMECODE    = 0x38

TC_VALID    = 1 << 31   # TIMECODE read: a time-code was received
# RXDATA / TXDATA beat fields
BEAT_TLAST  = 1 << 8
BEAT_TUSER  = 1 << 9    # tuser -> EEP (error end of packet)
BEAT_VALID  = 1 << 31

# spw link-error bits within STATUS[11:8]
ERR_DISC = 1 << 8
ERR_PAR  = 1 << 9
ERR_ESC  = 1 << 10
ERR_CRED = 1 << 11
ERR_ANY  = 0xF << 8

INJ_FREEZE = 1 << 0
INJ_INVERT = 1 << 1

# STATUS bits
ST_LINK_RUNNING  = 1 << 0
ST_SELFTEST_BUSY = 1 << 1
ST_SELFTEST_DONE = 1 << 2
ST_SELFTEST_PASS = 1 << 3
ST_BRINGUP_DONE  = 1 << 6

# CTRL bits
CTRL_SELFTEST_EN   = 1 << 0
CTRL_SELFTEST_STRT = 1 << 1
CTRL_SOFT_RESET    = 1 << 2
CTRL_SELFTEST_LOOP = 1 << 3

SELFTEST_LEN = 16
SELFTEST_PKTS = 4


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


async def poll_until_clear(dut, addr, mask, timeout=200000):
    for _ in range(timeout):
        val = await axi_read(dut, addr)
        if not (val & mask):
            return val
        await RisingEdge(dut.clk)
    raise TimeoutError(f"bit(s) {mask:#x} never cleared at {addr:#x} (last={val:#x})")


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
    pkts = await axi_read(dut, PKTCOUNT)
    expected = SELFTEST_PKTS * (SELFTEST_LEN + 1)  # PRBS bytes + EOP, per packet
    assert txc == expected, f"TXCOUNT={txc} (expected {expected})"
    assert rxc == expected, f"RXCOUNT={rxc} (expected {expected})"
    assert pkts == SELFTEST_PKTS, f"PKTCOUNT={pkts} (expected {SELFTEST_PKTS})"
    assert errc == 0, f"ERRCOUNT={errc}"
    dut._log.info(f"self-check pass: {pkts} back-to-back PRBS packets, "
                  f"TX={txc} RX={rxc} ERR={errc}")


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


@cocotb.test()
async def test_continuous_loop(dut):
    """Continuous (loop) mode: free-running back-to-back PRBS, ERRCOUNT stays 0."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Enter continuous mode before the link comes up so the first self-check run
    # free-runs from a clean state (no mid-run restart / residual data). On
    # hardware the host instead restarts into loop mode after the power-on
    # one-shot run has finished and the link is idle.
    await axi_write(dut, CTRL, CTRL_SELFTEST_EN | CTRL_SELFTEST_LOOP)
    await poll_until(dut, STATUS, ST_LINK_RUNNING)

    pkts = 0
    for _ in range(60):
        for _ in range(1000):
            await RisingEdge(dut.clk)
        pkts = await axi_read(dut, PKTCOUNT)
        errs = await axi_read(dut, ERRCOUNT)
        assert errs == 0, f"errors during loop run: ERRCOUNT={errs} (PKTCOUNT={pkts})"
        if pkts >= 12:
            break
    else:
        raise TimeoutError(f"loop did not advance enough (PKTCOUNT={pkts})")

    # Confirm it is still busy (never 'done' in loop mode), then stop it.
    st = await axi_read(dut, STATUS)
    assert st & ST_SELFTEST_BUSY, f"loop should stay busy (STATUS={st:#x})"
    await axi_write(dut, CTRL, 0x0)  # selftest_en=0 -> stop
    txc = await axi_read(dut, TXCOUNT)
    rxc = await axi_read(dut, RXCOUNT)
    assert rxc >= pkts * (SELFTEST_LEN + 1), f"RXCOUNT={rxc} too low for {pkts} pkts"
    dut._log.info(f"continuous loop ok: {pkts} back-to-back packets, "
                  f"TX={txc} RX={rxc} ERR=0")


@cocotb.test()
async def test_error_injection(dut):
    """Inject errors on the internal loopback line and check link-error detection
    (sticky spw error bits + link drop) and recovery via soft_reset."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    # continuous self-check so chars are flowing for the invert (parity) case
    await axi_write(dut, CTRL, CTRL_SELFTEST_EN | CTRL_SELFTEST_LOOP)
    await poll_until(dut, STATUS, ST_LINK_RUNNING)
    assert not (await axi_read(dut, STATUS) & ERR_ANY), "unexpected error at start"

    async def recover():
        await axi_write(dut, ERRINJ, 0x0)
        await axi_write(dut, CTRL,
                        CTRL_SELFTEST_EN | CTRL_SELFTEST_LOOP | CTRL_SOFT_RESET)
        await poll_until(dut, STATUS, ST_LINK_RUNNING)        # link back up
        await poll_until_clear(dut, STATUS, ERR_ANY)          # sticky errors cleared

    # 1) freeze the D/S line -> the line stops; the receiver flags a link error
    # (errdisc if it goes quiet, errpar if a char is truncated mid-flight) + drop
    await axi_write(dut, ERRINJ, INJ_FREEZE)
    st = await poll_until(dut, STATUS, ERR_ANY)
    assert st & ERR_ANY, f"expected a link error, STATUS={st:#x}"
    await poll_until_clear(dut, STATUS, ST_LINK_RUNNING)
    dut._log.info(f"freeze inject: STATUS={st:#010x} (err {(st>>8)&0xF:#x}), link dropped")
    await recover()

    # 2) invert the looped-back D line -> a link error + link drop
    await axi_write(dut, ERRINJ, INJ_INVERT)
    st = await poll_until(dut, STATUS, ERR_ANY)
    assert st & ERR_ANY, f"expected a link error, STATUS={st:#x}"
    await poll_until_clear(dut, STATUS, ST_LINK_RUNNING)
    dut._log.info(f"invert inject: STATUS={st:#010x} (err bits {(st>>8)&0xF:#x}), link dropped")
    await recover()

    dut._log.info("error injection + recovery verified")


async def poll_timecode(dut, expected, timeout=200000):
    """Poll TIMECODE until a *new* time-code (valid) with the expected value is
    mirrored back. The engine clears the received-valid before each send, so a
    stale value can't satisfy this."""
    val = 0
    for _ in range(timeout):
        val = await axi_read(dut, TIMECODE)
        if (val & TC_VALID) and (val & 0xFF) == expected:
            return val
        await RisingEdge(dut.clk)
    raise TimeoutError(f"time-code {expected:#04x} never looped back (last={val:#010x})")


@cocotb.test()
async def test_timecode(dut):
    """SpaceWire TimeCode loopback: the engine sends a time-code over the link
    and the received one is mirrored back through the TIMECODE register."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Quiet the link (data-mover mode, no self-check N-Chars) but keep it up.
    await axi_write(dut, CTRL, 0x0)
    await poll_until(dut, STATUS, ST_LINK_RUNNING)

    # Distinct values, including control-flag bits [7:6], sent back-to-back to
    # prove the clear-before-send makes the check repeatable.
    for tc in (0x95, 0x2A, 0x3F, 0xC1):
        await axi_write(dut, TIMECODE, tc)
        val = await poll_timecode(dut, tc)
        assert (val & 0xFF) == tc, f"time-code mismatch: got {val:#010x}, sent {tc:#04x}"
    dut._log.info("time-code loopback ok: 0x95, 0x2A, 0x3F, 0xC1 round-tripped")


@cocotb.test()
async def test_eep_roundtrip(dut):
    """An EEP (error end of packet) char round-trips with tuser=1, distinct from
    a normal EOP (tuser=0), through the host data-mover."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await axi_write(dut, CTRL, 0x0)               # data-mover mode
    await poll_until(dut, STATUS, ST_LINK_RUNNING)
    for _ in range(50):
        await RisingEdge(dut.clk)

    async def send_and_pop(term_beat):
        await axi_write(dut, TXDATA, 0x42)        # one data char
        await axi_write(dut, TXDATA, term_beat)   # terminator (EOP or EEP)
        got = []
        for _ in range(20000):
            val = await axi_read(dut, RXDATA)
            if val & BEAT_VALID:
                got.append(val)
                if val & BEAT_TLAST:
                    break
            else:
                await RisingEdge(dut.clk)
        else:
            raise TimeoutError("no end-of-packet received")
        return got

    # EEP: tuser=1, tlast=1
    got = await send_and_pop(BEAT_TUSER | BEAT_TLAST)
    assert (got[0] & 0xFF) == 0x42, f"data char wrong: {got[0]:#010x}"
    assert (got[0] & BEAT_TUSER) == 0, "data char should not be flagged EEP"
    assert got[-1] & BEAT_TLAST, "terminator not marked tlast"
    assert got[-1] & BEAT_TUSER, "EEP terminator should have tuser=1"

    # EOP: tuser=0, tlast=1 (the normal case, to show the bit distinguishes them)
    got = await send_and_pop(BEAT_TLAST)
    assert got[-1] & BEAT_TLAST, "terminator not marked tlast"
    assert (got[-1] & BEAT_TUSER) == 0, "EOP terminator should have tuser=0"
    dut._log.info("EEP/EOP round-trip ok: EEP -> tuser=1, EOP -> tuser=0")


@cocotb.test()
async def test_fault_under_load(dut):
    """Inject a fault while back-to-back PRBS traffic is flowing (link under
    load), confirm it is detected, then confirm the self-check runs cleanly
    again after recovery (no residual desync)."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await axi_write(dut, CTRL, CTRL_SELFTEST_EN | CTRL_SELFTEST_LOOP)
    await poll_until(dut, STATUS, ST_LINK_RUNNING)

    # Sustained load: packets advancing, no errors.
    p0 = await axi_read(dut, PKTCOUNT)
    for _ in range(4000):
        await RisingEdge(dut.clk)
    p1 = await axi_read(dut, PKTCOUNT)
    assert p1 > p0, f"packets not advancing under load ({p0} -> {p1})"
    assert (await axi_read(dut, ERRCOUNT)) == 0, "errors before fault"

    # Corrupt the D line mid-stream -> link error + drop while loaded.
    await axi_write(dut, ERRINJ, INJ_INVERT)
    st = await poll_until(dut, STATUS, ERR_ANY)
    await poll_until_clear(dut, STATUS, ST_LINK_RUNNING)
    dut._log.info(f"fault under load: STATUS={st:#010x}, link dropped mid-stream")

    # Recover AND restart the self-check (start pulse forces a clean TX/RX resync
    # so the PRBS streams realign) -> fresh run from a clean state.
    await axi_write(dut, ERRINJ, 0x0)
    await axi_write(dut, CTRL, CTRL_SELFTEST_EN | CTRL_SELFTEST_LOOP
                    | CTRL_SELFTEST_STRT | CTRL_SOFT_RESET)
    await poll_until(dut, STATUS, ST_LINK_RUNNING)
    await poll_until_clear(dut, STATUS, ERR_ANY)

    # Steady-state after recovery: packets advance and no new errors accumulate.
    for _ in range(2000):
        await RisingEdge(dut.clk)
    pa = await axi_read(dut, PKTCOUNT)
    ea = await axi_read(dut, ERRCOUNT)
    for _ in range(6000):
        await RisingEdge(dut.clk)
    pb = await axi_read(dut, PKTCOUNT)
    eb = await axi_read(dut, ERRCOUNT)
    assert pb > pa, f"packets not advancing after recovery ({pa} -> {pb})"
    assert eb == ea, f"new errors after recovery: {ea} -> {eb}"
    dut._log.info(f"recovered under load: packets {pa}->{pb}, ERRCOUNT steady at {eb}")
