# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

import os
from pathlib import Path

import pytest

from tests.cocotb.cocotb_runner import ROOT, run_ghdl, run_icarus


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
]


SPWLINK_SWEEP_CASES = [
    {"id": 1, "sys": 20.0e6, "rx": 20.0e6, "tx": 20.0e6, "input": 10.0e6, "div": 1, "rximpl": 0, "rxchunk": 1, "tximpl": 0},
    {"id": 2, "sys": 20.0e6, "rx": 20.0e6, "tx": 20.0e6, "input": 18.0e6, "div": 1, "rximpl": 0, "rxchunk": 1, "tximpl": 0},
    {"id": 3, "sys": 20.0e6, "rx": 20.0e6, "tx": 20.0e6, "input": 2.0e6, "div": 1, "rximpl": 0, "rxchunk": 1, "tximpl": 0},
    {"id": 4, "sys": 20.0e6, "rx": 20.0e6, "tx": 20.0e6, "input": 10.0e6, "div": 0, "rximpl": 0, "rxchunk": 1, "tximpl": 0},
    {"id": 5, "sys": 20.0e6, "rx": 20.0e6, "tx": 20.0e6, "input": 10.0e6, "div": 1, "rximpl": 1, "rxchunk": 1, "tximpl": 0},
    {"id": 6, "sys": 20.0e6, "rx": 20.0e6, "tx": 20.0e6, "input": 18.0e6, "div": 1, "rximpl": 1, "rxchunk": 1, "tximpl": 0},
    {"id": 7, "sys": 20.0e6, "rx": 20.0e6, "tx": 20.0e6, "input": 35.0e6, "div": 1, "rximpl": 1, "rxchunk": 2, "tximpl": 0},
    {"id": 8, "sys": 20.0e6, "rx": 30.0e6, "tx": 20.0e6, "input": 55.0e6, "div": 1, "rximpl": 1, "rxchunk": 3, "tximpl": 0},
    {"id": 9, "sys": 20.0e6, "rx": 40.0e6, "tx": 20.0e6, "input": 75.0e6, "div": 1, "rximpl": 1, "rxchunk": 4, "tximpl": 0},
    {"id": 10, "sys": 20.0e6, "rx": 100.0e6, "tx": 20.0e6, "input": 75.0e6, "div": 1, "rximpl": 1, "rxchunk": 4, "tximpl": 0},
    {"id": 11, "sys": 20.0e6, "rx": 100.0e6, "tx": 20.0e6, "input": 2.0e6, "div": 1, "rximpl": 1, "rxchunk": 4, "tximpl": 0},
    {"id": 12, "sys": 20.0e6, "rx": 43.0e6, "tx": 20.0e6, "input": 67.13e6, "div": 1, "rximpl": 1, "rxchunk": 4, "tximpl": 0},
    {"id": 13, "sys": 20.0e6, "rx": 20.0e6, "tx": 39.0e6, "input": 10.0e6, "div": 1, "rximpl": 0, "rxchunk": 1, "tximpl": 1},
    {"id": 14, "sys": 20.0e6, "rx": 20.0e6, "tx": 39.0e6, "input": 10.0e6, "div": 0, "rximpl": 0, "rxchunk": 1, "tximpl": 1},
    {"id": 15, "sys": 20.0e6, "rx": 20.0e6, "tx": 80.0e6, "input": 10.0e6, "div": 0, "rximpl": 0, "rxchunk": 1, "tximpl": 1},
    {"id": 16, "sys": 20.0e6, "rx": 20.0e6, "tx": 20.0e6, "input": 10.0e6, "div": 2, "rximpl": 0, "rxchunk": 1, "tximpl": 1},
    {"id": 17, "sys": 20.0e6, "rx": 20.0e6, "tx": 80.0e6, "input": 10.0e6, "div": 3, "rximpl": 0, "rxchunk": 1, "tximpl": 1},
    {"id": 18, "sys": 20.0e6, "rx": 20.0e6, "tx": 80.0e6, "input": 10.0e6, "div": 4, "rximpl": 0, "rxchunk": 1, "tximpl": 1},
    {"id": 19, "sys": 20.0e6, "rx": 20.0e6, "tx": 80.0e6, "input": 10.0e6, "div": 39, "rximpl": 0, "rxchunk": 1, "tximpl": 1},
    {"id": 20, "sys": 50.0e6, "rx": 50.0e6, "tx": 200.0e6, "input": 10.0e6, "div": 96, "rximpl": 0, "rxchunk": 1, "tximpl": 1},
    {"id": 21, "sys": 20.0e6, "rx": 20.0e6, "tx": 78.5e6, "input": 10.0e6, "div": 1, "rximpl": 0, "rxchunk": 1, "tximpl": 1},
    {"id": 22, "sys": 20.0e6, "rx": 43.0e6, "tx": 78.5e6, "input": 67.13e6, "div": 0, "rximpl": 1, "rxchunk": 4, "tximpl": 1},
    {"id": 23, "sys": 20.0e6, "rx": 43.0e6, "tx": 77.5e6, "input": 67.13e6, "div": 1, "rximpl": 1, "rxchunk": 4, "tximpl": 1},
]

