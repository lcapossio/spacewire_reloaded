# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

"""Bug 23 regression: the Verilog cores must reject out-of-range parameters with
an intentional diagnostic, matching the VHDL constrained generics (rxchunk 1..4,
rxfifosize_bits 6..14, txfifosize_bits 2..14, impl enums, tickdiv 12..24).

These are elaboration/time-0 guards ($display + $finish), so each invalid value
is checked by elaborating the module as top and confirming the guard message
appears. (VHDL already enforces these through subtype-constrained generics, so no
VHDL guard is added.)"""

import shutil
import subprocess

import pytest

from tests.cocotb.cocotb_runner import ROOT


have_icarus = shutil.which("iverilog") is not None and shutil.which("vvp") is not None


SPWSTREAM_SRCS = [
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

STREAMTEST_SRCS = [*SPWSTREAM_SRCS, "rtl/verilog/streamtest.v"]

AXITOP_SRCS = [
    *SPWSTREAM_SRCS,
    "rtl/verilog/spw_axis_tx.v",
    "rtl/verilog/spw_axis_rx.v",
    "rtl/verilog/spw_axi_lite_regs.v",
    "rtl/verilog/spw_axi_top.v",
]


def _elaborate_and_run(tmp_path, top, sources, params):
    """Elaborate `top` with parameter overrides and run it; return combined
    output. Returns the iverilog error text if elaboration itself fails."""
    sim = tmp_path / f"{top}.vvp"
    pargs = [f"-P{top}.{name}={value}" for name, value in params.items()]
    build = subprocess.run(
        ["iverilog", "-g2001", "-o", str(sim), "-s", top,
         *pargs, *(str(ROOT / s) for s in sources)],
        cwd=ROOT, capture_output=True, text=True,
    )
    if build.returncode != 0:
        return "ELABORATION FAILED:\n" + build.stdout + build.stderr
    run = subprocess.run([shutil.which("vvp"), str(sim)], cwd=ROOT, capture_output=True, text=True)
    return run.stdout + run.stderr


SPWSTREAM_BAD = [
    ({"RXIMPL": 2}, "RXIMPL must be"),
    ({"TXIMPL": 2}, "TXIMPL must be"),
    ({"RXCHUNK": 0}, "RXCHUNK must be"),
    ({"RXCHUNK": 5}, "RXCHUNK must be"),
    ({"RXFIFOSIZE_BITS": 5}, "RXFIFOSIZE_BITS must be"),
    ({"RXFIFOSIZE_BITS": 15}, "RXFIFOSIZE_BITS must be"),
    ({"TXFIFOSIZE_BITS": 1}, "TXFIFOSIZE_BITS must be"),
    ({"TXFIFOSIZE_BITS": 15}, "TXFIFOSIZE_BITS must be"),
]


@pytest.mark.skipif(not have_icarus, reason="iverilog/vvp not on PATH")
@pytest.mark.parametrize(
    "params,msg", SPWSTREAM_BAD,
    ids=[f"{list(p)[0]}={list(p.values())[0]}" for p, _ in SPWSTREAM_BAD],
)
def test_spwstream_rejects_invalid_param(tmp_path, params, msg):
    out = _elaborate_and_run(tmp_path, "spwstream", SPWSTREAM_SRCS, params)
    assert msg in out, out


@pytest.mark.skipif(not have_icarus, reason="iverilog/vvp not on PATH")
def test_spwstream_valid_params_clean(tmp_path):
    out = _elaborate_and_run(tmp_path, "spwstream", SPWSTREAM_SRCS, {})
    assert "must be" not in out, out


@pytest.mark.skipif(not have_icarus, reason="iverilog/vvp not on PATH")
@pytest.mark.parametrize("tickdiv", [11, 25])
def test_streamtest_rejects_invalid_tickdiv(tmp_path, tickdiv):
    out = _elaborate_and_run(tmp_path, "streamtest", STREAMTEST_SRCS, {"TICKDIV": tickdiv})
    assert "TICKDIV must be" in out, out


@pytest.mark.skipif(not have_icarus, reason="iverilog/vvp not on PATH")
def test_spw_axi_top_rejects_invalid_param(tmp_path):
    out = _elaborate_and_run(tmp_path, "spw_axi_top", AXITOP_SRCS, {"RXCHUNK": 5})
    assert "RXCHUNK must be" in out, out
