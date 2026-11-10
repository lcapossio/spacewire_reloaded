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

Power-up state: for rx the registers of both designs start from arbitrary,
independent values (only the two buffer RAMs start equal, at zero). For tx
every register of both designs starts at zero: the transmitter has txclk
registers that no reset clears (b_token, c_bits, e_shift, ...), and with
independent arbitrary power-up values the PDR run does not converge.

Targets:
  rx1..rx4  spwrecvfront_fast with rxchunk = 1..4
  tx        spwxmit_fast (through parity/formal/fast/spwxmit_fast_flat.vhd),
            identical all-zero power-up state

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
        chparam=f"-chparam RXCHUNK {n}", zero_init=False) for n in (1, 2, 3, 4)},
    "tx": dict(
        vhdl=[VHDL / "spwpkg.vhd", VHDL / "syncdff.vhd", VHDL / "spwxmit_fast.vhd",
              FAST / "spwxmit_fast_flat.vhd"],
        vtop="spwxmit_fast_flat", generics=[],
        verilog=[VLOG / "syncdff.v", VLOG / "spwxmit_fast.v"],
        miter=FAST / "miter_tx.sv", mtop="miter_tx", gold="gold_tx", chparam="",
        zero_init=True),
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
        gold_v=gold_v.as_posix(), vtop=t["vtop"], gold=t["gold"],
        verilog=" ".join(p.as_posix() for p in t["verilog"]),
        miter=t["miter"].as_posix(), mtop=t["mtop"], chparam=t["chparam"],
        aig=(d / "model.aig").as_posix(),
        zero_init="# All registers of both designs power up at zero.\nsetundef -zero -init\n"
                  if t["zero_init"] else ""))
    r = run(["yosys", "-q", "-s", str(ys)], d, d / "yosys.log")
    if r.returncode:
        return name, False, f"yosys failed, see {d / 'yosys.log'}"
    r = run(["yosys-abc", "-c",
             "read_aiger model.aig; strash; scorr -c; fold; pdr; write_cex -a cex.aiw"],
            d, d / "abc.log")
    out = r.stdout
    if "Property proved" in out:
        init = "zero power-up" if t["zero_init"] else "arbitrary power-up"
        return name, True, f"proved (unbounded, PDR, {init})"
    for line in out.splitlines():
        if "was asserted in frame" in line:
            return name, False, f"counterexample: {line.strip()}"
    return name, False, f"no verdict, see {d / 'abc.log'}"


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