TX_ONLY_SPWLINK_CASE_IDS = {14, 15, 21}
# The original VHDL bench drives RX from an independent SpaceWire stimulus
# generator and monitors TX separately. These three high-speed transmitter
# cases are valid there, but a physical loopback would also require the
# configured RX front end to sample the generated TX bit rate.
LOOPBACK_SWEEP_CASES = [case for case in SPWLINK_SWEEP_CASES if case["id"] not in TX_ONLY_SPWLINK_CASE_IDS]
STARTUP_RATE_CASE_IDS = {1, 14, 20, 21}


def sweep_env(case):
    return {
        "SPW_SWEEP_CASE": str(case["id"]),
        "SPW_SYS_CLOCK_FREQ": str(case["sys"]),
        "SPW_RX_CLOCK_FREQ": str(case["rx"]),
        "SPW_TX_CLOCK_FREQ": str(case["tx"]),
        "SPW_INPUT_RATE": str(case["input"]),
        "SPW_TX_CLOCK_DIV": str(case["div"]),
        "SPW_RXIMPL": str(case["rximpl"]),
        "SPW_TXIMPL": str(case["tximpl"]),
        "SPW_RXCHUNK": str(case["rxchunk"]),
    }


def verilog_sweep_parameters(case):
    return {
        "SYS_CLOCK_HZ": int(case["sys"]),
        "TX_CLOCK_HZ": int(case["tx"]),
        "RXIMPL": case["rximpl"],
        "TXIMPL": case["tximpl"],
        "RXCHUNK": case["rxchunk"],
    }


def verilog_tx_only_parameters(case):
    params = verilog_sweep_parameters(case)
    params["LOOPBACK"] = 0
    return params


def verilog_no_loopback_parameters(case):
    params = verilog_sweep_parameters(case)
    params["LOOPBACK"] = 0
    return params


def vhdl_sweep_generics(case):
    return {
        "SYS_CLOCK_HZ": int(case["sys"]),
        "RX_CLOCK_HZ": int(case["rx"]),
        "TX_CLOCK_HZ": int(case["tx"]),
        "RXIMPL_SELECT": case["rximpl"],
        "TXIMPL_SELECT": case["tximpl"],
        "RXCHUNK_VALUE": case["rxchunk"],
    }


def vhdl_tx_only_generics(case):
    generics = vhdl_sweep_generics(case)
    generics["LOOPBACK_ENABLE"] = 0
    return generics


def vhdl_no_loopback_generics(case):
    generics = vhdl_sweep_generics(case)
    generics["LOOPBACK_ENABLE"] = 0
    return generics


def verilog_external_line_parameters():
    params = verilog_sweep_parameters(SPWLINK_SWEEP_CASES[0])
    params["LOOPBACK"] = 0
    return params


def vhdl_external_line_generics():
    generics = vhdl_sweep_generics(SPWLINK_SWEEP_CASES[0])
    generics["LOOPBACK_ENABLE"] = 0
    return generics


