#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

"""Formal VHDL/Verilog equivalence of the fast (dual-clock) front ends.

For each target the VHDL golden is synthesized with GHDL (``--synth
--out=verilog``), the Verilog translation is read as is, and both are placed
in a miter (parity/formal/fast/miter_*.sv) that drives them with the same
inputs and asserts equal outputs. Both clocks are free formal inputs
(Yosys clk2fflogic, i.e. independent clocks with arbitrary phase). The miter
is reduced with ABC signal correspondence (scorr, honouring the miter's
environment assumptions) and checked with ABC's PDR engine: "proved" is an
unbounded proof, a failure prints the frame of the counterexample.

Power-up state: all source initializers of both designs are removed. For rx
every register then starts from an arbitrary value, independently in each
design (only the two buffer RAMs start equal, at zero). For tx every register
of both designs starts at zero; with independent arbitrary values the
outputs differ after a short reset. See parity/formal/README.md for the
environment rules each miter assumes.

Targets:
  rx1..rx4  spwrecvfront_fast with rxchunk = 1..4, arbitrary power-up
  tx        spwxmit_fast (through parity/formal/fast/spwxmit_fast_flat.vhd),
            all-zero power-up

Run from the repository root with ghdl, yosys and yosys-abc on PATH:
  python3 scripts/formal_parity_fast.py [target ...] [--jobs N] [--keep]
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FAST = ROOT / "parity" / "formal" / "fast"
VHDL = ROOT / "rtl" / "vhdl"
VLOG = ROOT / "rtl" / "verilog"

TARGETS = {
    **{f"rx{n}": dict(
        vhdl=[VHDL / "spwpkg.vhd", VHDL / "syncdff.vhd", VHDL / "spwram.vhd",
              VHDL / "spwrecvfront_fast.vhd"],
        vtop="spwrecvfront_fast", generics=[f"-grxchunk={n}"],
        verilog=[VLOG / "syncdff.v", VLOG / "spwram.v", VLOG / "spwrecvfront_fast.v"],
        miter=FAST / "miter_rx.sv", mtop="miter_rx", gold="gold_rx",
        chparam=f"-chparam RXCHUNK {n}", zero_init=False,
        init_desc="arbitrary power-up") for n in (1, 2, 3, 4)},
    "tx": dict(
        vhdl=[VHDL / "spwpkg.vhd", VHDL / "syncdff.vhd", VHDL / "spwxmit_fast.vhd",
              FAST / "spwxmit_fast_flat.vhd"],
        vtop="spwxmit_fast_flat", generics=[],
        verilog=[VLOG / "syncdff.v", VLOG / "spwxmit_fast.v"],
        miter=FAST / "miter_tx.sv", mtop="miter_tx", gold="gold_tx",
        # rst comes straight from the spwstream rst input: only assume that it
        # covers one clk edge (it is synchronous to clk).
        chparam="-chparam RST_CLK 1 -chparam RST_TXCLK 0", zero_init=True,
        init_desc="all-zero power-up"),
}

# Same model preparation as SymbiYosys (prove mode, multiclock on, abc pdr),
# run directly so the result does not depend on the installed SBY version.
YOSYS_SCRIPT = """\
read_verilog {gold_v}
hierarchy -top {vtop}
flatten
rename {vtop} {gold}
hierarchy -top {gold}
read_verilog {verilog}
read_verilog -formal {miter}
hierarchy -top {mtop} {chparam}
prep -top {mtop}
# Drop every source initializer (VHDL signal defaults, Verilog initial
# blocks) in both designs; only the miter's own registers keep theirs.
setattr -unset init */w:* {mtop}/* %d
# Both buffer RAMs start from the same (zero) contents.
setundef -zero -params t:$mem_v2
{zero_init}memory_map
opt_clean
hierarchy -smtcheck
rename -witness
memory_nordff
clk2fflogic
opt_clean
formalff -setundef -clk2ff -ff2anyinit -hierarchy
chformal -live -fair -cover -remove
opt_clean
check
setundef -undriven -anyseq
opt -fast
rename -witness
opt_clean
delete */t:$print
hierarchy -simcheck
formalff -assume
flatten
setundef -undriven -anyseq
setattr -unset keep
delete -output
opt -full
techmap
opt -fast
memory_map -formal
formalff -clk2ff -ff2anyinit
simplemap
dffunmap
aigmap
opt_clean
write_aiger -I -B -zinit -no-startoffset {aig}
"""


def yosys_path(p: Path) -> str:
    """A file name as a quoted Yosys command argument."""
    s = p.as_posix()
    if '"' in s:
        raise ValueError(f"path not usable in a Yosys script: {s}")
    return f'"{s}"'


def run(cmd: list[str], cwd: Path, log: Path) -> subprocess.CompletedProcess:
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    log.write_text(r.stdout + r.stderr)
    return r


def check(name: str, work: Path) -> tuple[str, bool, str]:
    t = TARGETS[name]
    d = work / name
    d.mkdir(parents=True, exist_ok=True)
    gold_v = d / "gold.v"
    r = run(["ghdl", "--synth", "--std=08", *t["generics"], "--out=verilog",
             *map(str, t["vhdl"]), "-e", t["vtop"]], d, d / "ghdl.log")
    if r.returncode:
        return name, False, f"ghdl failed, see {d / 'ghdl.log'}"
    gold_v.write_text(r.stdout)
    ys = d / "model.ys"
    ys.write_text(YOSYS_SCRIPT.format(
        gold_v=yosys_path(gold_v), vtop=t["vtop"], gold=t["gold"],
        verilog=" ".join(map(yosys_path, t["verilog"])),
        miter=yosys_path(t["miter"]), mtop=t["mtop"], chparam=t["chparam"],
        aig=yosys_path(d / "model.aig"),
        zero_init="# Every register of both designs powers up at zero.\nsetundef -zero -init\n"
                  if t["zero_init"] else ""))
    r = run(["yosys", "-q", "-s", str(ys)], d, d / "yosys.log")
    if r.returncode:
        return name, False, f"yosys failed, see {d / 'yosys.log'}"
    r = run(["yosys-abc", "-c",
             "read_aiger model.aig; strash; scorr -c; fold; pdr; write_cex -a cex.aiw"],
            d, d / "abc.log")
    lines = [ln.strip() for ln in r.stdout.splitlines()]
    proved = [ln for ln in lines if ln.startswith("Property proved.")]
    cex = [ln for ln in lines if "was asserted in frame" in ln]
    if r.returncode == 0 and len(proved) == 1 and not cex:
        return name, True, f"proved (unbounded, PDR, {t['init_desc']})"
    if cex:
        return name, False, f"counterexample: {cex[0]}"
    tail = "\n".join("    " + ln for ln in (r.stdout + r.stderr).splitlines()[-15:])
    return name, False, (f"no verdict (abc exit {r.returncode}), see {d / 'abc.log'};"
                         f" last lines:\n{tail}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("targets", nargs="*", metavar="target",
                    help=f"any of {', '.join(TARGETS)} (default: all)")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    ap.add_argument("--keep", action="store_true", help="keep the work directory")
    args = ap.parse_args()
    bad = [t for t in args.targets if t not in TARGETS]
    if bad:
        ap.error(f"unknown target(s): {', '.join(bad)}")
    if len(set(args.targets)) != len(args.targets):
        ap.error("duplicate target names")
    args.targets = args.targets or list(TARGETS)

    missing = [t for t in ("ghdl", "yosys", "yosys-abc") if shutil.which(t) is None]
    if missing:
        print(f"ERROR: not on PATH: {', '.join(missing)}", file=sys.stderr)
        return 2

    work = Path(tempfile.mkdtemp(prefix="formal_parity_fast_"))
    with ThreadPoolExecutor(max_workers=args.jobs) as ex:
        results = list(ex.map(lambda n: check(n, work), args.targets))
    ok = True
    for name, passed, msg in results:
        print(f"{'PASS' if passed else 'FAIL'}  {name:4}  {msg}")
        ok &= passed
    if args.keep or not ok:
        print(f"work directory: {work}")
    else:
        shutil.rmtree(work, ignore_errors=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
