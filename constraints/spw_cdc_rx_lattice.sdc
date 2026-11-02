# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# SpaceWire Reloaded - receive-side clock-domain-crossing timing constraints
# (Lattice Radiant).
#
# Companion to constraints/spw_cdc_rx.xdc; see that file for the crossings.
# Add this file only when RXIMPL = fast AND rxclk is a different clock from
# the system clock clk. With rxclk wired to clk, leave it out: the datapath-only
# delays would then drop hold checks on same-clock paths. The transmit side is
# in spw_cdc_tx_lattice.sdc. Radiant supports datapath-only maximum delays, so
# this mirrors the Vivado file; each constraint names the launch clock and only
# the destination registers of a crossing.
#
# Status: written against the Radiant constraint syntax (as used by Lattice's
# own dual-clock FIFO IP), but NOT yet run through Radiant in this repo. Check
# the synthesized cell names (sta_report_constraints shows constraints that
# matched nothing) and that sta_report_timing finds no remaining paths between
# the clocks.
#
# Usage: add this file to the Radiant project AFTER the clocks exist, and set
# the clock names below to the names your create_clock commands use. Do not
# put clk and rxclk in asynchronous clock groups or false-path between them:
# that would override these bounds.

set spw_clk_sys clk
set spw_clk_rx  rxclk

# Maximum delay on a crossing data path, in nanoseconds: at most the period of
# the FASTEST clock in a crossing (clk or rxclk).
set spw_cdc_max_delay_ns 5.000

# Instance scope: a glob for the hierarchy above recvfront_fast_inst, ending
# in "*" (default "*": every fast receiver in the design). With several
# cores where some have rxclk wired to clk, set spw_cdc_rx_scope (e.g.
# "*u_spw_a/*") before this file, and read the file once per core whose
# rxclk is a separate clock. The variable persists for files read later.
# See constraints/README.md.
set spw_cdc_rx_scope [expr {[info exists spw_cdc_rx_scope] ? $spw_cdc_rx_scope : "*"}]

# rxclk -> clk: head pointer and activity counter syncdff inputs (1), receive
# buffer registered read (3).
set_max_delay -datapath_only -from [get_clocks $spw_clk_rx] \
    -to [get_cells -hierarchical "${spw_cdc_rx_scope}recvfront_fast_inst/syncsys_*/syncdff_ff1*"] $spw_cdc_max_delay_ns
set_max_delay -datapath_only -from [get_clocks $spw_clk_rx] \
    -to [get_cells -hierarchical "${spw_cdc_rx_scope}recvfront_fast_inst/bufmem/rdata*"] $spw_cdc_max_delay_ns

# clk -> rxclk: asynchronous clear of the rxclk reset synchronizer (2).
set_max_delay -datapath_only -from [get_clocks $spw_clk_sys] \
    -to [get_cells -hierarchical "${spw_cdc_rx_scope}recvfront_fast_inst/syncrx_reset/syncdff_ff*"] $spw_cdc_max_delay_ns

# D/S line samplers: the line input is asynchronous to rxclk (5).
set_false_path -to [get_cells -hierarchical "${spw_cdc_rx_scope}recvfront_fast_inst/*a_di1*"]
set_false_path -to [get_cells -hierarchical "${spw_cdc_rx_scope}recvfront_fast_inst/*a_si1*"]
set_false_path -to [get_cells -hierarchical "${spw_cdc_rx_scope}recvfront_fast_inst/*a_di2*"]
set_false_path -to [get_cells -hierarchical "${spw_cdc_rx_scope}recvfront_fast_inst/*a_si2*"]