def test_spw_axi_top_loopback_verilog():
    test_dir = Path(__file__).resolve().parent
    run_icarus(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_cocotb",
        verilog_sources=[*(ROOT / path for path in VERILOG_RTL), test_dir / "spw_axi_top_loop_tb.v"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axi_top_loop_verilog",
    )


def test_spw_axi_top_strict_timecodes_verilog():
    test_dir = Path(__file__).resolve().parent
    run_icarus(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_strict_tc_cocotb",
        verilog_sources=[*(ROOT / path for path in VERILOG_RTL), test_dir / "spw_axi_top_loop_tb.v"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axi_top_strict_tc_verilog",
        parameters={"STRICT_TIMECODES": 1},
    )


@pytest.mark.parametrize("case", LOOPBACK_SWEEP_CASES, ids=lambda case: f"spwlink{case['id']:02d}")
def test_spw_axi_top_spwlink_sweep_verilog(case):
    test_dir = Path(__file__).resolve().parent
    run_icarus(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_sweep_cocotb",
        verilog_sources=[*(ROOT / path for path in VERILOG_RTL), test_dir / "spw_axi_top_loop_tb.v"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / f"spw_axi_top_sweep_verilog_{case['id']:02d}",
        parameters=verilog_sweep_parameters(case),
        extra_env=sweep_env(case),
    )


@pytest.mark.parametrize(
    "case",
    [case for case in SPWLINK_SWEEP_CASES if case["id"] in TX_ONLY_SPWLINK_CASE_IDS],
    ids=lambda case: f"spwlink{case['id']:02d}",
)
def test_spw_axi_top_spwlink_tx_only_verilog(case):
    test_dir = Path(__file__).resolve().parent
    run_icarus(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_line_cocotb",
        verilog_sources=[*(ROOT / path for path in VERILOG_RTL), test_dir / "spw_axi_top_loop_tb.v"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / f"spw_axi_top_tx_only_verilog_{case['id']:02d}",
        parameters=verilog_tx_only_parameters(case),
        extra_env=sweep_env(case),
        test_filter="axi_top_tx_only_case_uses_external_spacewire_line_driver",
    )


@pytest.mark.parametrize(
    "case",
    [case for case in SPWLINK_SWEEP_CASES if case["id"] in STARTUP_RATE_CASE_IDS],
    ids=lambda case: f"spwlink{case['id']:02d}",
)
def test_spw_axi_top_spwlink_startup_rate_verilog(case):
    test_dir = Path(__file__).resolve().parent
    run_icarus(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_line_cocotb",
        verilog_sources=[*(ROOT / path for path in VERILOG_RTL), test_dir / "spw_axi_top_loop_tb.v"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / f"spw_axi_top_startup_rate_verilog_{case['id']:02d}",
        parameters=verilog_no_loopback_parameters(case),
        extra_env=sweep_env(case),
        test_filter="axi_top_startup_signals_at_10mbps_before_run",
    )


def test_spw_axi_top_external_line_errors_verilog():
    test_dir = Path(__file__).resolve().parent
    run_icarus(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_line_cocotb",
        verilog_sources=[*(ROOT / path for path in VERILOG_RTL), test_dir / "spw_axi_top_loop_tb.v"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axi_top_external_line_errors_verilog",
        parameters=verilog_external_line_parameters(),
        extra_env=sweep_env(SPWLINK_SWEEP_CASES[0]),
        test_filter="axi_top_external_line_.*",
    )


@pytest.mark.skipif(
    os.environ.get("SPW_RUN_VHDL_COCOTB") != "1",
    reason="VHDL cocotb tests are enabled by build.py test --hdl vhdl/all",
)
def test_spw_axi_top_loopback_vhdl():
    test_dir = Path(__file__).resolve().parent
    run_ghdl(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_cocotb",
        vhdl_sources=[*(ROOT / path for path in VHDL_RTL), test_dir / "spw_axi_top_loop_tb.vhd"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axi_top_loop_vhdl",
    )


@pytest.mark.skipif(
    os.environ.get("SPW_RUN_VHDL_COCOTB") != "1",
    reason="VHDL cocotb tests are enabled by build.py test --hdl vhdl/all",
)
def test_spw_axi_top_strict_timecodes_vhdl():
    test_dir = Path(__file__).resolve().parent
    run_ghdl(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_strict_tc_cocotb",
        vhdl_sources=[*(ROOT / path for path in VHDL_RTL), test_dir / "spw_axi_top_loop_tb.vhd"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axi_top_strict_tc_vhdl",
        generics={"STRICT_TIMECODES": 1},
    )


@pytest.mark.skipif(
    os.environ.get("SPW_RUN_VHDL_COCOTB") != "1",
    reason="VHDL cocotb tests are enabled by build.py test --hdl vhdl/all",
)
@pytest.mark.parametrize("case", LOOPBACK_SWEEP_CASES, ids=lambda case: f"spwlink{case['id']:02d}")
def test_spw_axi_top_spwlink_sweep_vhdl(case):
    test_dir = Path(__file__).resolve().parent
    run_ghdl(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_sweep_cocotb",
        vhdl_sources=[*(ROOT / path for path in VHDL_RTL), test_dir / "spw_axi_top_loop_tb.vhd"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / f"spw_axi_top_sweep_vhdl_{case['id']:02d}",
        generics=vhdl_sweep_generics(case),
        extra_env=sweep_env(case),
    )


@pytest.mark.skipif(
    os.environ.get("SPW_RUN_VHDL_COCOTB") != "1",
    reason="VHDL cocotb tests are enabled by build.py test --hdl vhdl/all",
)
@pytest.mark.parametrize(
    "case",
    [case for case in SPWLINK_SWEEP_CASES if case["id"] in TX_ONLY_SPWLINK_CASE_IDS],
    ids=lambda case: f"spwlink{case['id']:02d}",
)
def test_spw_axi_top_spwlink_tx_only_vhdl(case):
    test_dir = Path(__file__).resolve().parent
    run_ghdl(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_line_cocotb",
        vhdl_sources=[*(ROOT / path for path in VHDL_RTL), test_dir / "spw_axi_top_loop_tb.vhd"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / f"spw_axi_top_tx_only_vhdl_{case['id']:02d}",
        generics=vhdl_tx_only_generics(case),
        extra_env=sweep_env(case),
        test_filter="axi_top_tx_only_case_uses_external_spacewire_line_driver",
    )


@pytest.mark.skipif(
    os.environ.get("SPW_RUN_VHDL_COCOTB") != "1",
    reason="VHDL cocotb tests are enabled by build.py test --hdl vhdl/all",
)
@pytest.mark.parametrize(
    "case",
    [case for case in SPWLINK_SWEEP_CASES if case["id"] in STARTUP_RATE_CASE_IDS],
    ids=lambda case: f"spwlink{case['id']:02d}",
)
def test_spw_axi_top_spwlink_startup_rate_vhdl(case):
    test_dir = Path(__file__).resolve().parent
    run_ghdl(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_line_cocotb",
        vhdl_sources=[*(ROOT / path for path in VHDL_RTL), test_dir / "spw_axi_top_loop_tb.vhd"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / f"spw_axi_top_startup_rate_vhdl_{case['id']:02d}",
        generics=vhdl_no_loopback_generics(case),
        extra_env=sweep_env(case),
        test_filter="axi_top_startup_signals_at_10mbps_before_run",
    )


@pytest.mark.skipif(
    os.environ.get("SPW_RUN_VHDL_COCOTB") != "1",
    reason="VHDL cocotb tests are enabled by build.py test --hdl vhdl/all",
)
def test_spw_axi_top_external_line_errors_vhdl():
    test_dir = Path(__file__).resolve().parent
    run_ghdl(
        top="spw_axi_top_loop_tb",
        test_module="spw_axi_top_line_cocotb",
        vhdl_sources=[*(ROOT / path for path in VHDL_RTL), test_dir / "spw_axi_top_loop_tb.vhd"],
        test_dir=test_dir,
        build_dir=ROOT / "build" / "cocotb" / "spw_axi_top_external_line_errors_vhdl",
        generics=vhdl_external_line_generics(),
        extra_env=sweep_env(SPWLINK_SWEEP_CASES[0]),
        test_filter="axi_top_external_line_.*",
    )
