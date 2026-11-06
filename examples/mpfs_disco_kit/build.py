#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""Build (and optionally program) the PolarFire SoC Discovery Kit example.

Runs a Libero SoC batch flow for the Microchip PolarFire SoC Discovery Kit
(MPFS-DISCO-KIT, MPFS095T-1FCSG325E). The project and every generated file go
to ``libero/mpfs_disco_kit_<hdl>/`` at the repository root, and the
programming data stays in that project (``--program-only`` programs from it).

Libero is looked up on PATH (``libero``); pass ``--libero-bin`` to point at
Libero's ``Designer/bin`` directory instead. Synthesis needs the Synplify
licence: when Synplify reports ``synplifypro_actel`` as unavailable, point it
at your licence server, for example ``SNPSLMD_LICENSE_FILE=1702@localhost``.

Programming (``--program``) uses the first FlashPro Libero finds, normally the
board's embedded FlashPro5. Nothing else (an fcapz host, OpenOCD) may hold its
JTAG channel at that moment.

Usage:
    python examples/mpfs_disco_kit/build.py                   # Verilog, full flow
    python examples/mpfs_disco_kit/build.py --hdl vhdl
    python examples/mpfs_disco_kit/build.py --flow synth      # synthesis only
    python examples/mpfs_disco_kit/build.py --program         # build + program
    python examples/mpfs_disco_kit/build.py --program-only    # program the last build
    python examples/mpfs_disco_kit/build.py --dry-run         # check tools/files only
"""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
TCL = HERE / "build_mpfs.tcl"
PROGRAM_TCL = HERE / "program_mpfs.tcl"
# fpgacapZero (JTAG debug cores) is the submodule shared with the Arty example.
FCAPZ_RTL = ROOT / "examples" / "arty_a7100t" / "fpgacapZero" / "rtl"
PROJECT = "spw_mpfs_disco_kit_top"
LIBERO = "libero.exe" if sys.platform == "win32" else "libero"


def find_libero(bin_dir: str | None) -> str:
    if bin_dir:
        candidate = Path(bin_dir) / LIBERO
        if candidate.is_file():
            return str(candidate)
        raise SystemExit(f"ERROR: {LIBERO} not found in --libero-bin {bin_dir}")
    found = shutil.which(LIBERO)
    if not found:
        raise SystemExit(
            f"ERROR: {LIBERO} not found on PATH. Add Libero SoC's Designer/bin "
            "directory to PATH or pass --libero-bin <dir>."
        )
    return found


def rel(path: Path) -> str:
    """Path relative to the repository root (Libero runs there), with / separators."""
    return path.relative_to(ROOT).as_posix()


def run_libero(libero: str, script: Path, script_args: list[str], log: Path) -> int:
    log.parent.mkdir(parents=True, exist_ok=True)
    # Libero splits SCRIPT_ARGS on spaces, so only repository-relative paths go
    # into it (the Tcl makes them absolute); the checkout path may contain spaces.
    bad = [a for a in script_args if not a or any(c.isspace() for c in a)]
    if bad:
        raise SystemExit(f"ERROR: Libero script arguments may not contain spaces: {bad}")
    cmd = [libero, f"SCRIPT:{rel(script)}",
           "SCRIPT_ARGS:" + " ".join(script_args), f"LOGFILE:{rel(log)}"]
    print(f"[build] {' '.join(cmd)}", flush=True)
    rc = subprocess.run(cmd, cwd=ROOT, check=False).returncode
    if rc != 0:
        print(f"[build] Libero failed (exit {rc}); see {log}", file=sys.stderr)
        text = log.read_text(errors="replace") if log.is_file() else ""
        synplify = log.parent / "synthesis" / "synplify.log"
        if synplify.is_file():
            text += synplify.read_text(errors="replace")
        if "synplifypro_actel is not available" in text:
            print("[build] Synplify could not check out its licence: set "
                  "SNPSLMD_LICENSE_FILE to your licence server (e.g. 1702@localhost)",
                  file=sys.stderr)
    return rc


def timing_summary(report: Path) -> list[list[str]]:
    """Rows of a SmartTime XML report's Summary table (clock, period, MHz, slack, corner)."""
    root = ET.parse(report).getroot()
    for section in root.iter("section"):
        if section.findtext("name") == "Summary":
            table = section.find("table")
            return [[(c.text or "").strip() for c in row] for row in table.findall("row")]
    return []


