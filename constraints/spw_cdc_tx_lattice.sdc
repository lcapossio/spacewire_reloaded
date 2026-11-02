# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# SpaceWire Reloaded - transmit-side clock-domain-crossing timing constraints
# (Lattice Radiant).
#
# Companion to constraints/spw_cdc_tx.xdc; see that file for the crossings.
# Add this file only when TXIMPL = fast AND txclk is a different clock from
# the system clock clk. With txclk wired to clk, leave it out: the datapath-only
# delays would then drop hold checks on same-clock paths. The receive side is
# in spw_cdc_rx_lattice.sdc. Each constraint names the launch clock and only
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
# put clk and txclk in asynchronous clock groups or false-path between them:
# that would override these bounds.

set spw_clk_sys clk
set spw_clk_tx  txclk

# Maximum delay on a crossing data path, in nanoseconds: at most the period of
# the FASTEST clock in a crossing (clk or txclk).
set spw_cdc_max_delay_ns 5.000

# txclk -> clk: transmit handshake flip syncdff inputs (1).
set_max_delay -datapath_only -from [get_clocks $spw_clk_tx] \
    -to [get_cells -hierarchical {*xmit_fast_inst/syncsys_*/syncdff_ff1*}] $spw_cdc_max_delay_ns

# clk -> txclk: syncdff inputs and the asynchronous clears of the txclk
# synchronizers (1, 2), and the token and divider registers (4).
set_max_delay -datapath_only -from [get_clocks $spw_clk_sys] \
    -to [get_cells -hierarchical {*xmit_fast_inst/synctx_*/syncdff_ff*}] $spw_cdc_max_delay_ns
set_max_delay -datapath_only -from [get_clocks $spw_clk_sys] \
    -to [get_cells -hierarchical {*xmit_fast_inst/*b_token*}] $spw_cdc_max_delay_ns
set_max_delay -datapath_only -from [get_clocks $spw_clk_sys] \
    -to [get_cells -hierarchical {*xmit_fast_inst/*txclkdiv*}] $spw_cdc_max_delay_ns
set_max_delay -datapath_only -from [get_clocks $spw_clk_sys] \
    -to [get_cells -hierarchical {*xmit_fast_inst/*txdivnorm_tx*}] $spw_cdc_max_delay_ns
set_max_delay -datapath_only -from [get_clocks $spw_clk_sys] \
    -to [get_cells -hierarchical {*xmit_fast_inst/rtx*txdivnorm*}] $spw_cdc_max_delay_ns
