# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# SpaceWire Reloaded - receive-side clock-domain-crossing timing constraints
# (Xilinx Vivado).
#
# Read this file only when RXIMPL = fast AND rxclk is a different clock from
# the system clock clk. With the generic receiver, or with rxclk wired to clk,
# leave it out: the rules below would then match nothing (rejected by Vivado)
# or relax same-clock paths. The transmit side is in spw_cdc_tx.xdc.
#
# Receive crossings (constraints/README.md lists all five crossing types):
#
#   1. syncdff synchronizers rxclk -> clk (gray-coded head pointer, activity
#      counter). The flip-flops carry ASYNC_REG/keep attributes in the RTL.
#   2. The asynchronous reset of syncrx_reset (clk -> rxclk).
#   3. The receive buffer: LUTRAM written on rxclk, read into a clk register.
#   5. The D/S line samplers, whose input is asynchronous by definition.
#
# 1-3 get a datapath-only maximum delay; 5 is a false path. The bounds are
# required, not optional: the gray-coded pointer is only safe if its bits
# arrive within one capture period of each other, and the buffer word is only
# safe if it settles before the synchronized pointer says it is there.
#
# Usage: read this file AFTER the clocks exist (from the board constraints or,
# for MMCM-generated clocks, post-synthesis). Do NOT put clk and rxclk in
# separate set_clock_groups -asynchronous groups (or false-path between them):
# Vivado gives clock groups and false paths priority over set_max_delay, which
# silently disables 1-3. Check with report_exceptions -ignored. This file must
# stay plain XDC (no if/foreach/puts): Vivado rejects Tcl control flow in an
# XDC file and drops the rest of it. The cell patterns match both the Verilog
# and VHDL netlists.

# Maximum delay on a crossing data path, in nanoseconds: at most the period of
# the FASTEST clock in a crossing (clk or rxclk).
set spw_cdc_max_delay_ns 5.000

# Instance scope: a glob for the hierarchy above recvfront_fast_inst, ending
# in "*" (default "*": every fast receiver in the design). With several
# cores where some have rxclk wired to clk, limit this file to the cores whose
# rxclk is a separate clock: read_xdc -cells {u_spw_a u_spw_c} (in a project:
# the SCOPED_TO_CELLS file property), or set spw_cdc_rx_scope (e.g.
# "*u_spw_a/*") before this file. The variable persists for files read
# later. See constraints/README.md.
set spw_cdc_rx_scope [expr {[info exists spw_cdc_rx_scope] ? $spw_cdc_rx_scope : "*"}]

# 1. syncdff data inputs, rxclk -> clk.
set_max_delay -datapath_only -from [all_clocks] \
    -to [get_pins -of_objects [get_cells -hierarchical -filter "NAME =~ ${spw_cdc_rx_scope}recvfront_fast_inst/syncsys_*/syncdff_ff1*"] \
             -filter {REF_PIN_NAME == D}] \
    $spw_cdc_max_delay_ns

# 2. Asynchronous reset of the rxclk reset synchronizer, clk -> rxclk.
set_max_delay -datapath_only -from [all_clocks] \
    -to [get_pins -of_objects [get_cells -hierarchical -filter "NAME =~ ${spw_cdc_rx_scope}recvfront_fast_inst/syncrx_reset/syncdff_ff*"] \
             -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}] \
    $spw_cdc_max_delay_ns

# 3. Receive buffer LUTRAM (rxclk write) -> registered read (clk).
set_max_delay -datapath_only \
    -from [get_cells -hierarchical -filter "NAME =~ ${spw_cdc_rx_scope}recvfront_fast_inst/bufmem/*mem_reg* && IS_PRIMITIVE"] \
    -to [get_cells -hierarchical -filter "NAME =~ ${spw_cdc_rx_scope}recvfront_fast_inst/bufmem/rdata*"] \
    $spw_cdc_max_delay_ns

# 5. D/S line samplers: the line input is asynchronous to rxclk.
set_false_path \
    -to [get_pins -of_objects [get_cells -hierarchical -filter \
             "NAME =~ ${spw_cdc_rx_scope}recvfront_fast_inst/*a_di1_reg || NAME =~ ${spw_cdc_rx_scope}recvfront_fast_inst/*a_si1_reg || NAME =~ ${spw_cdc_rx_scope}recvfront_fast_inst/*a_di2_reg || NAME =~ ${spw_cdc_rx_scope}recvfront_fast_inst/*a_si2_reg"] \
             -filter {REF_PIN_NAME == D}]
