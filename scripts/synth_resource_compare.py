#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

"""Run matched SpaceWire Light synthesis checks and print resource stats."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
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
    "syn/vhdl/spwstream_synth_wrappers.vhd",
]

VERILOG_SOURCES = [
    "rtl/verilog/syncdff.v",
    "rtl/verilog/spwram.v",
    "rtl/verilog/spwlink.v",
    "rtl/verilog/spwxmit.v",
    "rtl/verilog/spwxmit_fast.v",
    "rtl/verilog/spwrecv.v",
    "rtl/verilog/spwrecvfront_generic.v",
    "rtl/verilog/spwrecvfront_fast.v",
    "rtl/verilog/spwstream.v",
    "rtl/verilog/streamtest.v",
]


def run(cmd: list[str], cwd: Path = ROOT, stdout: int | None = None) -> None:
    print("+ " + " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, stdout=stdout, check=True)


def run_capture(cmd: list[str], cwd: Path = ROOT, input_text: str | None = None) -> str:
    print("+ " + " ".join(cmd), flush=True)
    try:
        return subprocess.check_output(
            cmd,
            cwd=cwd,
            input=input_text,
            text=True,
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError as err:
        if err.output:
            print(err.output, end="")
        raise


def ghdl_analyze() -> None:
    run(["ghdl", "--clean"])
    run(["ghdl", "-a", "--std=08", "-fsynopsys", *VHDL_SOURCES])


def emit_vhdl_netlist(entity: str, path: Path) -> None:
    with path.open("w", encoding="utf-8") as handle:
        run(
            ["ghdl", "--synth", "--std=08", "-fsynopsys", "--out=verilog", entity],
            stdout=handle,
        )


def yosys_stats(name: str, commands: list[str], stats_path: Path) -> dict[str, object]:
    script = "\n".join([*commands, f"tee -o {stats_path.as_posix()} stat -json"])
    run_capture(["yosys", "-q", "-"], input_text=script + "\n")
    data = json.loads(stats_path.read_text(encoding="utf-8"))
    modules = data.get("modules", {})
    if not modules:
        raise RuntimeError(f"Yosys did not report any modules for {name}")
    top = next(iter(modules.values()))
    return {
        "wires": top.get("num_wires", 0),
        "wire_bits": top.get("num_wire_bits", 0),
        "memories": top.get("num_memories", 0),
        "memory_bits": top.get("num_memory_bits", 0),
        "cells": top.get("num_cells", 0),
    }


def verilog_commands(rximpl: int, tximpl: int, rxchunk: int) -> list[str]:
    sources = " ".join(VERILOG_SOURCES)
    return [
        f"read_verilog {sources}",
        (
            "hierarchy -check -top spwstream "
            f"-chparam RXIMPL {rximpl} -chparam TXIMPL {tximpl} "
            f"-chparam RXCHUNK {rxchunk}"
        ),
        "proc",
        "memory",
        "opt",
        "check",
    ]


def vhdl_netlist_commands(path: Path, top: str) -> list[str]:
    return [
        f"read_verilog {path.as_posix()}",
        f"hierarchy -check -top {top}",
        "proc",
        "memory",
        "opt",
        "check",
    ]


def pct_delta(reference: int, value: int) -> str:
    if reference == 0:
        return "n/a"
    delta = 100.0 * (value - reference) / reference
    return f"{delta:+.1f}%"


def markdown_table(results: dict[str, dict[str, object]]) -> str:
    pairs = [
        ("generic", "Verilog generic", "VHDL generic"),
        ("fast", "Verilog fast", "VHDL fast"),
    ]
    lines = [
        "| Config | Source | Cells | Cell delta vs Verilog | Wires | Wire bits | Memories | Memory bits |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for config, verilog_key, vhdl_key in pairs:
        vref = int(results[verilog_key]["cells"])
        for label, key in [("Verilog", verilog_key), ("VHDL-derived", vhdl_key)]:
            row = results[key]
            cells = int(row["cells"])
            delta = "reference" if label == "Verilog" else pct_delta(vref, cells)
            lines.append(
                f"| {config} | {label} | {cells} | {delta} | "
                f"{row['wires']} | {row['wire_bits']} | "
                f"{row['memories']} | {row['memory_bits']} |"
            )
    return "\n".join(lines)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix=".spw_synth_", dir=ROOT) as tmp:
        tmpdir = Path(tmp)
        ghdl_analyze()
        generic_netlist = tmpdir / "spwstream_synth_generic.v"
        fast_netlist = tmpdir / "spwstream_synth_fast.v"
        emit_vhdl_netlist("spwstream_synth_generic", generic_netlist)
        emit_vhdl_netlist("spwstream_synth_fast", fast_netlist)

        results = {
            "Verilog generic": yosys_stats(
                "Verilog generic",
                verilog_commands(0, 0, 1),
                tmpdir / "verilog_generic.json",
            ),
            "Verilog fast": yosys_stats(
                "Verilog fast",
                verilog_commands(1, 1, 4),
                tmpdir / "verilog_fast.json",
            ),
            "VHDL generic": yosys_stats(
                "VHDL generic",
                vhdl_netlist_commands(generic_netlist, "spwstream_synth_generic"),
                tmpdir / "vhdl_generic.json",
            ),
            "VHDL fast": yosys_stats(
                "VHDL fast",
                vhdl_netlist_commands(fast_netlist, "spwstream_synth_fast"),
                tmpdir / "vhdl_fast.json",
            ),
        }

    table = markdown_table(results)
    print("\nSynthesis resource comparison\n")
    print(table)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with Path(summary).open("a", encoding="utf-8") as handle:
            handle.write("## Synthesis resource comparison\n\n")
            handle.write(table)
            handle.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
