# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# SpaceWire Reloaded - clock-domain-crossing timing constraints (Xilinx Vivado).
#
# All clock-domain crossings in the core funnel through the two-flip-flop
# synchronizer "syncdff" (rxclk <-> clk in spwrecvfront_fast, clk <-> txclk in
# spwxmit_fast). The synchronizer flip-flops carry ASYNC_REG/keep attributes in
# the RTL, so this file only has to bound the data-path delay of the crossing.
#
# The receive head pointer is gray-coded before it crosses (see
# spwrecvfront_fast), so correctness does not depend on these constraints; they
# bound skew/latency and stop the tool from timing the (asynchronous) crossing
# against the launch clock. The activity counter "bitcnt" crosses as binary but
# is change-detected only and tolerates a transient mismatch.
#
# Usage: read this file into the Vivado project AFTER the three core clocks
# (clk, rxclk, txclk) have been created by the board/project constraints or by
# the clocking IP. This file does not create clocks and contains no absolute
# paths.

# Maximum allowed delay on a crossing data path, in nanoseconds. Set this to the
# period of the FASTEST clock that takes part in a crossing (clk, rxclk or
# txclk), which conservatively bounds the path to under one capture period.
set spw_cdc_max_delay_ns 5.000

# First-stage flip-flop of every syncdff instance (the crossing endpoint).
set spw_sync_ff1 [get_cells -hierarchical -filter {NAME =~ *syncdff_ff1*}]

if {[llength $spw_sync_ff1] > 0} {
    # Bound the asynchronous crossing into each synchronizer input. -datapath_only
    # drops the launch/capture clock relationship and constrains only routing+logic.
    set_max_delay -datapath_only \
        -to [get_pins -of_objects $spw_sync_ff1 -filter {REF_PIN_NAME == D}] \
        $spw_cdc_max_delay_ns

    # Optional, recommended for the gray-coded head-pointer bus: also bound the
    # bit-to-bit skew so the three gray bits land within one destination period.
    # Uncomment and group the headptr synchronizers if your tool version supports it:
    # set_bus_skew \
    #     -to [get_pins -of_objects \
    #         [get_cells -hierarchical -filter {NAME =~ *syncsys_headptr*syncdff_ff1*}] \
    #         -filter {REF_PIN_NAME == D}] \
    #     $spw_cdc_max_delay_ns
} else {
    puts "WARNING: spw_cdc.xdc found no syncdff_ff1 cells; check the instance names."
}
