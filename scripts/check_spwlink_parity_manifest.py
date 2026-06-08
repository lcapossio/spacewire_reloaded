#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

"""Check the spwlink parity manifest against the current bench sources."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path.cwd()
MANIFEST = ROOT / "parity" / "spwlink_manifest.yml"
VHDL_TB = ROOT / "bench" / "vhdl" / "spwlink_tb.vhd"
VERILOG_TB = ROOT / "bench" / "verilog" / "spwlink_tb.v"
VERILOG_TB_ALL = ROOT / "bench" / "verilog" / "spwlink_tb_all.v"

STIMULUS_MARKERS = {
    "reset_idle_assertions": ("Test 1: Reset", "reset"),
    "started_null_generation": ("Test 4: Start link", "NULL"),
    "started_timeout": ("Test 5: Timeout in Started state", "started_timeout"),
    "connecting_fct_generation": ("Test 6: Start link; simulate NULL pattern", "FCT"),
    "connecting_timeout": ("Test 7: Timeout in Connecting state", "connecting_timeout"),
    "autostart_to_run": ("Test 8: Autostart link", "autostart"),
    "link_disable": ("Test 8: Autostart link", "link disable"),
    "running_disconnect_error": ("Test 9: Start link until Run state", "errdisc"),
    "junk_signal_filtering": ("Test 10: Junk signal before starting link", "junk signal"),
    "unexpected_eop_reset": ("Test 11: Incoming EOP before first FCT", "unexpected EOP"),
    "timecode_and_data_receive": ("Test 12: Send and receive characters", "TimeCode"),
    "double_escape_error": ("Test 12: Send and receive characters", "erresc"),
    "eop_eep_receive": ("Test 13: Send and receive EOP, EEP", "eop, eep"),
    "credit_error": ("Test 13: Send and receive EOP, EEP", "errcred"),
    "parity_error": ("Test 14: Abort on parity error", "errpar"),
    "inverted_strobe_start": ("Test 15: start with wrong strobe polarity", "weird_strobe"),
    "data_strobe_both_high": ("Test 16: start with wrong data polarity", "weird_data"),
}


def scalar(value: str) -> str:
    value = value.strip()
    if value.startswith("8'd"):
        return value[3:]
    if value.endswith(".0"):
        return value[:-2]
    return value


def manifest_cases(text: str) -> list[tuple[str, str, str, str, str]]:
    cases: list[tuple[str, str, str, str, str]] = []
    in_cases = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == "cases:":
            in_cases = True
            continue
        if in_cases and stripped and not stripped.startswith("- ["):
            break
        if in_cases and stripped.startswith("- ["):
            fields = [field.strip() for field in stripped[3:-1].split(",")]
            case, rximpl, rxchunk, tximpl, txdiv = fields[:5]
            cases.append((case, rximpl, rxchunk, tximpl, txdiv))
    return cases


def verilog_cases(text: str) -> list[tuple[str, str, str, str, str]]:
    cases: list[tuple[str, str, str, str, str]] = []
    pattern = re.compile(
        r"\.TEST_ID\((?P<case>\d+)\).*?"
        r"\.RXIMPL\((?P<rximpl>\d+)\).*?"
        r"\.RXCHUNK\((?P<rxchunk>\d+)\).*?"
        r"\.TXIMPL\((?P<tximpl>\d+)\).*?"
        r"\.TX_CLOCK_DIV\((?P<txdiv>[^)]+)\)",
    )
    for match in pattern.finditer(text):
        rximpl = "fast" if match.group("rximpl") == "1" else "generic"
        tximpl = "fast" if match.group("tximpl") == "1" else "generic"
        cases.append((
            match.group("case"),
            rximpl,
            match.group("rxchunk"),
            tximpl,
            scalar(match.group("txdiv")),
        ))
    return cases


def main() -> int:
    manifest = MANIFEST.read_text()
    vhdl_tb = VHDL_TB.read_text()
    verilog_tb = VERILOG_TB.read_text()
    tb_all = VERILOG_TB_ALL.read_text()
    expected = manifest_cases(manifest)
    actual = verilog_cases(tb_all)

    ok = True
    if expected != actual:
        ok = False
        print("ERROR: Verilog spwlink_tb_all case matrix does not match manifest", file=sys.stderr)
        print(f"expected {len(expected)} cases: {expected}", file=sys.stderr)
        print(f"actual   {len(actual)} cases: {actual}", file=sys.stderr)

    required_markers = list(STIMULUS_MARKERS)
    missing = [marker for marker in required_markers if marker not in manifest]
    if missing:
        ok = False
        print(f"ERROR: manifest missing stimulus markers: {missing}", file=sys.stderr)

    missing_verilog_markers = [
        marker for marker in required_markers if marker not in verilog_tb
    ]
    if missing_verilog_markers:
        ok = False
        print(
            f"ERROR: Verilog spwlink bench missing stimulus markers: {missing_verilog_markers}",
            file=sys.stderr,
        )

    missing_vhdl_anchors = [
        marker
        for marker, anchors in STIMULUS_MARKERS.items()
        if not any(anchor in vhdl_tb for anchor in anchors)
    ]
    if missing_vhdl_anchors:
        ok = False
        print(
            f"ERROR: VHDL spwlink bench no longer contains anchors for: {missing_vhdl_anchors}",
            file=sys.stderr,
        )

    if "status: complete" not in manifest:
        ok = False
        print("ERROR: spwlink manifest must be marked complete", file=sys.stderr)
    if "class: stimulus-isomorphic" not in manifest:
        ok = False
        print("ERROR: spwlink bench classification must be stimulus-isomorphic", file=sys.stderr)
    if "verilog_spwlink_lightweight_stimulus" in manifest:
        ok = False
        print("ERROR: obsolete lightweight-stimulus waiver is still present", file=sys.stderr)
    if "self-loopback checks suitable for Icarus Verilog CI" in verilog_tb:
        ok = False
        print("ERROR: Verilog spwlink bench still declares lightweight self-loopback status", file=sys.stderr)

    if not ok:
        return 1

    print(
        "PASS: spwlink parity manifest matches Verilog "
        f"{len(actual)}-case stimulus-isomorphic configuration sweep"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
