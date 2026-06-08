# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

from __future__ import annotations

import os
import shutil
import subprocess
import sys
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

    run(
        ["vvp", "-M", cocotb_lib_dir(), "-m", "cocotbvpi_icarus", str(sim_file)],
        cwd=ROOT,
        env=env,
    )
