# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def require_tool(name: str) -> None:
    if shutil.which(name) is None:
        raise RuntimeError(f"required tool not found on PATH: {name}")


def run(args: list[str], *, cwd: Path, env: dict[str, str] | None = None) -> None:
    result = subprocess.run(args, cwd=cwd, env=env)
    if result.returncode != 0:
        raise RuntimeError(f"command failed with exit code {result.returncode}: {' '.join(args)}")


def cocotb_lib_dir() -> str:
    result = subprocess.run(
        ["cocotb-config", "--lib-dir"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    return result.stdout.strip()


def parse_cocotb_results(results_file: Path) -> None:
    if not results_file.exists():
        raise RuntimeError(f"cocotb did not write results file: {results_file}")

    results = ET.parse(results_file)
    failures = []
    for testcase in results.findall(".//testcase"):
        failure = testcase.find("failure")
        error = testcase.find("error")
        if failure is not None or error is not None:
            detail = failure if failure is not None else error
            failures.append(
                f"{testcase.get('classname')}.{testcase.get('name')}: "
                f"{detail.get('error_msg') or detail.text or 'failed'}"
            )
    if failures:
        raise RuntimeError("cocotb failures:\n" + "\n".join(failures))


def run_icarus(
    *,
    top: str,
    test_module: str,
    verilog_sources: list[Path],
    test_dir: Path,
    build_dir: Path,
    parameters: dict[str, str | int] | None = None,
) -> None:
    require_tool("iverilog")
    require_tool("vvp")
    require_tool("cocotb-config")

    build_dir.mkdir(parents=True, exist_ok=True)
    sim_file = build_dir / f"{top}.vvp"
    sources = [str(path) for path in verilog_sources]
    parameter_args = []
    for name, value in (parameters or {}).items():
        parameter_args.append(f"-P{top}.{name}={value}")

    run(
        ["iverilog", "-g2001", "-Wall", "-o", str(sim_file), "-s", top, *parameter_args, *sources],
        cwd=ROOT,
    )

    env = os.environ.copy()
    env["COCOTB_TOPLEVEL"] = top
    env["COCOTB_TEST_MODULES"] = test_module
    env["TOPLEVEL_LANG"] = "verilog"
    env["PYGPI_PYTHON_BIN"] = sys.executable
    env["PYTHONPATH"] = str(test_dir) + os.pathsep + env.get("PYTHONPATH", "")
    results_file = build_dir / "results.xml"
    if results_file.exists():
        results_file.unlink()
    env["COCOTB_RESULTS_FILE"] = str(results_file)

    run(
        ["vvp", "-M", cocotb_lib_dir(), "-m", "cocotbvpi_icarus", str(sim_file)],
        cwd=ROOT,
        env=env,
    )

    parse_cocotb_results(results_file)


def run_ghdl(
    *,
    top: str,
    test_module: str,
    vhdl_sources: list[Path],
    test_dir: Path,
    build_dir: Path,
    generics: dict[str, str | int] | None = None,
) -> None:
    require_tool("ghdl")
    require_tool("cocotb-config")

    from cocotb_tools.runner import get_runner

    build_dir.mkdir(parents=True, exist_ok=True)
    results_file = build_dir / "results.xml"
    if results_file.exists():
        results_file.unlink()

    runner = get_runner("ghdl")
    runner.build(
        hdl_library="top",
        sources=vhdl_sources,
        hdl_toplevel=top,
        build_dir=build_dir,
        build_args=["--std=08"],
        always=True,
    )

    env = os.environ.copy()
    env["PYTHONPATH"] = str(test_dir) + os.pathsep + env.get("PYTHONPATH", "")
    runner.test(
        test_module=test_module,
        hdl_toplevel=top,
        hdl_toplevel_library="top",
        hdl_toplevel_lang="vhdl",
        build_dir=build_dir,
        test_dir=build_dir,
        results_xml=str(results_file),
        test_args=["--std=08"],
        parameters=generics or {},
        extra_env=env,
    )

    parse_cocotb_results(results_file)
