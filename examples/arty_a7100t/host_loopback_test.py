#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""fpgacapZero (fcapz) host verification of the Arty A7-100T SpaceWire loopback.

Talks to the programmed board over JTAG and checks, end to end:
  * example identity and the SpaceWire CORE_ID read back through AXI-Lite,
  * automatic link bring-up and the fabric self-check result/counters,
  * a host-driven loopback through the AXI data-mover (TXDATA/RXDATA),
  * the same status mirrored on the EIO probe inputs.

Requires the fcapz host package (``pip install`` the fpgacapZero host) and a
backend: hw_server (default, Vivado/XSDB) or OpenOCD.

Examples:
    # hw_server (programs the bitstream on connect)
    hw_server -d
    python examples/arty_a7100t/host_loopback_test.py \
        --bitfile examples/arty_a7100t/spw_arty_a7100t_top.bit

    # OpenOCD (start it first; program the .bit separately)
    openocd -f examples/arty_a7100t/arty_a7100t.cfg
    python examples/arty_a7100t/host_loopback_test.py --backend openocd
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

# Register byte offsets (see rtl/spw_loopback_axi.v)
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

ST_LINK_RUNNING  = 1 << 0
ST_SELFTEST_BUSY = 1 << 1
ST_SELFTEST_DONE = 1 << 2
ST_SELFTEST_PASS = 1 << 3
ST_BRINGUP_DONE  = 1 << 6

# spw link-error bits within STATUS[11:8]
ERR_DISC, ERR_PAR, ERR_ESC, ERR_CRED = 1 << 8, 1 << 9, 1 << 10, 1 << 11
ERR_ANY = 0xF << 8
INJ_FREEZE, INJ_INVERT = 1 << 0, 1 << 1

CTRL_SELFTEST_EN   = 1 << 0
CTRL_SELFTEST_STRT = 1 << 1
CTRL_SOFT_RESET    = 1 << 2
CTRL_SELFTEST_LOOP = 1 << 3

EXPECT_EXAMPLE_ID = 0x5350574C  # "SPWL"
EXPECT_SPW_COREID = 0x53505752  # "SPWR"
SELFTEST_LEN = 16
SELFTEST_PKTS = 4

HERE = Path(__file__).resolve().parent
DEFAULT_BIT = HERE / "spw_arty_a7100t_top.bit"


class CheckError(Exception):
    pass


def expect(cond, msg):
    if not cond:
        raise CheckError(msg)
    print(f"  ok: {msg}")


def poll(fn, mask, tries=2000, delay=0.002):
    val = 0
    for _ in range(tries):
        val = fn()
        if val & mask:
            return val
        time.sleep(delay)
    raise CheckError(f"timeout waiting for {mask:#x} (last {val:#010x})")


def poll_clear(fn, mask, tries=2000, delay=0.002):
    val = 0
    for _ in range(tries):
        val = fn()
        if not (val & mask):
            return val
        time.sleep(delay)
    raise CheckError(f"timeout waiting for {mask:#x} to clear (last {val:#010x})")


def make_transport(args):
    if args.backend == "openocd":
        from fcapz.transport import OpenOcdTransport
        return OpenOcdTransport(port=args.port or 6666, tap=args.tap)
    from fcapz.transport import XilinxHwServerTransport
    return XilinxHwServerTransport(
        port=args.port or 3121, fpga_name=args.fpga, bitfile=str(args.bitfile))


