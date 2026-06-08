#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""Project build, lint, and regression entry point."""

from __future__ import annotations

import argparse
import importlib.util
import os
import platform
import shutil
import shlex
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def require_tool(name: str) -> None:
    if shutil.which(name) is None:
        raise SystemExit(f"ERROR: required tool not found on PATH: {name}")


def require_python_package(name: str) -> None:
    if importlib.util.find_spec(name) is None:
        raise SystemExit(f"ERROR: required Python package is not installed: {name}")


def run(args: list[str]) -> None:
    print("+ " + " ".join(args), flush=True)
    result = subprocess.run(args, cwd=ROOT)
    if result.returncode != 0:
        raise SystemExit(result.returncode)


def is_windows() -> bool:
    return platform.system().lower() == "windows"


def wsl_has_distro() -> bool:
    if not is_windows() or shutil.which("wsl") is None:
        return False
    result = subprocess.run(
        ["wsl", "-l", "-q"],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        return False
    return bool(result.stdout.replace("\x00", "").strip())


def wsl_repo_path() -> str:
    result = subprocess.run(
        ["wsl", "-e", "wslpath", "-a", str(ROOT)],
        cwd=ROOT,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        stderr = result.stderr.replace("\x00", "")
        raise SystemExit(f"ERROR: failed to convert repo path for WSL: {stderr.strip()}")
    return result.stdout.strip()


def run_test_wsl(args: argparse.Namespace) -> None:
    require_tool("wsl")
    if not wsl_has_distro():
        raise SystemExit("ERROR: WSL is installed but no WSL distribution is visible to this user")
    pytest_args = " -v" if args.verbose else ""
    command = f"cd {shlex.quote(wsl_repo_path())} && python3 build.py test --runner local{pytest_args}"
    run(["wsl", "-e", "bash", "-lc", command])


def cmd_lint(args: argparse.Namespace) -> None:
    lint_args = [sys.executable, "scripts/lint_hdl.py"]
    if args.vhdl:
        lint_args.append("--vhdl")
    if args.verilog:
        lint_args.append("--verilog")
    if args.skip_yosys:
        lint_args.append("--skip-yosys")
    run(lint_args)


def cmd_test(args: argparse.Namespace) -> None:
    if args.runner == "wsl" or (args.runner == "auto" and is_windows() and wsl_has_distro()):
        run_test_wsl(args)
        return

    require_tool("iverilog")
    require_tool("vvp")
    require_python_package("pytest")
    require_python_package("cocotb")
    require_python_package("cocotbext.axi")
    pytest_args = [sys.executable, "-m", "pytest", "tests/cocotb"]
    if args.verbose:
        pytest_args.append("-v")
    run(pytest_args)


def cmd_vivado(args: argparse.Namespace) -> None:
    if args.dry_run:
        print("Vivado flow is not implemented yet; dry run passed.")
        return
    raise SystemExit("ERROR: Vivado flow is not implemented yet")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    lint_parser = subparsers.add_parser("lint", help="run HDL lint checks")
    lint_parser.add_argument("--vhdl", action="store_true", help="run only VHDL lint")
    lint_parser.add_argument("--verilog", action="store_true", help="run only Verilog lint")
    lint_parser.add_argument("--skip-yosys", action="store_true", help="skip Yosys structural checks")
    lint_parser.set_defaults(func=cmd_lint)

    test_parser = subparsers.add_parser("test", help="run cocotb regressions")
    test_parser.add_argument(
        "--runner",
        choices=("auto", "local", "wsl"),
        default=os.environ.get("SPW_TEST_RUNNER", "auto"),
        help="choose where cocotb runs; auto prefers WSL on Windows when available",
    )
    test_parser.add_argument("-v", "--verbose", action="store_true", help="pass verbose output to pytest")
    test_parser.set_defaults(func=cmd_test)

    vivado_parser = subparsers.add_parser("vivado", help="run or check the Vivado build flow")
    vivado_parser.add_argument("--dry-run", action="store_true", help="check flow wiring without building")
    vivado_parser.set_defaults(func=cmd_vivado)

    args = parser.parse_args()
    if getattr(args, "vhdl", False) and getattr(args, "verilog", False):
        raise SystemExit("ERROR: choose at most one of --vhdl or --verilog")
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
