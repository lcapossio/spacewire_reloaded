#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""Launch a Vivado batch build of the Arty A7-100T SpaceWire loopback example.

Builds the all-Verilog or the mixed-language VHDL variant. The fpgacapZero
debug-core RTL is taken from the git submodule at
``examples/arty_a7100t/fpgacapZero``; run ``git submodule update --init`` first
on a fresh checkout.

Usage:
    python examples/arty_a7100t/build.py                 # Verilog (default)
    python examples/arty_a7100t/build.py --hdl vhdl
    python examples/arty_a7100t/build.py --vivado /path/to/vivado
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SUBMODULE = HERE / "fpgacapZero"
TCL = {"verilog": HERE / "build_arty.tcl", "vhdl": HERE / "build_arty_vhdl.tcl"}
BITFILE = {
    "verilog": HERE / "spw_arty_a7100t_top.bit",
    "vhdl": HERE / "spw_arty_a7100t_top_vhdl.bit",
}


def find_vivado(explicit: str | None) -> str:
    if explicit:
        return explicit
    found = shutil.which("vivado")
    if not found:
        raise SystemExit(
            "ERROR: vivado not on PATH; pass --vivado or source Vivado settings"
        )
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--hdl", choices=("verilog", "vhdl"), default="verilog")
    parser.add_argument("--vivado", default=None, help="path to vivado executable")
    parser.add_argument("--log-dir", default=str(HERE / "vivado_logs"))
    args = parser.parse_args()

    if not (SUBMODULE / "rtl").is_dir():
        raise SystemExit(
            f"ERROR: fpgacapZero submodule missing at {SUBMODULE}.\n"
            "Run: git submodule update --init examples/arty_a7100t/fpgacapZero"
        )

    vivado = find_vivado(args.vivado)
    log_dir = Path(args.log_dir)
    log_dir.mkdir(parents=True, exist_ok=True)
    tcl = TCL[args.hdl]
    bit = BITFILE[args.hdl]

    cmd = [
        vivado, "-mode", "batch", "-source", str(tcl),
        "-log", str(log_dir / f"vivado_{args.hdl}.log"),
        "-journal", str(log_dir / f"vivado_{args.hdl}.jou"),
    ]
    print(f"[build] vivado: {vivado}")
    print(f"[build] hdl:    {args.hdl}")
    print(f"[build] cmd:    {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=str(ROOT), check=False)
    if result.returncode != 0:
        print(f"[build] vivado failed (exit {result.returncode})", file=sys.stderr)
        return result.returncode
    if not bit.is_file():
        print(f"[build] reported success but bitstream missing: {bit}", file=sys.stderr)
        return 4
    print(f"[build] success: {bit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