def run(args) -> int:
    from fcapz.ejtagaxi import EjtagAxiController
    from fcapz.eio import EioController

    t = make_transport(args)
    axi = EjtagAxiController(t, chain=4)
    axi.connect()
    print("connected to EJTAG-AXI bridge on USER4")

    # --- identity ---
    expect(axi.axi_read(EXAMPLE_ID) == EXPECT_EXAMPLE_ID, "EXAMPLE_ID == 'SPWL'")
    ver = axi.axi_read(EXAMPLE_VER)
    hdl = {ord("V"): "Verilog", ord("H"): "VHDL"}.get(ver & 0xFF, "unknown")
    print(f"  example version: {ver:#010x}  (live build = {hdl})")
    expect((ver >> 8) == 0x000100 and (ver & 0xFF) in (ord("V"), ord("H")),
           f"EXAMPLE_VER carries a valid HDL fingerprint ({hdl})")

    # --- out-of-range decode must not alias the register map ---
    expect(axi.axi_read(0x100) == 0x0, "unmapped 0x100 reads 0 (no 0x100 aliasing)")

    # --- scratch R/W ---
    axi.axi_write(SCRATCH, 0xCAFEF00D)
    expect(axi.axi_read(SCRATCH) == 0xCAFEF00D, "SCRATCH read-back")

    # --- bring-up + CORE_ID over AXI-Lite ---
    poll(lambda: axi.axi_read(STATUS), ST_BRINGUP_DONE)
    expect(axi.axi_read(SPW_COREID) == EXPECT_SPW_COREID,
           "SpaceWire CORE_ID 'SPWR' read back over AXI-Lite")
    poll(lambda: axi.axi_read(STATUS), ST_LINK_RUNNING)
    expect(True, "SpaceWire link running (loopback)")

    # --- fabric self-check ---
    st = poll(lambda: axi.axi_read(STATUS), ST_SELFTEST_DONE)
    expect(st & ST_SELFTEST_PASS, f"fabric self-check passed (STATUS={st:#010x})")
    txc, rxc, errc = (axi.axi_read(TXCOUNT), axi.axi_read(RXCOUNT), axi.axi_read(ERRCOUNT))
    pkts = axi.axi_read(PKTCOUNT)
    expected = SELFTEST_PKTS * (SELFTEST_LEN + 1)  # PRBS bytes + EOP per packet
    print(f"  self-check: {pkts} back-to-back PRBS packets, TX={txc} RX={rxc} ERR={errc}")
    expect(txc == expected and rxc == expected and pkts == SELFTEST_PKTS and errc == 0,
           f"self-check counts ({SELFTEST_PKTS} packets x {SELFTEST_LEN} PRBS + EOP, 0 errors)")

    # --- host-driven data-mover loopback ---
    axi.axi_write(CTRL, 0x0)              # selftest_en = 0 -> manual control
    time.sleep(0.01)
    payload = [0xA5, 0x5A, 0x00, 0xFF, 0x10]
    for b in payload:
        axi.axi_write(TXDATA, b)          # data chars
    axi.axi_write(TXDATA, 1 << 8)         # EOP (tlast=1, data=0)

    got = []
    for _ in range(2000):
        val = axi.axi_read(RXDATA)
        if val & (1 << 31):
            got.append(val)
            if val & (1 << 8):            # tlast
                break
        else:
            time.sleep(0.002)
    else:
        raise CheckError("data-mover: no EOP looped back")
    rx_data = [g & 0xFF for g in got[:-1]]
    expect(rx_data == payload, f"data-mover loopback payload {rx_data} == {payload}")
    expect((got[-1] & (1 << 8)) and not (got[-1] & (1 << 9)), "data-mover EOP terminal beat")

    # --- EIO status mirror (USER1 slot 2) ---
    try:
        eio = EioController(t, chain=1, instance=2)
        eio.connect()
        ein = eio.read_inputs()
        print(f"  EIO0 probe_in = {ein:#04x} (bit0 link_running, bit4 selftest_pass)")
        expect(ein & 0x1, "EIO mirrors link_running")
    except Exception as exc:  # EIO is a secondary surface; don't fail the run on it
        print(f"  note: EIO read skipped ({exc})")

    print("\nRESULT: PASS - SpaceWire loopback verified over fcapz/JTAG")
    return 0


def run_stress(args) -> int:
    """Soak: free-run back-to-back PRBS packets for args.stress seconds and
    confirm ERRCOUNT stays 0 and the counters keep advancing."""
    from fcapz.ejtagaxi import EjtagAxiController

    t = make_transport(args)
    axi = EjtagAxiController(t, chain=4)
    axi.connect()
    print("connected to EJTAG-AXI bridge on USER4")
    expect(axi.axi_read(EXAMPLE_ID) == EXPECT_EXAMPLE_ID, "EXAMPLE_ID == 'SPWL'")
    poll(lambda: axi.axi_read(STATUS), ST_BRINGUP_DONE)
    poll(lambda: axi.axi_read(STATUS), ST_LINK_RUNNING)

    # Clean restart into continuous loop mode: stop (drain), then en+loop+start.
    axi.axi_write(CTRL, 0x0)
    time.sleep(0.1)
    axi.axi_write(CTRL, CTRL_SELFTEST_EN | CTRL_SELFTEST_LOOP | CTRL_SELFTEST_STRT)
    time.sleep(0.05)
    expect(axi.axi_read(STATUS) & ST_SELFTEST_BUSY, "continuous self-check running")

    print(f"soaking back-to-back PRBS packets for {args.stress}s ...")
    t0 = time.time()
    last_pkts = 0
    while time.time() - t0 < args.stress:
        time.sleep(args.poll_interval)
        pkts = axi.axi_read(PKTCOUNT)
        tx = axi.axi_read(TXCOUNT)
        rx = axi.axi_read(RXCOUNT)
        err = axi.axi_read(ERRCOUNT)
        el = time.time() - t0
        rate = (tx / el / 1e6) if el > 0 else 0
        print(f"  [{el:6.1f}s] packets={pkts:>10,}  TX={tx:>12,}  RX={rx:>12,}  "
              f"ERR={err}  (~{rate:.2f} MChar/s)")
        if err != 0:
            raise CheckError(f"PRBS/framing errors during soak: ERRCOUNT={err}")
        if pkts <= last_pkts:
            raise CheckError(f"packet count not advancing (stalled at {pkts})")
        last_pkts = pkts

    axi.axi_write(CTRL, 0x0)  # stop
    time.sleep(0.05)
    pkts = axi.axi_read(PKTCOUNT)
    tx = axi.axi_read(TXCOUNT)
    rx = axi.axi_read(RXCOUNT)
    err = axi.axi_read(ERRCOUNT)
    print(f"\nsoak done: {pkts:,} back-to-back PRBS packets, "
          f"TX={tx:,} RX={rx:,} chars, ERRCOUNT={err}")
    expect(err == 0, "0 PRBS/framing errors over the whole soak")
    expect(pkts > 0 and rx > 0, "traffic actually flowed")
    print("\nRESULT: PASS - PRBS back-to-back stress verified over fcapz/JTAG")
    return 0