def summary(outdir: Path) -> None:
    """Print resource usage and timing from the Libero reports."""
    designer = outdir / "designer" / PROJECT
    resources = designer / f"{PROJECT}_compile_netlist_resources.rpt"
    if resources.is_file():
        keep = re.compile(r"^\|\s*(4LUT|DFF|User I/O|uSRAM|LSRAM|Math|H-Chip Global|"
                          r"PLL|UJTAG|INIT)\s*\|")
        print("[build] --- resource usage ---")
        for line in resources.read_text(errors="replace").splitlines():
            if keep.match(line):
                print(f"[build]   {line.strip()}")
    for kind, label in (("max", "setup"), ("min", "hold")):
        report = designer / f"{PROJECT}_{kind}_timing_multi_corner.xml"
        if not report.is_file():
            continue
        print(f"[build] --- timing, {label} (worst of all corners) ---")
        for row in timing_summary(report):
            if len(row) >= 5 and row[3]:
                print(f"[build]   {row[0]:<6} {row[1]:>8} ns  worst {label} slack "
                      f"{row[3]} ns ({row[4]})")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--hdl", choices=("verilog", "vhdl"), default="verilog")
    parser.add_argument("--flow", choices=("full", "synth"), default="full",
                        help="full = through programming data (default); synth = synthesis only")
    parser.add_argument("--libero-bin", default=None,
                        help="Libero SoC Designer/bin directory (default: libero on PATH)")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--program", action="store_true",
                       help="after a full build, program the board (embedded FlashPro5)")
    group.add_argument("--program-only", action="store_true",
                       help="program the board from the last full build, without rebuilding")
    parser.add_argument("--dry-run", action="store_true",
                        help="check tools and sources, do not build")
    args = parser.parse_args()

    if args.program and args.flow != "full":
        raise SystemExit("ERROR: --program needs --flow full")

    libero = find_libero(args.libero_bin)
    outdir_rel = Path("libero") / f"mpfs_disco_kit_{args.hdl}"
    outdir = ROOT / outdir_rel

    if args.dry_run:
        rtl = HERE / "rtl"
        missing = [str(p) for p in (TCL, PROGRAM_TCL, HERE / "mpfs_disco_kit.sdc",
                                    HERE / "mpfs_disco_kit_io.pdc",
                                    rtl / f"{PROJECT}.v", rtl / f"{PROJECT}.vhd",
                                    rtl / "microchip" / "mpfs_por.v",
                                    rtl / "microchip" / "mpfs_debug.v",
                                    FCAPZ_RTL / "jtag_tap" / "jtag_tap_polarfire.v",
                                    FCAPZ_RTL / "fcapz_debug_multi.v")
                   if not p.is_file()]
        if not (FCAPZ_RTL / "fcapz_debug_multi.v").is_file():
            missing.append("(fpgacapZero submodule: git submodule update --init "
                           "examples/arty_a7100t/fpgacapZero)")
        if missing:
            raise SystemExit("ERROR: missing sources:\n  " + "\n  ".join(missing))
        print(f"[build] dry run ok: {libero}; would build {args.hdl} ({args.flow}) "
              f"into {outdir_rel.as_posix()}")
        return 0

    if args.program_only:
        if not (outdir / f"{PROJECT}.prjx").is_file():
            raise SystemExit(f"ERROR: no project in {outdir_rel.as_posix()}; build it first")
        rc = run_libero(libero, PROGRAM_TCL, [outdir_rel.as_posix()],
                        ROOT / "libero" / f"program_{args.hdl}.log")
        if rc == 0:
            print("[build] board programmed: LED1-LED4 all lit = self-check passed")
        return rc

    # The Tcl deletes and recreates the project, so no stale report survives.
    rc = run_libero(libero, TCL,
                    [".", args.hdl, args.flow, outdir_rel.as_posix(),
                     "1" if args.program else "0"],
                    ROOT / "libero" / f"build_{args.hdl}.log")
    if rc != 0:
        return rc
    summary(outdir)
    if args.flow == "synth":
        print("[build] synthesis ok")
        return 0
    print(f"[build] success: {outdir_rel.as_posix()}")
    if args.program:
        print("[build] board programmed: LED1-LED4 all lit = self-check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
