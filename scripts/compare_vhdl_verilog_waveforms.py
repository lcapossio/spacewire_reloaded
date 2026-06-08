#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

"""Compare normalized VHDL and Verilog VCD waveforms for matched benches."""

from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path.cwd()

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

SIGNALS = {
    "clk": ("streamtest_trace_tb.sysclk", "streamtest_trace_tb.clk"),
    "rst": ("streamtest_trace_tb.s_rst", "streamtest_trace_tb.rst"),
    "loopback": ("streamtest_trace_tb.s_loopback", "streamtest_trace_tb.loopback"),
    "linkstart": ("streamtest_trace_tb.s_linkstart", "streamtest_trace_tb.linkstart"),
    "autostart": ("streamtest_trace_tb.s_autostart", "streamtest_trace_tb.autostart"),
    "linkdisable": ("streamtest_trace_tb.s_linkdisable", "streamtest_trace_tb.linkdisable"),
    "txdivcnt": ("streamtest_trace_tb.s_divcnt[7:0]", "streamtest_trace_tb.txdivcnt [7:0]"),
    "nreceived": ("streamtest_trace_tb.s_nreceived", "streamtest_trace_tb.nreceived [31:0]"),
    "linkrun": ("streamtest_trace_tb.s_linkrun", "streamtest_trace_tb.linkrun"),
    "linkerror": ("streamtest_trace_tb.s_linkerror", "streamtest_trace_tb.linkerror"),
    "gotdata": ("streamtest_trace_tb.s_gotdata", "streamtest_trace_tb.gotdata"),
    "dataerror": ("streamtest_trace_tb.s_dataerror", "streamtest_trace_tb.dataerror"),
    "tickerror": ("streamtest_trace_tb.s_tickerror", "streamtest_trace_tb.tickerror"),
    "spw_di": ("streamtest_trace_tb.s_spwdi", "streamtest_trace_tb.spw_di"),
    "spw_si": ("streamtest_trace_tb.s_spwsi", "streamtest_trace_tb.spw_si"),
    "spw_do": ("streamtest_trace_tb.s_spwdo", "streamtest_trace_tb.spw_do"),
    "spw_so": ("streamtest_trace_tb.s_spwso", "streamtest_trace_tb.spw_so"),
}


def run(cmd: list[str]) -> str:
    print("+ " + " ".join(cmd), flush=True)
    return subprocess.check_output(cmd, cwd=ROOT, text=True, stderr=subprocess.STDOUT)


def build_waveforms(tmpdir: Path) -> tuple[Path, Path]:
    verilog_vvp = tmpdir / "streamtest_trace_tb.vvp"
    verilog_vcd = tmpdir / "streamtest_trace_verilog.vcd"
    vhdl_vcd = tmpdir / "streamtest_trace_vhdl.vcd"

    run(["iverilog", "-g2001", "-o", str(verilog_vvp), *VERILOG_SOURCES])
    run(["vvp", str(verilog_vvp), f"+WAVE={verilog_vcd}"])

    run(["ghdl", "--clean"])
    run(["ghdl", "-a", "--std=08", "-fsynopsys", *VHDL_SOURCES])
    run(["ghdl", "-e", "--std=08", "-fsynopsys", "streamtest_trace_tb"])
    run([
        "ghdl",
        "-r",
        "--std=08",
        "-fsynopsys",
        "streamtest_trace_tb",
        "--assert-level=error",
        f"--vcd={vhdl_vcd}",
    ])
    (ROOT / "work-obj08.cf").unlink(missing_ok=True)
    return vhdl_vcd, verilog_vcd


def timescale_to_ps(text: str) -> float:
    match = re.search(r"\$timescale\s+(\d+)\s*([fpnum]?s)\s+\$end", text, re.S)
    if not match:
        raise ValueError(f"unsupported VCD timescale: {line!r}")
    value = int(match.group(1))
    unit = match.group(2)
    factors = {
        "fs": 0.001,
        "ps": 1.0,
        "ns": 1000.0,
        "us": 1_000_000.0,
        "ms": 1_000_000_000.0,
        "s": 1_000_000_000_000.0,
    }
    return value * factors[unit]


def canonical(value: str) -> str:
    value = value.lower()
    if value in {"x", "z", "u", "w", "-"}:
        return "x"
    if value.startswith("b"):
        bits = value[1:].lower()
        bits = "".join("x" if bit not in "01" else bit for bit in bits)
        return bits.lstrip("0") or "0"
    return value


