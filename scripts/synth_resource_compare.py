#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

"""Run synthesis checks and print resource/timing reports."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

VHDL_COMMON = [
    "rtl/vhdl/spwpkg.vhd",
    "rtl/vhdl/spwlink.vhd",
    "rtl/vhdl/spwrecv.vhd",
    "rtl/vhdl/spwxmit.vhd",
    "rtl/vhdl/spwxmit_fast.vhd",
    "rtl/vhdl/spwrecvfront_generic.vhd",
    "rtl/vhdl/spwrecvfront_fast.vhd",
    "rtl/vhdl/syncdff.vhd",
    "rtl/vhdl/spwram.vhd",
]

VHDL_STREAM_SOURCES = VHDL_COMMON + [
    "rtl/vhdl/spwstream.vhd",
    "syn/vhdl/spwstream_synth_wrappers.vhd",
]

VHDL_AXI_SOURCES = VHDL_COMMON + [
    "rtl/vhdl/spwstream.vhd",
    "rtl/vhdl/spw_axis_tx.vhd",
    "rtl/vhdl/spw_axis_rx.vhd",
    "rtl/vhdl/spw_axi_lite_regs.vhd",
    "rtl/vhdl/spw_axi_top.vhd",
    "syn/vhdl/spw_axi_synth_wrappers.vhd",
]

VERILOG_STREAM_SOURCES = [
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

VERILOG_AXI_SOURCES = [
    "rtl/verilog/syncdff.v",
    "rtl/verilog/spwram.v",
    "rtl/verilog/spwlink.v",
    "rtl/verilog/spwxmit.v",
    "rtl/verilog/spwxmit_fast.v",
    "rtl/verilog/spwrecv.v",
    "rtl/verilog/spwrecvfront_generic.v",
    "rtl/verilog/spwrecvfront_fast.v",
    "rtl/verilog/spwstream.v",
    "rtl/verilog/spw_axis_tx.v",
    "rtl/verilog/spw_axis_rx.v",
    "rtl/verilog/spw_axi_lite_regs.v",
    "rtl/verilog/spw_axi_top.v",
]


@dataclass(frozen=True)
class SynthTarget:
    report: str
    config: str
    source: str
    key: str
    top: str
    commands: list[str]


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


def ghdl_analyze(sources: list[str]) -> None:
    run(["ghdl", "--clean"])
    run(["ghdl", "-a", "--std=08", "-fsynopsys", *sources])


def emit_vhdl_netlist(entity: str, path: Path) -> None:
    with path.open("w", encoding="utf-8") as handle:
        run(
            ["ghdl", "--synth", "--std=08", "-fsynopsys", "--out=verilog", entity],
            stdout=handle,
        )


def parse_ltp(text: str) -> dict[str, object]:
    levels = None
    for pattern in (
        r"Longest topological path.*?([0-9]+)\s+(?:cells|gates|levels)",
        r"length\s+([0-9]+)",
    ):
        match = re.search(pattern, text)
        if match:
            levels = int(match.group(1))
            break
    if levels is None:
        path_lines = [
            line for line in text.splitlines()
            if re.match(r"\s*[0-9]+:\s+", line)
        ]
        levels = len(path_lines) if path_lines else None
    return {"critical_path_levels": levels}


def yosys_stats(
    name: str,
    top_name: str,
    commands: list[str],
    stats_path: Path,
    timing_path: Path,
    design_path: Path,
) -> dict[str, object]:
    script = "\n".join(
        [
            *commands,
            f"tee -o {timing_path.as_posix()} ltp",
            f"tee -o {stats_path.as_posix()} stat -json",
            f"write_json {design_path.as_posix()}",
        ]
    )
    run_capture(["yosys", "-q", "-"], input_text=script + "\n")
    stats_data = json.loads(stats_path.read_text(encoding="utf-8"))
    stats_modules = stats_data.get("modules", {})
    top_key = next(
        (key for key in stats_modules if key.lstrip("\\") == top_name),
        None,
    )
    if top_key is None:
        reported = ", ".join(sorted(stats_modules))
        raise RuntimeError(f"Yosys did not report top module {top_name} for {name}; got: {reported}")
    design_data = json.loads(design_path.read_text(encoding="utf-8"))
    totals = hierarchical_totals(top_name, stats_modules, design_data.get("modules", {}))
    return {
        **totals,
        **parse_ltp(timing_path.read_text(encoding="utf-8")),
    }


def module_lookup(modules: dict[str, object]) -> dict[str, str]:
    return {name.lstrip("\\"): name for name in modules}


def hierarchical_totals(
    top_name: str,
    stats_modules: dict[str, object],
    design_modules: dict[str, object],
) -> dict[str, int]:
    stats_lookup = module_lookup(stats_modules)
    design_lookup = module_lookup(design_modules)

    def walk(module_name: str) -> dict[str, int]:
        stats_key = stats_lookup[module_name]
        design_key = design_lookup[module_name]
        stats = stats_modules[stats_key]
        design = design_modules[design_key]
        totals = {
            "wires": int(stats.get("num_wires", 0)),
            "wire_bits": int(stats.get("num_wire_bits", 0)),
            "memories": int(stats.get("num_memories", 0)),
            "memory_bits": int(stats.get("num_memory_bits", 0)),
            "cells": 0,
            "dffs": 0,
        }
        for cell in design.get("cells", {}).values():
            cell_type = str(cell.get("type", "")).lstrip("\\")
            if cell_type in design_lookup:
                child = walk(cell_type)
                for key, value in child.items():
                    totals[key] += value
            else:
                totals["cells"] += 1
                if "DFF" in cell_type.upper():
                    totals["dffs"] += 1
        return totals

    return walk(top_name)


def synth_steps() -> list[str]:
    return [
        "proc",
        "memory",
        "opt",
        "check",
    ]


def verilog_stream_commands(rximpl: int, tximpl: int, rxchunk: int) -> list[str]:
    sources = " ".join(VERILOG_STREAM_SOURCES)
    return [
        f"read_verilog {sources}",
        (
            "hierarchy -check -top spwstream "
            f"-chparam RXIMPL {rximpl} -chparam TXIMPL {tximpl} "
            f"-chparam RXCHUNK {rxchunk}"
        ),
        *synth_steps(),
    ]


def verilog_axi_commands(top: str, chparams: dict[str, int] | None = None) -> list[str]:
    sources = " ".join(VERILOG_AXI_SOURCES)
    commands = [f"read_verilog {sources}"]
    for name, value in (chparams or {}).items():
        commands.append(f"chparam -set {name} {value} {top}")
    return [*commands, f"hierarchy -check -top {top}", *synth_steps()]


def vhdl_netlist_commands(path: Path, top: str) -> list[str]:
    return [
        f"read_verilog {path.as_posix()}",
        f"hierarchy -check -top {top}",
        *synth_steps(),
    ]


def pct_delta(reference: int, value: int) -> str:
    if reference == 0:
        return "n/a"
    delta = 100.0 * (value - reference) / reference
    return f"{delta:+.1f}%"


def fmt_float(value: object, digits: int = 2) -> str:
    if value is None:
        return "n/a"
    return f"{float(value):.{digits}f}"


def stream_markdown_table(results: dict[str, dict[str, object]]) -> str:
    pairs = [
        ("generic", "Verilog generic", "VHDL generic"),
        ("fast", "Verilog fast", "VHDL fast"),
    ]
    lines = [
        "| Config | Source | Cells | Cell delta vs Verilog | FF cells | Wires | Wire bits | Memories | Memory bits |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for config, verilog_key, vhdl_key in pairs:
        vref = int(results[verilog_key]["cells"])
        for label, key in [("Verilog", verilog_key), ("VHDL-derived", vhdl_key)]:
            row = results[key]
            cells = int(row["cells"])
            delta = "reference" if label == "Verilog" else pct_delta(vref, cells)
            lines.append(
                f"| {config} | {label} | {cells} | {delta} | "
                f"{row['dffs']} | {row['wires']} | {row['wire_bits']} | "
                f"{row['memories']} | {row['memory_bits']} |"
            )
    return "\n".join(lines)


def axi_markdown_table(targets: list[SynthTarget], results: dict[str, dict[str, object]]) -> str:
    lines = [
        "| Block | Config | Source | Cells | FF cells | Wires | Wire bits | Memories | Memory bits | Critical path levels |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
    ]
    for target in targets:
        row = results[target.key]
        lines.append(
            f"| {target.report} | {target.config} | {target.source} | "
            f"{row['cells']} | {row['dffs']} | {row['wires']} | {row['wire_bits']} | "
            f"{row['memories']} | {row['memory_bits']} | "
            f"{row['critical_path_levels'] if row['critical_path_levels'] is not None else 'n/a'} |"
        )
    return "\n".join(lines)


def collect_stream_results(tmpdir: Path) -> dict[str, dict[str, object]]:
    ghdl_analyze(VHDL_STREAM_SOURCES)
    generic_netlist = tmpdir / "spwstream_synth_generic.v"
    fast_netlist = tmpdir / "spwstream_synth_fast.v"
    emit_vhdl_netlist("spwstream_synth_generic", generic_netlist)
    emit_vhdl_netlist("spwstream_synth_fast", fast_netlist)

    return {
        "Verilog generic": yosys_stats(
            "Verilog generic",
            "spwstream",
            verilog_stream_commands(0, 0, 1),
            tmpdir / "verilog_generic.json",
            tmpdir / "verilog_generic_timing.txt",
            tmpdir / "verilog_generic_design.json",
        ),
        "Verilog fast": yosys_stats(
            "Verilog fast",
            "spwstream",
            verilog_stream_commands(1, 1, 4),
            tmpdir / "verilog_fast.json",
            tmpdir / "verilog_fast_timing.txt",
            tmpdir / "verilog_fast_design.json",
        ),
        "VHDL generic": yosys_stats(
            "VHDL generic",
            "spwstream_synth_generic",
            vhdl_netlist_commands(generic_netlist, "spwstream_synth_generic"),
            tmpdir / "vhdl_generic.json",
            tmpdir / "vhdl_generic_timing.txt",
            tmpdir / "vhdl_generic_design.json",
        ),
        "VHDL fast": yosys_stats(
            "VHDL fast",
            "spwstream_synth_fast",
            vhdl_netlist_commands(fast_netlist, "spwstream_synth_fast"),
            tmpdir / "vhdl_fast.json",
            tmpdir / "vhdl_fast_timing.txt",
            tmpdir / "vhdl_fast_design.json",
        ),
    }


def collect_axi_results(tmpdir: Path) -> tuple[list[SynthTarget], dict[str, dict[str, object]]]:
    ghdl_analyze(VHDL_AXI_SOURCES)
    vhdl_netlists = {
        "spw_axis_tx": tmpdir / "vhdl_spw_axis_tx.v",
        "spw_axis_rx": tmpdir / "vhdl_spw_axis_rx.v",
        "spw_axi_lite_regs": tmpdir / "vhdl_spw_axi_lite_regs.v",
        "spw_axi_top_synth_generic": tmpdir / "vhdl_spw_axi_top_synth_generic.v",
        "spw_axi_top_synth_fast": tmpdir / "vhdl_spw_axi_top_synth_fast.v",
    }
    for entity, path in vhdl_netlists.items():
        emit_vhdl_netlist(entity, path)

    targets = [
        SynthTarget("AXI-Stream TX bridge", "leaf", "Verilog", "verilog_axis_tx", "spw_axis_tx", verilog_axi_commands("spw_axis_tx")),
        SynthTarget("AXI-Stream TX bridge", "leaf", "VHDL-derived", "vhdl_axis_tx", "spw_axis_tx", vhdl_netlist_commands(vhdl_netlists["spw_axis_tx"], "spw_axis_tx")),
        SynthTarget("AXI-Stream RX bridge", "leaf", "Verilog", "verilog_axis_rx", "spw_axis_rx", verilog_axi_commands("spw_axis_rx")),
        SynthTarget("AXI-Stream RX bridge", "leaf", "VHDL-derived", "vhdl_axis_rx", "spw_axis_rx", vhdl_netlist_commands(vhdl_netlists["spw_axis_rx"], "spw_axis_rx")),
        SynthTarget("AXI-Lite register block", "8-bit address", "Verilog", "verilog_axil_regs", "spw_axi_lite_regs", verilog_axi_commands("spw_axi_lite_regs")),
        SynthTarget("AXI-Lite register block", "8-bit address", "VHDL-derived", "vhdl_axil_regs", "spw_axi_lite_regs", vhdl_netlist_commands(vhdl_netlists["spw_axi_lite_regs"], "spw_axi_lite_regs")),
        SynthTarget("AXI top wrapper", "generic RX/TX, 20 MHz", "Verilog", "verilog_axi_top_generic", "spw_axi_top", verilog_axi_commands("spw_axi_top", {"SYS_CLOCK_HZ": 20000000, "TX_CLOCK_HZ": 20000000})),
        SynthTarget("AXI top wrapper", "generic RX/TX, 20 MHz", "VHDL-derived", "vhdl_axi_top_generic", "spw_axi_top_synth_generic", vhdl_netlist_commands(vhdl_netlists["spw_axi_top_synth_generic"], "spw_axi_top_synth_generic")),
        SynthTarget("AXI top wrapper", "fast RX/TX, 50/100 MHz", "Verilog", "verilog_axi_top_fast", "spw_axi_top", verilog_axi_commands("spw_axi_top", {"SYS_CLOCK_HZ": 50000000, "TX_CLOCK_HZ": 100000000, "RXIMPL": 1, "TXIMPL": 1, "RXCHUNK": 4})),
        SynthTarget("AXI top wrapper", "fast RX/TX, 50/100 MHz", "VHDL-derived", "vhdl_axi_top_fast", "spw_axi_top_synth_fast", vhdl_netlist_commands(vhdl_netlists["spw_axi_top_synth_fast"], "spw_axi_top_synth_fast")),
    ]
    results = {
        target.key: yosys_stats(
            target.key,
            target.top,
            target.commands,
            tmpdir / f"{target.key}.json",
            tmpdir / f"{target.key}_timing.txt",
            tmpdir / f"{target.key}_design.json",
        )
        for target in targets
    }
    return targets, results


def main() -> int:
    with tempfile.TemporaryDirectory(prefix=".spw_synth_", dir=ROOT) as tmp:
        tmpdir = Path(tmp)
        stream_results = collect_stream_results(tmpdir)
        axi_targets, axi_results = collect_axi_results(tmpdir)

    stream_table = stream_markdown_table(stream_results)
    axi_table = axi_markdown_table(axi_targets, axi_results)
    timing_note = (
        "Timing condition: Yosys `ltp` critical-path logic levels after "
        "RTL-level synthesis; this is a CI trend metric, not vendor "
        "place-and-route timing or an Fmax guarantee."
    )

    print("\nSynthesis resource comparison\n")
    print(stream_table)
    print("\nAXI synthesis resource and timing report\n")
    print(axi_table)
    print(f"\n{timing_note}")

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with Path(summary).open("a", encoding="utf-8") as handle:
            handle.write("## Synthesis resource comparison\n\n")
            handle.write(stream_table)
            handle.write("\n\n## AXI synthesis resource and timing report\n\n")
            handle.write(axi_table)
            handle.write(f"\n\n{timing_note}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
