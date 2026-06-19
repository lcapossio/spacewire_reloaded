# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import os
from pathlib import Path

import pytest

from tests.cocotb.cocotb_runner import ROOT, run_ghdl, run_icarus


def test_spw_axi_lite_regs_verilog():
    test_dir = Path(__file__).resolve().parent
    run_icarus(
        top="spw_axi_lite_regs",
        test_module="spw_axi_lite_regs_cocotb",
        verilog_sources=[ROOT / "rtl" / "verilog" / "spw_axi_lite_regs.v"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axi_lite_regs_verilog",
    )


def test_spw_axi_lite_regs_wide_aperture_verilog():
    """Build with a 32-bit AXI address bus and probe high addresses to confirm
    the range check is robust for wide apertures (Bug 21 follow-up)."""
    test_dir = Path(__file__).resolve().parent
    run_icarus(
        top="spw_axi_lite_regs",
        test_module="spw_axi_lite_regs_cocotb",
        verilog_sources=[ROOT / "rtl" / "verilog" / "spw_axi_lite_regs.v"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axi_lite_regs_wide_verilog",
        parameters={"ADDR_WIDTH": 32},
        test_filter="axi_lite_high_address_reads_zero_on_wide_aperture",
    )


@pytest.mark.skipif(
    os.environ.get("SPW_RUN_VHDL_COCOTB") != "1",
    reason="VHDL cocotb tests are enabled by build.py test --hdl vhdl/all",
)
def test_spw_axi_lite_regs_vhdl():
    test_dir = Path(__file__).resolve().parent
    run_ghdl(
        top="spw_axi_lite_regs",
        test_module="spw_axi_lite_regs_cocotb",
        vhdl_sources=[ROOT / "rtl" / "vhdl" / "spw_axi_lite_regs.vhd"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axi_lite_regs_vhdl",
    )


@pytest.mark.skipif(
    os.environ.get("SPW_RUN_VHDL_COCOTB") != "1",
    reason="VHDL cocotb tests are enabled by build.py test --hdl vhdl/all",
)
def test_spw_axi_lite_regs_wide_aperture_vhdl():
    """Build with a 32-bit AXI address bus and probe high addresses to confirm
    the range check is robust for wide apertures (Bug 21 follow-up). Pre-fix this
    crashed GHDL via to_integer overflow on addresses >= 0x8000_0000."""
    test_dir = Path(__file__).resolve().parent
    run_ghdl(
        top="spw_axi_lite_regs",
        test_module="spw_axi_lite_regs_cocotb",
        vhdl_sources=[ROOT / "rtl" / "vhdl" / "spw_axi_lite_regs.vhd"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axi_lite_regs_wide_vhdl",
        generics={"ADDR_WIDTH": 32},
        test_filter="axi_lite_high_address_reads_zero_on_wide_aperture",
    )
