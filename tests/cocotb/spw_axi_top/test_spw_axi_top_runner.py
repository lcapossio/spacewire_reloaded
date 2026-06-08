# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

from pathlib import Path

from tests.cocotb.cocotb_runner import ROOT, run_icarus


VERILOG_RTL = [
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


def test_spw_axi_top_loopback_verilog():
    test_dir = Path(__file__).resolve().parent
    run_icarus(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_cocotb",
        verilog_sources=[*(ROOT / path for path in VERILOG_RTL), test_dir / "spw_axi_top_loop_tb.v"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axi_top_loop_verilog",
    )
