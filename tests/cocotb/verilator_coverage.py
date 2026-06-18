#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""Measure RTL line coverage of the SpaceWire core with Verilator + cocotb.

Builds the ``spw_axi_top`` integration testbench with Verilator ``--coverage``
across a few configurations (generic loopback, external-line error injection,
fast RX/TX front ends), runs the existing cocotb regressions against each,
merges the per-run Verilator coverage, and prints a per-file line-coverage
summary plus an RTL total.

This complements the functional cover-point test (which the Icarus/GHDL flow
already runs); it is the line-coverage flow. It needs a Verilator-capable
environment (Linux / WSL) with ``verilator`` and ``verilator_coverage`` on PATH.

Requires Verilator >= 5.022: older releases lack the VPI entry points cocotb's
Verilator harness calls (``clearEvalNeeded``/``doInertialPuts``/``evalNeeded``),
and the Debian/Ubuntu apt package (5.020) is too old. Build a current ``stable``
Verilator from source if needed.

Usage:
    python3 tests/cocotb/verilator_coverage.py

The build/coverage artifacts go under ``build/coverage`` (git-ignored); override
the location with ``SPW_COV_BUILD`` (e.g. a fast native path when the repo lives
on a slow mount).
"""
from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPW_DIR = ROOT / "tests" / "cocotb" / "spw_axi_top"
# The cocotb runner derives the simulation's PYTHONPATH from this process's
# sys.path, so ROOT (for ``tests.cocotb.*``) and SPW_DIR (for the test modules)
# must be importable here, not just via the environment.
sys.path.insert(0, str(SPW_DIR))
sys.path.insert(0, str(ROOT))

from tests.cocotb.spw_axi_top.test_spw_axi_top_runner import VERILOG_RTL  # noqa: E402

TOP = "spw_axi_top_loop_tb"

# (label, cocotb test module, testbench parameters) build/run configurations.
# Together they exercise the generic and fast front ends and the link-error
# paths, so the merged coverage spans the whole core and the AXI wrappers.
CONFIGS = [
    ("generic-loopback", "spw_axi_top_cocotb", {}),
    ("external-line-errors", "spw_axi_top_line_cocotb", {"LOOPBACK": 0}),
    ("fast-frontends", "spw_axi_top_cocotb", {"RXIMPL": 1, "TXIMPL": 1, "RXCHUNK": 4}),
]

BUILD_ARGS = [
    "--language", "1364-2005",  # plain Verilog-2005: syncdff's 'do' port is legal
    "--coverage",               # line + toggle + user coverage
    "-Wno-fatal",               # keep third-party-RTL lint warnings non-fatal
    "-Wno-WIDTH", "-Wno-UNOPTFLAT", "-Wno-CASEINCOMPLETE",
    "-Wno-UNUSEDSIGNAL", "-Wno-UNUSEDPARAM", "-Wno-BLKANDNBLK", "-Wno-CMPCONST",
]


def coverage_base() -> Path:
    return Path(os.environ.get("SPW_COV_BUILD", str(ROOT / "build" / "coverage")))


def run_config(label: str, module: str, params: dict) -> tuple[Path, bool]:
    from cocotb_tools.runner import get_runner

    build_dir = coverage_base() / label
    build_dir.mkdir(parents=True, exist_ok=True)
    sources = [ROOT / p for p in VERILOG_RTL] + [SPW_DIR / f"{TOP}.v"]

    runner = get_runner("verilator")
    runner.build(
        sources=sources,
        hdl_toplevel=TOP,
        build_dir=build_dir,
        parameters=params,
        build_args=BUILD_ARGS,
        always=True,
    )

    env = os.environ.copy()
    env["PYTHONPATH"] = os.pathsep.join(
        [str(ROOT), str(SPW_DIR), env.get("PYTHONPATH", "")]
    )
    ok = True
    try:
        runner.test(
            test_module=module,
            hdl_toplevel=TOP,
            test_dir=build_dir,
            results_xml=str(build_dir / "results.xml"),
            extra_env=env,
        )
    except Exception as exc:  # collect coverage even if a test fails
        ok = False
        print(f"[warn] {label}: cocotb run failed: {exc}")
    return build_dir / "coverage.dat", ok


def lcov_line_stats(info: Path) -> dict[str, list[int]]:
    per: dict[str, list[int]] = {}
    cur = None
    for line in info.read_text().splitlines():
        if line.startswith("SF:"):
            cur = line[3:]
            per.setdefault(cur, [0, 0])
        elif line.startswith("DA:") and cur is not None:
            _, count = line[3:].split(",")
            per[cur][0] += 1
            if int(count) > 0:
                per[cur][1] += 1
    return per


def main() -> int:
    for tool in ("verilator", "verilator_coverage"):
        if shutil.which(tool) is None:
            raise SystemExit(
                f"ERROR: {tool} not found on PATH; this flow needs Verilator >= 5.022 "
                "(see the module docstring)."
            )

    dats: list[str] = []
    all_ok = True
    for label, module, params in CONFIGS:
        print(f"\n===== coverage config: {label} ({module} {params or 'default'}) =====")
        dat, ok = run_config(label, module, params)
        all_ok = all_ok and ok
        if dat.exists():
            dats.append(str(dat))
        else:
            print(f"[warn] no coverage.dat produced for {label}")
    if not dats:
        raise SystemExit("no coverage data produced")

    merged = coverage_base() / "merged.info"
    if os.system(f"verilator_coverage --write-info {merged} {' '.join(dats)}") != 0:
        raise SystemExit("verilator_coverage merge failed")

    per = lcov_line_stats(merged)
    total_found = total_hit = 0
    print(f"\n=== merged Verilator line coverage ({len(dats)} configs) ===")
    for sf, (found, hit) in sorted(per.items()):
        name = Path(sf).name
        if name == f"{TOP}.v":  # testbench, not RTL under test
            continue
        total_found += found
        total_hit += hit
        pct = 100.0 * hit / found if found else 0.0
        print(f"  {name:26s} {hit:5d}/{found:<5d} {pct:6.1f}%")
    overall = 100.0 * total_hit / total_found if total_found else 0.0
    print(f"  {'TOTAL (RTL)':26s} {total_hit:5d}/{total_found:<5d} {overall:6.1f}%")
    print(f"\nmerged lcov info: {merged}")
    return 0 if all_ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
