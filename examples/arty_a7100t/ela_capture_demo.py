#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""Demonstrate an fpgacapZero ELA capture of the live SpaceWire link.

ELA0 (USER1, instance 0) samples, in the system clock domain, the byte
    {spw_do, spw_so, spw_di, spw_si, bringup_done, link_running,
     selftest_done, selftest_pass}
i.e. the SpaceWire Data/Strobe pins plus the example status. This script brings
the link up, starts the continuous self-check so the D/S lines are toggling, then
arms ELA0 and captures a window, renders the four D/S signals as an ASCII
waveform, checks that they actually transition (real SpaceWire activity) and that
the internal loopback holds (spw_do==spw_di, spw_so==spw_si), and writes a VCD.

Use the generic build (10 Mbit/s) for a clear waveform: at 100 MHz sampling each
SpaceWire bit is ~10 samples wide.

    hw_server -d
    python examples/arty_a7100t/ela_capture_demo.py \
        --bitfile examples/arty_a7100t/spw_arty_a7100t_top.bit
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

CTRL    = 0x0C
STATUS  = 0x10
ST_LINK_RUNNING = 1 << 0
CTRL_EN, CTRL_START, CTRL_LOOP = 1 << 0, 1 << 1, 1 << 3

# ELA0 probe bit positions (see spw_arty_a7100t_top: ela0_probe concat).
PROBES = [  # (name, lsb)
    ("selftest_pass", 0), ("selftest_done", 1), ("link_running", 2),
    ("bringup", 3), ("spw_si", 4), ("spw_di", 5), ("spw_so", 6), ("spw_do", 7),
]
HERE = Path(__file__).resolve().parent


def make_transport(args):
    if args.backend == "openocd":
        from fcapz.transport import OpenOcdTransport
        return OpenOcdTransport(port=args.port or 6666, tap=args.tap)
    from fcapz.transport import XilinxHwServerTransport
    return XilinxHwServerTransport(port=args.port or 3121, fpga_name=args.fpga,
                                   bitfile=str(args.bitfile))


def ascii_wave(samples, lsb, n):
    # ASCII digital waveform: '#' high rail, '_' low rail.
    return "".join("#" if (v >> lsb) & 1 else "_" for v in samples[:n])


def transitions(samples, lsb):
    t = 0
    for a, b in zip(samples, samples[1:]):
        if ((a >> lsb) & 1) != ((b >> lsb) & 1):
            t += 1
    return t


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--backend", choices=("hw_server", "openocd"), default="hw_server")
    p.add_argument("--bitfile", type=Path, default=HERE / "spw_arty_a7100t_top.bit")
    p.add_argument("--port", type=int, default=None)
    p.add_argument("--tap", default="xc7a100t.tap")
    p.add_argument("--fpga", default="xc7a100t")
    p.add_argument("--depth", type=int, default=1024)  # must match built ELA DEPTH
    p.add_argument("--wave-cols", type=int, default=120)
    p.add_argument("--vcd", type=Path, default=HERE / "ela_capture.vcd")
    args = p.parse_args()

    from fcapz.ejtagaxi import EjtagAxiController
    from fcapz.analyzer import Analyzer, CaptureConfig, TriggerConfig, ProbeSpec

    t = make_transport(args)
    axi = EjtagAxiController(t, chain=4)
    axi.connect()
    # Bring up + start continuous self-check so the D/S lines are always active.
    for _ in range(2000):
        if axi.axi_read(STATUS) & ST_LINK_RUNNING:
            break
        time.sleep(0.002)
    else:
        print("FAIL: link did not come up", file=sys.stderr)
        return 1
    axi.axi_write(CTRL, 0x0)
    time.sleep(0.05)
    axi.axi_write(CTRL, CTRL_EN | CTRL_LOOP | CTRL_START)
    time.sleep(0.05)
    print("link up, continuous self-check running; capturing ELA0 ...")

    ela = Analyzer(t, instance=0)
    ela.connect()
    # ELA built with DEPTH=1024 and NUM_SEGMENTS=4 -> 256 samples per segment;
    # the capture window (pre+post+1) must fit one segment.
    seg = args.depth // 4
    cfg = CaptureConfig(
        pretrigger=8,
        posttrigger=seg - 8 - 1,
        trigger=TriggerConfig(mode="value_match", value=0, mask=0),  # trigger now
        sample_width=8,
        depth=args.depth,
        probes=[ProbeSpec(name=n, width=1, lsb=b) for n, b in PROBES],
    )
    ela.configure(cfg)
    ela.reset()
    ela.arm()
    result = ela.capture(timeout=5.0)
    n = len(result.samples)
    print(f"captured {n} samples (overflow={result.overflow})\n")

    cols = min(args.wave_cols, n)
    for name in ("spw_do", "spw_so", "spw_di", "spw_si"):
        lsb = dict(PROBES)[name]
        print(f"  {name:>7}: |{ascii_wave(result.samples, lsb, cols)}|")
    print()

    tr = {n_: transitions(result.samples, b_) for n_, b_ in PROBES}
    print(f"  transitions over {n} samples: "
          f"do={tr['spw_do']} so={tr['spw_so']} di={tr['spw_di']} si={tr['spw_si']}")

    # checks: D/S actually toggled, and internal loopback holds at every sample.
    ok = True
    if tr["spw_do"] < 4 or tr["spw_so"] < 4:
        print("FAIL: SpaceWire D/S did not toggle (no link activity captured)", file=sys.stderr)
        ok = False
    do_eq_di = all(((v >> 7) & 1) == ((v >> 5) & 1) for v in result.samples)
    so_eq_si = all(((v >> 6) & 1) == ((v >> 4) & 1) for v in result.samples)
    if not (do_eq_di and so_eq_si):
        print(f"FAIL: internal loopback mismatch (do==di:{do_eq_di} so==si:{so_eq_si})",
              file=sys.stderr)
        ok = False
    else:
        print("  internal loopback holds: spw_do==spw_di and spw_so==spw_si in all samples")

    try:
        args.vcd.write_text(ela.export_vcd_text(result))
        print(f"  wrote waveform: {args.vcd}")
    except Exception as exc:
        print(f"  note: VCD export skipped ({exc})")

    axi.axi_write(CTRL, 0x0)  # stop self-check
    print("\nRESULT: %s - ELA captured live SpaceWire D/S activity" %
          ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
