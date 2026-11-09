#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""fpgacapZero (fcapz) host verification of the Discovery Kit SpaceWire loopback.

Runs the same checks as the Arty A7-100T example
(examples/arty_a7100t/host_loopback_test.py) on the PolarFire SoC Discovery
Kit, directly over the board's embedded FlashPro5 (fcapz ``ftdi`` backend,
FTDI D2XX driver; no OpenOCD). Like the Arty flow (hw_server programs the
bitstream on connect), each run first programs the board through Libero, so
every check starts from a freshly configured design; build first:

    python build.py libero

Then:

    python examples/mpfs_disco_kit/host_loopback_test.py              # basic checks
    python examples/mpfs_disco_kit/host_loopback_test.py --inject     # error injection
    python examples/mpfs_disco_kit/host_loopback_test.py --timecode   # TimeCodes
    python examples/mpfs_disco_kit/host_loopback_test.py --eep        # EEP vs EOP
    python examples/mpfs_disco_kit/host_loopback_test.py --loadfault  # fault under load
    python examples/mpfs_disco_kit/host_loopback_test.py --stress 60  # PRBS soak

``--hdl`` selects the build to program (default verilog; the project is
libero/mpfs_disco_kit_<hdl>/), ``--no-program`` skips programming, and
``--libero-bin`` points at Libero's Designer/bin when ``libero`` is not on
PATH. All other options of the Arty script are accepted (``--hardware``
selects the FTDI channel, default: "Embedded FlashPro5 A").

UJTAG chain map (see rtl/microchip/mpfs_debug.v): chain 1 (IR 0x20) = fcapz
core manager, ELA in slot 0 and EIO in slot 1; chain 2 (IR 0x21) = EJTAG-AXI.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "examples" / "arty_a7100t"))

import host_loopback_test as common  # noqa: E402

# The embedded FlashPro5 enumerates its JTAG channel as "Embedded FlashPro5 A";
# naming it keeps other FTDI JTAG adapters (an Arty, say) out of the way.
MPFS_DEFAULTS = ["--backend", "ftdi", "--hardware", "Embedded FlashPro5 A",
                 "--axi-chain", "2", "--eio-chain", "1", "--eio-instance", "1"]


def program(hdl: str, libero_bin: str | None) -> None:
    """Program the board from the last full build (build.py --program-only)."""
    cmd = [sys.executable, str(HERE / "build.py"), "--hdl", hdl, "--program-only"]
    if libero_bin:
        cmd += ["--libero-bin", libero_bin]
    print(f"programming the {hdl} build ...", flush=True)
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(res.stdout + res.stderr, file=sys.stderr)
        raise SystemExit(f"ERROR: programming failed (exit {res.returncode})")


def main() -> int:
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--hdl", choices=("verilog", "vhdl"), default="verilog")
    p.add_argument("--no-program", action="store_true")
    p.add_argument("--libero-bin", default=None)
    own, rest = p.parse_known_args()
    if "-h" in rest or "--help" in rest:
        print(__doc__)
    elif not own.no_program:
        program(own.hdl, own.libero_bin)
    return common.main(MPFS_DEFAULTS + rest)


if __name__ == "__main__":
    raise SystemExit(main())
