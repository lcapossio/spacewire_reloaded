# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# SpaceWire Reloaded - clock-domain-crossing timing constraints (Lattice).
#
# For Lattice Radiant and Diamond/Synplify Pro SDC-based timing. Companion to
# constraints/spw_cdc.xdc; see that file for the full rationale. All crossings
# go through the "syncdff" synchronizer, whose flip-flops carry the Synplify
# syn_preserve / syn_srlstyle attributes in the RTL. The receive head pointer is
# gray-coded before crossing, so these constraints bound skew/latency rather
# than provide correctness.
#
# Usage: add this .sdc to the Radiant/Diamond project AFTER the three core
# clocks (clk, rxclk, txclk) are created. No clocks are created here and there
# are no absolute paths. Verify the cell-name pattern against your tool's post-
# synthesis netlist (hierarchy separator and *_reg suffixes vary by version).

# Maximum allowed delay on a crossing data path, in nanoseconds. Set to the
# period of the fastest clock that takes part in a crossing (clk, rxclk, txclk).
set spw_cdc_max_delay_ns 5.000

# First-stage flip-flop of every syncdff instance.
set spw_sync_ff1 [get_cells {*syncdff_ff1*}]

if {[llength $spw_sync_ff1] > 0} {
    # Bound the asynchronous crossing into each synchronizer input.
    set_max_delay -from [all_registers] -to $spw_sync_ff1 $spw_cdc_max_delay_ns

    # Alternative if you prefer to cut the crossing entirely (safe here because
    # the head pointer is gray-coded and bitcnt is change-detected only):
    # set_false_path -to $spw_sync_ff1
} else {
    puts "WARNING: spw_cdc_lattice.sdc found no syncdff_ff1 cells; check instance names."
}
