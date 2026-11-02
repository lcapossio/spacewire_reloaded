# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""Pytest entry point for the DE25-Nano board-level sim (Icarus / GHDL).

Simulates the real DE25-Nano top-level with the vendor reset-release wrapper
replaced by its behavioral stub, so it runs without Quartus.
"""

import os
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tests.cocotb.cocotb_runner import run_ghdl, run_icarus  # noqa: E402

RTL = [
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
    "examples/arty_a7100t/rtl/spw_loopback_axi.v",
    "examples/de25_nano/tb/de25_reset_release_sim.v",
    "examples/de25_nano/tb/de25_debug_sim.v",
    "examples/de25_nano/rtl/spw_de25_nano_top.v",
]

VHDL_RTL = [
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
    "rtl/vhdl/spw_axis_tx.vhd",
    "rtl/vhdl/spw_axis_rx.vhd",
    "rtl/vhdl/spw_axi_lite_regs.vhd",
    "rtl/vhdl/spw_axi_top.vhd",
    "examples/arty_a7100t/rtl/spw_loopback_axi.vhd",
    "examples/de25_nano/tb/de25_reset_release_sim.vhd",
    "examples/de25_nano/tb/de25_debug_sim.vhd",
    "examples/de25_nano/rtl/spw_de25_nano_top.vhd",
]


def test_spw_de25_nano_verilog():
    test_dir = Path(__file__).resolve().parent
    run_icarus(
        top="spw_de25_nano_top",
        test_module="de25_nano_cocotb",
        verilog_sources=[ROOT / p for p in RTL],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_de25_nano_verilog",
    )


@pytest.mark.skipif(
    os.environ.get("SPW_RUN_VHDL_COCOTB") != "1",
    reason="VHDL cocotb tests are enabled by build.py test --hdl vhdl/all",
)
def test_spw_de25_nano_vhdl():
    test_dir = Path(__file__).resolve().parent
    run_ghdl(
        top="spw_de25_nano_top",
        test_module="de25_nano_cocotb",
        vhdl_sources=[ROOT / p for p in VHDL_RTL],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_de25_nano_vhdl",
    )
