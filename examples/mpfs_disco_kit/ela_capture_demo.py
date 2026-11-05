#!/usr/bin/env python3
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
"""fpgacapZero ELA capture of the live SpaceWire link on the Discovery Kit.

Runs the Arty example's capture demo (examples/arty_a7100t/ela_capture_demo.py)
over the PolarFire SoC Discovery Kit's embedded FlashPro5 (fcapz ``ftdi``
backend). The ELA (UJTAG chain 1, core manager slot 0, see
rtl/microchip/mpfs_debug.v) samples 16 bits at 50 MHz: bits [7:0] are the same
D/S + status byte as on the Arty board, bits [15:8] the received N-Char byte.
At 10 Mbit/s each SpaceWire bit is ~5 samples wide.

The board must already be programmed (``python build.py libero --program``):

    python examples/mpfs_disco_kit/ela_capture_demo.py

The waveform is written to build/mpfs_ela_capture.vcd (override with --vcd).
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "examples" / "arty_a7100t"))

import ela_capture_demo as common  # noqa: E402

MPFS_DEFAULTS = [
    "--backend", "ftdi", "--hardware", "Embedded FlashPro5 A", "--axi-chain", "2",
    "--ela-chain", "1", "--ela-instance", "0",
    "--sample-width", "16",
    "--vcd", str(ROOT / "build" / "mpfs_ela_capture.vcd"),
]


if __name__ == "__main__":
    (ROOT / "build").mkdir(exist_ok=True)
    raise SystemExit(common.main(MPFS_DEFAULTS + sys.argv[1:]))
