#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""fpgacapZero (fcapz) host verification of the DE25-Nano SpaceWire loopback.

Runs the same checks as the Arty A7-100T example
(examples/arty_a7100t/host_loopback_test.py) over the DE25-Nano's on-board
USB-Blaster III, through Quartus ``quartus_stp`` (fcapz ``usb_blaster``
backend). Like the Arty flow (hw_server programs the bitstream on connect),
each run first programs the board with quartus_pgm, so every check starts
from a freshly configured design; build the .sof first:

    python build.py quartus

Then:

    python examples/de25_nano/host_loopback_test.py              # basic checks
    python examples/de25_nano/host_loopback_test.py --inject     # error injection
    python examples/de25_nano/host_loopback_test.py --timecode   # TimeCodes
    python examples/de25_nano/host_loopback_test.py --eep        # EEP vs EOP
    python examples/de25_nano/host_loopback_test.py --loadfault  # fault under load
    python examples/de25_nano/host_loopback_test.py --stress 60  # PRBS soak

``quartus_stp``/``quartus_pgm`` are looked up on PATH; pass ``--quartus-bin
<dir>`` otherwise. ``--sof`` selects the programming file (default: the Verilog
build; the VHDL one is quartus/de25_nano_vhdl/output/spw_de25_nano_top.sof),
``--no-program`` skips programming, ``--cable`` selects the quartus_pgm cable.
All other options of the Arty script are accepted (``--hardware`` selects the
cable for quartus_stp, default: the first one).
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARTY = ROOT / "examples" / "arty_a7100t"
DEFAULT_SOF = ROOT / "quartus" / "de25_nano_verilog" / "output" / "spw_de25_nano_top.sof"
sys.path.insert(0, str(ARTY))

import host_loopback_test as common  # noqa: E402

# sld_virtual_jtag instance map: see rtl/intel/de25_debug.v
DE25_DEFAULTS = ["--backend", "usb_blaster", "--eio-chain", "3", "--eio-instance", "-1"]


def find_tool(name: str, bin_dir: str | None) -> str:
    if bin_dir:
        for cand in (Path(bin_dir) / name, Path(bin_dir) / f"{name}.exe"):
            if cand.is_file():
                return str(cand)
        raise SystemExit(f"ERROR: {name} not found in --quartus-bin {bin_dir}")
    found = shutil.which(name)
    if not found:
        raise SystemExit(f"ERROR: {name} not found on PATH (add the Quartus bin64 "
                         "directory to PATH or pass --quartus-bin <dir>)")
    return found


def main() -> int:
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--quartus-bin", default=None)
    p.add_argument("--sof", type=Path, default=DEFAULT_SOF)
    p.add_argument("--no-program", action="store_true")
    p.add_argument("--cable", default="1")
    own, rest = p.parse_known_args()
    if "-h" in rest or "--help" in rest:
        print(__doc__)

    if not own.no_program and not ("-h" in rest or "--help" in rest):
        if not own.sof.is_file():
            raise SystemExit(f"ERROR: {own.sof} not found (python build.py quartus)")
        pgm = find_tool("quartus_pgm", own.quartus_bin)
        cmd = [pgm, "-c", own.cable, "-m", "jtag", "-o", f"p;{own.sof}"]
        print(f"programming {own.sof.name} ...", flush=True)
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            print(res.stdout + res.stderr, file=sys.stderr)
            raise SystemExit(f"ERROR: quartus_pgm failed (exit {res.returncode})")

    extra = []
    if "--quartus-stp" not in rest:
        extra = ["--quartus-stp", find_tool("quartus_stp", own.quartus_bin)]
    return common.main(DE25_DEFAULTS + extra + rest)


if __name__ == "__main__":
    raise SystemExit(main())
