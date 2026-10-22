# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# SpaceWire Reloaded - clock-domain-crossing timing constraints (Lattice
# Radiant).
#
# Companion to constraints/spw_cdc.xdc; see that file for the five crossing
# types. Needed only with the fast front ends, where rxclk and txclk can differ
# from clk. Radiant supports datapath-only maximum delays, so this mirrors the
# Vivado file. Each constraint names the launch clock and only the destination
# registers of a crossing, so no same-domain path is relaxed.
#
# Status: written against the Radiant constraint syntax (as used by Lattice's
# own dual-clock FIFO IP), but NOT yet run through Radiant in this repo. Check
# the synthesized cell names (sta_report_constraints shows constraints that
# matched nothing) and that sta_report_timing finds no remaining paths between
# the three clocks.
#
# Usage: add this file to the Radiant project AFTER the clocks exist, and set
# the three clock names below to the names your create_clock commands use.
# Do not put the three clocks in asynchronous clock groups or false-path
# between them: that would override these bounds.

set spw_clk_sys clk
set spw_clk_rx  rxclk
set spw_clk_tx  txclk

# Maximum delay on a crossing data path, in nanoseconds: at most the period of
# the FASTEST clock in a crossing (clk, rxclk or txclk).
set spw_cdc_max_delay_ns 5.000

# rxclk -> clk: head pointer and activity counter syncdff inputs (1), receive
# buffer registered read (3).
set_max_delay -datapath_only -from [get_clocks $spw_clk_rx] \
    -to [get_cells -hierarchical {*recvfront_fast_inst/syncsys_*/syncdff_ff1*}] $spw_cdc_max_delay_ns
set_max_delay -datapath_only -from [get_clocks $spw_clk_rx] \
    -to [get_cells -hierarchical {*recvfront_fast_inst/bufmem/rdata*}] $spw_cdc_max_delay_ns

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

# clk -> rxclk: asynchronous clear of the rxclk reset synchronizer (2).
set_max_delay -datapath_only -from [get_clocks $spw_clk_sys] \
    -to [get_cells -hierarchical {*recvfront_fast_inst/syncrx_reset/syncdff_ff*}] $spw_cdc_max_delay_ns

# D/S line samplers: the line input is asynchronous to rxclk (5).
set_false_path -to [get_cells -hierarchical {*recvfront_fast_inst/*a_di1*}]
set_false_path -to [get_cells -hierarchical {*recvfront_fast_inst/*a_si1*}]
set_false_path -to [get_cells -hierarchical {*recvfront_fast_inst/*a_di2*}]
set_false_path -to [get_cells -hierarchical {*recvfront_fast_inst/*a_si2*}]
