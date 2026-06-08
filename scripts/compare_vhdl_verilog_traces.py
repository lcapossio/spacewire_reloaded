#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

"""Compare deterministic VHDL and Verilog streamtest traces."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

VHDL_SOURCES = [
    "rtl/vhdl/spwpkg.vhd",
    "rtl/vhdl/spwlink.vhd",
    "rtl/vhdl/spwrecv.vhd",
    "rtl/vhdl/spwxmit.vhd",
    "rtl/vhdl/spwxmit_fast.vhd",
    "rtl/vhdl/spwrecvfront_generic.vhd",
    "rtl/vhdl/spwrecvfront_fast.vhd",
    "rtl/vhdl/syncdff.vhd",
    "rtl/vhdl/spwram.vhd",
    "rtl/vhdl/spwstream.vhd",
    "rtl/vhdl/streamtest.vhd",
    "bench/vhdl/streamtest_trace_tb.vhd",
]

VERILOG_SOURCES = [
    "bench/verilog/streamtest_trace_tb.v",
    "rtl/verilog/streamtest.v",
    "rtl/verilog/syncdff.v",
    "rtl/verilog/spwram.v",
    "rtl/verilog/spwlink.v",
    "rtl/verilog/spwxmit.v",
    "rtl/verilog/spwxmit_fast.v",
    "rtl/verilog/spwrecv.v",
    "rtl/verilog/spwrecvfront_generic.v",
    "rtl/verilog/spwrecvfront_fast.v",
    "rtl/verilog/spwstream.v",
]


def run(cmd: list[str]) -> str:
    print("+ " + " ".join(cmd), flush=True)
    return subprocess.check_output(cmd, cwd=ROOT, text=True, stderr=subprocess.STDOUT)


def traces(output: str) -> list[str]:
    return [line.strip() for line in output.splitlines() if line.startswith("TRACE ")]


def run_verilog() -> list[str]:
    out = ROOT / "streamtest_trace_tb.vvp"
    run(["iverilog", "-g2001", "-o", str(out), *VERILOG_SOURCES])
    try:
        return traces(run(["vvp", str(out)]))
    finally:
        out.unlink(missing_ok=True)


def run_vhdl() -> list[str]:
    run(["ghdl", "--clean"])
    run(["ghdl", "-a", "--std=08", "-fsynopsys", *VHDL_SOURCES])
    run(["ghdl", "-e", "--std=08", "-fsynopsys", "streamtest_trace_tb"])
    try:
        return traces(run(["ghdl", "-r", "--std=08", "-fsynopsys", "streamtest_trace_tb", "--assert-level=error"]))
    finally:
        (ROOT / "work-obj08.cf").unlink(missing_ok=True)


def main() -> int:
    verilog_trace = run_verilog()
    vhdl_trace = run_vhdl()

    print("\nVerilog trace:")
    print("\n".join(verilog_trace))
    print("\nVHDL trace:")
    print("\n".join(vhdl_trace))

    if verilog_trace != vhdl_trace:
        print("\nERROR: VHDL and Verilog traces differ", file=sys.stderr)
        return 1
    print("\nPASS: VHDL and Verilog traces match")
    return 0


if __name__ == "__main__":
    sys.exit(main())