def parse_vcd(path: Path, wanted_paths: dict[str, str]) -> dict[str, list[tuple[int, str]]]:
    lines = path.read_text().splitlines()
    scale_ps = None
    scopes: list[str] = []
    codes: dict[str, str] = {}
    code_to_names: dict[str, list[str]] = {}
    in_defs = True
    start_idx = 0

    for idx, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("$timescale"):
            text = stripped
            j = idx + 1
            while "$end" not in text and j < len(lines):
                text += " " + lines[j].strip()
                j += 1
            scale_ps = timescale_to_ps(text)
        elif stripped.startswith("$scope"):
            parts = stripped.split()
            scopes.append(parts[2])
        elif stripped.startswith("$upscope"):
            scopes.pop()
        elif stripped.startswith("$var"):
            parts = stripped.split()
            code = parts[3]
            ref = " ".join(parts[4:-1])
            full = ".".join([*scopes, ref])
            code_to_names.setdefault(code, []).append(full)
        elif stripped.startswith("$enddefinitions"):
            start_idx = idx + 1
            in_defs = False
            break

    if in_defs or scale_ps is None:
        raise ValueError(f"{path}: incomplete VCD header")

    for name, full_path in wanted_paths.items():
        for code, names in code_to_names.items():
            if full_path in names:
                codes[name] = code
                break
        else:
            available = "\n  ".join(sorted(name for names in code_to_names.values() for name in names))
            raise ValueError(f"{path}: missing signal {full_path}\nAvailable:\n  {available}")

    target_codes = {code: name for name, code in codes.items()}
    state = {name: "x" for name in wanted_paths}
    samples: dict[str, list[tuple[int, str]]] = {name: [] for name in wanted_paths}
    current_time = 0

    def emit(name: str, value: str) -> None:
        value = canonical(value)
        if state[name] != value:
            state[name] = value
            samples[name].append((current_time, value))

    for line in lines[start_idx:]:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("#"):
            current_time = int(round(int(stripped[1:]) * scale_ps))
            continue
        if stripped[0] in "01xzXZ":
            code = stripped[1:]
            if code in target_codes:
                emit(target_codes[code], stripped[0])
        elif stripped[0] == "b":
            value, code = stripped.split(None, 1)
            if code in target_codes:
                emit(target_codes[code], value)

    return samples


def value_at(changes: list[tuple[int, str]], time_ps: int) -> str:
    value = "x"
    for change_time, change_value in changes:
        if change_time > time_ps:
            break
        value = change_value
    return value


def compare(vhdl_vcd: Path, verilog_vcd: Path) -> int:
    vhdl_paths = {name: paths[0] for name, paths in SIGNALS.items()}
    verilog_paths = {name: paths[1] for name, paths in SIGNALS.items()}
    vhdl = parse_vcd(vhdl_vcd, vhdl_paths)
    verilog = parse_vcd(verilog_vcd, verilog_paths)

    mismatches: list[str] = []
    start_ps = 25_000
    end_ps = min(
        max(time for changes in vhdl.values() for time, _ in changes),
        max(time for changes in verilog.values() for time, _ in changes),
    )

    for name in SIGNALS:
        sample_times = sorted({
            time
            for changes in (vhdl[name], verilog[name])
            for time, _ in changes
            if start_ps <= time <= end_ps
        })
        diff = next(
            (
                time
                for time in sample_times
                if value_at(vhdl[name], time) != value_at(verilog[name], time)
            ),
            None,
        )
        if diff is not None:
            mismatches.append(name)
            print(f"\nERROR: waveform mismatch for {name}", file=sys.stderr)
            print(f"  time_ps: {diff}", file=sys.stderr)
            print(f"  VHDL:    {value_at(vhdl[name], diff)}", file=sys.stderr)
            print(f"  Verilog: {value_at(verilog[name], diff)}", file=sys.stderr)

    if mismatches:
        print(f"\nERROR: {len(mismatches)} signal waveform(s) differ", file=sys.stderr)
        return 1
    print(
        "\nPASS: streamtest_trace_tb normalized waveforms match "
        f"for {len(SIGNALS)} signals from {start_ps} ps to {end_ps} ps"
    )
    return 0


def main() -> int:
    tmpdir = Path(".wavecmp_tmp")
    shutil.rmtree(tmpdir, ignore_errors=True)
    tmpdir.mkdir(exist_ok=True)
    try:
        vhdl_vcd, verilog_vcd = build_waveforms(tmpdir)
        return compare(vhdl_vcd, verilog_vcd)
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
