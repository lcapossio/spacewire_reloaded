#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""Build (and optionally program) the DE25-Nano SpaceWire loopback example.

Runs a Quartus Prime Pro batch compile for the Terasic DE25-Nano (Agilex 5
E-series, A5EB013BB23BE4SR1). The project and every generated file go to
``quartus/de25_nano_<hdl>/`` at the repository root; the programming file is
``quartus/de25_nano_<hdl>/output/spw_de25_nano_top.sof``.

Quartus tools are looked up on PATH (``quartus_sh``, and ``quartus_pgm`` for
``--program``); pass ``--quartus-bin`` to point at a Quartus ``bin64``
directory instead.

Usage:
    python examples/de25_nano/build.py                   # Verilog, full compile
    python examples/de25_nano/build.py --hdl vhdl
    python examples/de25_nano/build.py --flow synth      # synthesis only
    python examples/de25_nano/build.py --program         # compile + program over JTAG
    python examples/de25_nano/build.py --dry-run         # check tools/files only
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
TCL = HERE / "build_de25.tcl"
# fpgacapZero (JTAG debug cores) is the submodule shared with the Arty example.
FCAPZ_RTL = ROOT / "examples" / "arty_a7100t" / "fpgacapZero" / "rtl"
DEVICE = "A5EB013BB23BE4SR1"
PROJECT = "spw_de25_nano_top"


def find_tool(name: str, bin_dir: str | None) -> str:
    if bin_dir:
        for candidate in (Path(bin_dir) / name, Path(bin_dir) / f"{name}.exe"):
            if candidate.is_file():
                return str(candidate)
        raise SystemExit(f"ERROR: {name} not found in --quartus-bin {bin_dir}")
    found = shutil.which(name)
    if not found:
        raise SystemExit(
            f"ERROR: {name} not found on PATH. Add the Quartus Prime Pro bin64 "
            "directory to PATH or pass --quartus-bin <dir>."
        )
    return found


def default_jobs() -> int:
    return max(1, (os.cpu_count() or 2) // 2)


def summary(outdir: Path) -> None:
    """Print utilization and timing from the Quartus summary files."""
    fit = outdir / "output" / f"{PROJECT}.fit.summary"
    sta = outdir / "output" / f"{PROJECT}.sta.summary"
    if fit.is_file():
        keep = ("Device", "Logic utilization", "Total dedicated logic registers",
                "Total pins", "Total block memory bits", "Total RAM Blocks",
                "Total DSP Blocks", "Total PLLs")
        print("[build] --- utilization ---")
        for line in fit.read_text(errors="replace").splitlines():
            if line.startswith(keep):
                print(f"[build]   {line.strip()}")
    if sta.is_file():
        print("[build] --- timing (worst case) ---")
        text = sta.read_text(errors="replace")
        for kind, slack in re.findall(r"Type\s*:\s*(.+?)\nSlack\s*:\s*(-?[\d.]+)", text):
            print(f"[build]   {kind.strip():<32} slack {slack} ns")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--hdl", choices=("verilog", "vhdl"), default="verilog")
    parser.add_argument("--flow", choices=("full", "synth"), default="full",
                        help="full = compile to .sof (default); synth = synthesis only")
    parser.add_argument("--device", default=DEVICE, help=f"Agilex 5 OPN (default {DEVICE})")
    parser.add_argument("--jobs", type=int, default=default_jobs(),
                        help="max Quartus parallel processors (default: half the cores)")
    parser.add_argument("--quartus-bin", default=None,
                        help="Quartus bin64 directory (default: tools on PATH)")
    parser.add_argument("--program", action="store_true",
                        help="after a full compile, program the board over JTAG (quartus_pgm)")
    parser.add_argument("--cable", default="1", help="quartus_pgm cable (default: 1)")
    parser.add_argument("--dry-run", action="store_true",
                        help="check tools and sources, do not build")
    args = parser.parse_args()

    if args.program and args.flow != "full":
        raise SystemExit("ERROR: --program needs --flow full")

    quartus_sh = find_tool("quartus_sh", args.quartus_bin)
    quartus_pgm = find_tool("quartus_pgm", args.quartus_bin) if args.program else None
    outdir_rel = Path("quartus") / f"de25_nano_{args.hdl}"
    outdir = ROOT / outdir_rel
    sof = outdir / "output" / f"{PROJECT}.sof"

    if args.dry_run:
        missing = [str(p) for p in (TCL, HERE / "de25_nano.sdc", HERE / "de25_nano_pins.tcl",
                                    HERE / "rtl" / "intel" / "de25_reset_release.v",
                                    HERE / "rtl" / "intel" / "de25_reset_release_ip.ip",
                                    HERE / "rtl" / "intel" / "de25_debug.v",
                                    FCAPZ_RTL / "fcapz_ela_intel.v")
                   if not p.is_file()]
        if not (FCAPZ_RTL / "fcapz_ela_intel.v").is_file():
            missing.append("(fpgacapZero submodule: git submodule update --init "
                           "examples/arty_a7100t/fpgacapZero)")
        if missing:
            raise SystemExit("ERROR: missing sources:\n  " + "\n  ".join(missing))
        print(f"[build] dry run ok: {quartus_sh}; would build {args.hdl} ({args.flow}) "
              f"for {args.device} into {outdir_rel}")
        return 0

    # A stale .sof or report summary must not masquerade as the result of this
    # run (a synth-only run does not rewrite the fit/sta summaries).
    for stale in [sof] + [outdir / "output" / f"{PROJECT}.{kind}.summary"
                          for kind in ("syn", "fit", "sta")]:
        if stale.exists():
            stale.unlink()

    cmd = [quartus_sh, "-t", str(TCL), args.hdl, args.device, args.flow,
           outdir_rel.as_posix(), str(args.jobs)]
    print(f"[build] {' '.join(cmd)}", flush=True)
    result = subprocess.run(cmd, cwd=ROOT, check=False)
    if result.returncode != 0:
        print(f"[build] Quartus failed (exit {result.returncode})", file=sys.stderr)
        return result.returncode

    summary(outdir)
    if args.flow == "synth":
        print("[build] synthesis ok")
        return 0
    if not sof.is_file():
        print(f"[build] compile reported success but {sof} is missing", file=sys.stderr)
        return 4
    print(f"[build] success: {sof}")

    if quartus_pgm:
        pgm = [quartus_pgm, "-c", args.cable, "-m", "jtag", "-o", f"p;{sof}"]
        print(f"[build] {' '.join(pgm)}", flush=True)
        result = subprocess.run(pgm, cwd=ROOT, check=False)
        if result.returncode != 0:
            print(f"[build] programming failed (exit {result.returncode})", file=sys.stderr)
            return result.returncode
        print("[build] board programmed: LEDR0-3 all lit = self-check passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
