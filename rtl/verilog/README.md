SpaceWire Light Verilog 2001 translation RTL
=================================

Author: Leonardo Capossio - bard0 design - hello@bard0.com

This directory contains a Verilog 2001 translation of the standalone
SpaceWire Light core.

Scope
-----

Translated here:
 * spwram
 * syncdff
 * spwlink
 * spwxmit
 * spwrecv
 * spwrecvfront_generic
 * spwrecvfront_fast
 * spwxmit_fast
 * spwstream
 * streamtest

Translated Verilog benches:
 * spwlink_tb
 * spwlink_tb_all
 * spwstream_smoke_tb
 * spwstream_fast_smoke_tb
 * spwstream_loopback_tb
 * streamtest_tb

Related synthesis/regression support:
 * `syn/vhdl/spwstream_synth_wrappers.vhd` provides matching generic and
   fast VHDL synthesis tops for comparison against the Verilog `spwstream`
   configurations.
 * `scripts/synth_resource_compare.py` emits VHDL-derived Verilog netlists
   with GHDL, synthesizes both the handwritten Verilog and VHDL-derived
   netlists with Yosys, and prints a resource comparison table.
 * `.github/workflows/verilog.yml` runs Verilog lint, translated Verilog
   benches, original VHDL parity benches, and the synthesis resource
   comparison in CI.

Intentionally not translated here:
 * spwamba
 * spwambapkg
 * spwahbmst
 * LEON3/GRLIB-dependent synthesis and simulation wrappers

Interface note
--------------

The original VHDL uses package record types for link, receiver and
transmitter buses. Verilog 2001 has no equivalent struct type, so the
translated modules use flattened ports with names matching the original
record fields.

The VHDL top-level generics `sysfreq` and `txclkfreq` are real-valued.
The Verilog 2001 translation uses precomputed integer parameters instead:
`RESET_TIME`, `DISCONNECT_TIME` and `DEFAULT_DIVCNT`.

License
-------

The translated standalone Verilog RTL and benches carry:

 * `SPDX-License-Identifier: LGPL-2.1-or-later`
 * Original copyright: `Copyright (C) 2009-2013 Joris van Rantwijk`
 * Translation copyright: `Copyright (C) 2026 Leonardo Capossio - bard0 design`

Author: Leonardo Capossio - bard0 design - hello@bard0.com.

This translation is a modified form of SpaceWire Light. Keep the original
copyright and license terms from the repository root when distributing it.