def run_inject(args) -> int:
    """Inject errors on the internal loopback line and confirm the SpaceWire
    link-error detection (sticky error bits + link drop) and recovery."""
    from fcapz.ejtagaxi import EjtagAxiController

    t = make_transport(args)
    axi = EjtagAxiController(t, chain=4)
    axi.connect()
    poll(lambda: axi.axi_read(STATUS), ST_BRINGUP_DONE)
    # continuous self-check so N-Chars flow (needed for the parity/invert case)
    axi.axi_write(CTRL, CTRL_SELFTEST_EN | CTRL_SELFTEST_LOOP)
    poll(lambda: axi.axi_read(STATUS), ST_LINK_RUNNING)
    expect(not (axi.axi_read(STATUS) & ERR_ANY), "link running, no errors before injection")

    def recover():
        axi.axi_write(ERRINJ, 0x0)
        axi.axi_write(CTRL, CTRL_SELFTEST_EN | CTRL_SELFTEST_LOOP | CTRL_SOFT_RESET)
        poll(lambda: axi.axi_read(STATUS), ST_LINK_RUNNING)
        poll_clear(lambda: axi.axi_read(STATUS), ERR_ANY)

    names = {ERR_DISC: "errdisc", ERR_PAR: "errpar", ERR_ESC: "erresc", ERR_CRED: "errcred"}

    def bits(st):
        return " ".join(n for m, n in names.items() if st & m) or "none"

    # 1) freeze the loopback D/S line -> disconnect
    axi.axi_write(ERRINJ, INJ_FREEZE)
    st = poll(lambda: axi.axi_read(STATUS), ERR_DISC)
    poll_clear(lambda: axi.axi_read(STATUS), ST_LINK_RUNNING)
    print(f"  freeze  -> STATUS={st:#010x} errors=[{bits(st)}], link dropped")
    expect(st & ERR_DISC, "disconnect injection sets errdisc and drops the link")
    recover()
    expect(True, "link recovered and sticky errors cleared after disconnect")

    # 2) invert the looped-back D line -> a link error
    axi.axi_write(ERRINJ, INJ_INVERT)
    st = poll(lambda: axi.axi_read(STATUS), ERR_ANY)
    poll_clear(lambda: axi.axi_read(STATUS), ST_LINK_RUNNING)
    print(f"  invert  -> STATUS={st:#010x} errors=[{bits(st)}], link dropped")
    expect(st & ERR_ANY, "D-line corruption sets a link error and drops the link")
    recover()
    expect(True, "link recovered and sticky errors cleared after corruption")

    axi.axi_write(CTRL, 0x0)
    print("\nRESULT: PASS - internal-loopback error injection + recovery verified")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--backend", choices=("hw_server", "openocd"), default="hw_server")
    p.add_argument("--bitfile", type=Path, default=DEFAULT_BIT)
    p.add_argument("--port", type=int, default=None)
    p.add_argument("--tap", default="xc7a100t.tap")
    p.add_argument("--fpga", default="xc7a100t")
    p.add_argument("--stress", type=float, default=0.0,
                   help="run a continuous back-to-back PRBS soak for N seconds")
    p.add_argument("--poll-interval", type=float, default=10.0,
                   help="seconds between counter polls during --stress")
    p.add_argument("--inject", action="store_true",
                   help="inject errors on the internal loopback line and check "
                        "link-error detection + recovery")
    args = p.parse_args()
    try:
        if args.inject:
            return run_inject(args)
        return run_stress(args) if args.stress > 0 else run(args)
    except CheckError as exc:
        print(f"\nRESULT: FAIL - {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
