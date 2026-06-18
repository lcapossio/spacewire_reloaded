# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

from __future__ import annotations

import os
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections.abc import MutableMapping
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


def cocotb_vpi_module(simulator: str) -> str:
    """The VPI module name to pass to ``vvp -m``. cocotb names it differently per
    platform (``cocotbvpi_icarus`` on Windows, ``libcocotbvpi_icarus`` on Linux),
    so ask cocotb rather than hardcoding it."""
    result = subprocess.run(
        ["cocotb-config", "--lib-name", "vpi", simulator],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    return result.stdout.strip()


def ghdl_vpi_lib_dir() -> str:
    result = subprocess.run(
        ["ghdl", "--vpi-library-dir"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=True,
    )
    return result.stdout.strip()


def ghdl_dll_dirs() -> list[str]:
    paths = [ghdl_vpi_lib_dir()]
    ghdl_exe = shutil.which("ghdl")
    if ghdl_exe is not None:
        paths.append(str(Path(ghdl_exe).resolve().parent))
    return paths


def prepend_env_path(env: MutableMapping[str, str], paths: list[str]) -> str:
    path_key = next((key for key in env if key.lower() == "path"), "PATH")
    env[path_key] = os.pathsep.join([*paths, env.get(path_key, "")])
    return path_key


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
    extra_env: dict[str, str] | None = None,
    test_filter: str | None = None,
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
    env.update(extra_env or {})
    if test_filter is not None:
        env["COCOTB_TEST_FILTER"] = test_filter
    results_file = build_dir / "results.xml"
    if results_file.exists():
        results_file.unlink()
    env["COCOTB_RESULTS_FILE"] = str(results_file)

    run(
        ["vvp", "-M", cocotb_lib_dir(), "-m", cocotb_vpi_module("icarus"), str(sim_file)],
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
    generics: dict[str, object] | None = None,
    extra_env: dict[str, str] | None = None,
    test_filter: str | None = None,
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
    env.update(extra_env or {})
    python_dir = str(Path(sys.executable).resolve().parent)
    dll_paths = [cocotb_lib_dir(), *ghdl_dll_dirs(), python_dir]
    prepend_env_path(env, dll_paths)
    process_path_key = next((key for key in os.environ if key.lower() == "path"), "PATH")
    old_process_path = os.environ.get(process_path_key)
    prepend_env_path(os.environ, dll_paths)
    try:
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
            test_filter=test_filter,
            extra_env=env,
        )
    finally:
        if old_process_path is None:
            os.environ.pop(process_path_key, None)
        else:
            os.environ[process_path_key] = old_process_path

    parse_cocotb_results(results_file)
