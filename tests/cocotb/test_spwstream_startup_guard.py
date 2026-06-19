# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

"""Bug 20 regression: spwstream must reject a clock whose auto-derived startup
divider lands outside the SpaceWire 10 Mbit/s +/-10% handshake window.

This is an elaboration / time-0 guard (Verilog $display+$finish, VHDL concurrent
assert severity failure), so it is checked by directly elaborating spwstream with
a bad and a good clock rather than through the cocotb runtime."""

import shutil
import subprocess
from pathlib import Path

import pytest

from tests.cocotb.cocotb_runner import ROOT

# GHDL cannot override a real generic from the CLI, so the VHDL guard is driven
# through this integer-generic wrapper (sysfreq := real(sys_hz)).
VHDL_TB = Path(__file__).resolve().parent / "spwstream_startup_tb.vhd"


# Common substring of the guard message emitted by both language fronts.
GUARD_MSG = "SpaceWire 10 Mbit/s"

# 25 MHz has no integer divider inside [9, 11] Mbit/s: /2 = 12.5, /3 = 8.33.
NONCOMPLIANT_HZ = 25_000_000
# 20 MHz / 2 = exactly 10 Mbit/s.
COMPLIANT_HZ = 20_000_000


SPWSTREAM_VERILOG = [
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


SPWSTREAM_VHDL = [
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
]


have_icarus = shutil.which("iverilog") is not None and shutil.which("vvp") is not None
have_ghdl = shutil.which("ghdl") is not None


def _run_spwstream_verilog(tmp_path, sys_hz):
    """Elaborate+run spwstream as top with a given SYS_CLOCK_HZ; return sim output."""
    sim = tmp_path / "spwstream.vvp"
    sources = [str(ROOT / path) for path in SPWSTREAM_VERILOG]
    subprocess.run(
        [
            "iverilog", "-g2001", "-o", str(sim), "-s", "spwstream",
            f"-Pspwstream.SYS_CLOCK_HZ={sys_hz}",
            "-Pspwstream.TXIMPL=0",
            *sources,
        ],
        cwd=ROOT, check=True, capture_output=True, text=True,
    )
    proc = subprocess.run([shutil.which("vvp"), str(sim)], cwd=ROOT, capture_output=True, text=True)
    return proc.stdout + proc.stderr


def _run_spwstream_vhdl(tmp_path, sys_hz):
    """Analyze+elaborate+run the spwstream startup harness with a given clock;
    return (rc, output). Uses an integer-generic TB because GHDL cannot override
    a real generic from the command line."""
    # Run in tmp_path: GHDL writes the elaborated executable and e~*.o to the CWD
    # regardless of --workdir, so keep that out of the repo tree. Sources are
    # passed as absolute paths.
    for path in [*(str(ROOT / p) for p in SPWSTREAM_VHDL), str(VHDL_TB)]:
        subprocess.run(
            ["ghdl", "-a", "--std=08", path],
            cwd=tmp_path, check=True, capture_output=True, text=True,
        )
    proc = subprocess.run(
        [
            "ghdl", "--elab-run", "--std=08", "spwstream_startup_tb",
            f"-gsys_hz={sys_hz}", "--stop-time=1ns",
        ],
        cwd=tmp_path, capture_output=True, text=True,
    )
    return proc.returncode, proc.stdout + proc.stderr


@pytest.mark.skipif(not have_icarus, reason="iverilog/vvp not on PATH")
def test_spwstream_rejects_noncompliant_startup_rate_verilog(tmp_path):
    assert GUARD_MSG in _run_spwstream_verilog(tmp_path, NONCOMPLIANT_HZ)


@pytest.mark.skipif(not have_icarus, reason="iverilog/vvp not on PATH")
def test_spwstream_accepts_compliant_startup_rate_verilog(tmp_path):
    assert GUARD_MSG not in _run_spwstream_verilog(tmp_path, COMPLIANT_HZ)


@pytest.mark.skipif(not have_ghdl, reason="ghdl not on PATH")
def test_spwstream_rejects_noncompliant_startup_rate_vhdl(tmp_path):
    rc, out = _run_spwstream_vhdl(tmp_path, NONCOMPLIANT_HZ)
    assert rc != 0, f"expected nonzero exit, got {rc}; output:\n{out}"
    assert GUARD_MSG in out


@pytest.mark.skipif(not have_ghdl, reason="ghdl not on PATH")
def test_spwstream_accepts_compliant_startup_rate_vhdl(tmp_path):
    rc, out = _run_spwstream_vhdl(tmp_path, COMPLIANT_HZ)
    assert rc == 0, f"expected clean run, got {rc}; output:\n{out}"
    assert GUARD_MSG not in out
