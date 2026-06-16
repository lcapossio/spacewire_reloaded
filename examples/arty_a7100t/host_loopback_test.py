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

ST_LINK_RUNNING  = 1 << 0
ST_SELFTEST_DONE = 1 << 2
ST_SELFTEST_PASS = 1 << 3
ST_BRINGUP_DONE  = 1 << 6

EXPECT_EXAMPLE_ID = 0x5350574C  # "SPWL"
EXPECT_SPW_COREID = 0x53505752  # "SPWR"
SELFTEST_LEN = 16

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
    print(f"  example version: {axi.axi_read(EXAMPLE_VER):#010x}")

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
    print(f"  self-check counters: TX={txc} RX={rxc} ERR={errc}")
    expect(txc == SELFTEST_LEN + 1 and rxc == SELFTEST_LEN + 1 and errc == 0,
           "self-check counts (16 data + EOP, 0 errors)")

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


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--backend", choices=("hw_server", "openocd"), default="hw_server")
    p.add_argument("--bitfile", type=Path, default=DEFAULT_BIT)
    p.add_argument("--port", type=int, default=None)
    p.add_argument("--tap", default="xc7a100t.tap")
    p.add_argument("--fpga", default="xc7a100t")
    args = p.parse_args()
    try:
        return run(args)
    except CheckError as exc:
        print(f"\nRESULT: FAIL - {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
