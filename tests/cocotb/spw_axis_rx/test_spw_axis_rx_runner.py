# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

from pathlib import Path

from tests.cocotb.cocotb_runner import ROOT, run_icarus


def test_spw_axis_rx_verilog():
    test_dir = Path(__file__).resolve().parent
    run_icarus(
        top="spw_axis_rx",
        test_module="spw_axis_rx_cocotb",
        verilog_sources=[ROOT / "rtl" / "verilog" / "spw_axis_rx.v"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axis_rx_verilog",
    )
