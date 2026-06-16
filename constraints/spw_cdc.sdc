# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# SpaceWire Reloaded - clock-domain-crossing timing constraints (Intel Quartus).
#
# Companion to constraints/spw_cdc.xdc; see that file for the full rationale.
# All crossings go through the "syncdff" two-flip-flop synchronizer, whose
# flip-flops carry the Quartus "preserve" attribute in the RTL so they survive
# synthesis with their names intact. The receive head pointer is gray-coded
# before crossing, so these constraints bound skew/latency rather than provide
# correctness.
#
# Usage: add this .sdc to the Quartus project (Assignments -> Settings -> Timing
# Analyzer) AFTER the three core clocks (clk, rxclk, txclk) are created. No
# clocks are created here and there are no absolute paths.

# Maximum allowed delay/skew on a crossing data path, in nanoseconds. Set to the
# period of the fastest clock that takes part in a crossing (clk, rxclk, txclk).
set spw_cdc_max_delay_ns 5.000

# First-stage flip-flop of every syncdff instance.
set spw_sync_ff1 [get_registers {*syncdff_ff1*}]

if {[get_collection_size $spw_sync_ff1] > 0} {
    # Bound the crossing data path and the bit-to-bit routing skew into the
    # synchronizer inputs. set_net_delay limits the interconnect portion, which
    # is the part that matters for a metastability-hardened synchronizer.
    set_max_delay -from [all_registers] -to $spw_sync_ff1 $spw_cdc_max_delay_ns
    set_net_delay -to $spw_sync_ff1 -max $spw_cdc_max_delay_ns

    # Alternative if you prefer to cut the crossing entirely (safe here because
    # the head pointer is gray-coded and bitcnt is change-detected only):
    # set_false_path -to $spw_sync_ff1
} else {
    post_message -type warning "spw_cdc.sdc found no syncdff_ff1 registers; check instance names."
}
