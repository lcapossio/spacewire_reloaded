# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import os
from pathlib import Path

import pytest

from tests.cocotb.cocotb_runner import ROOT, run_ghdl, run_icarus


def test_spw_axis_tx_verilog():
    test_dir = Path(__file__).resolve().parent
    run_icarus(
        top="spw_axis_tx",
        test_module="spw_axis_tx_cocotb",
        verilog_sources=[ROOT / "rtl" / "verilog" / "spw_axis_tx.v"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axis_tx_verilog",
    )


@pytest.mark.skipif(
    os.environ.get("SPW_RUN_VHDL_COCOTB") != "1",
    reason="VHDL cocotb tests are enabled by build.py test --hdl vhdl/all",
)
def test_spw_axis_tx_vhdl():
    test_dir = Path(__file__).resolve().parent
    run_ghdl(
        top="spw_axis_tx",
        test_module="spw_axis_tx_cocotb",
        vhdl_sources=[ROOT / "rtl" / "vhdl" / "spw_axis_tx.vhd"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axis_tx_vhdl",
    )
