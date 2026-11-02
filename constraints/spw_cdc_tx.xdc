# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# SpaceWire Reloaded - transmit-side clock-domain-crossing timing constraints
# (Xilinx Vivado).
#
# Read this file only when TXIMPL = fast AND txclk is a different clock from
# the system clock clk. With the generic transmitter, or with txclk wired to
# clk, leave it out: the rules below would then match nothing (rejected by
# Vivado) or relax same-clock paths. The receive side is in spw_cdc_rx.xdc.
#
# Transmit crossings (constraints/README.md lists all five crossing types):
#
#   1. syncdff synchronizers clk <-> txclk (handshake flips, enable and
#      divider-safe flags). The flip-flops carry ASYNC_REG/keep attributes.
#   2. The asynchronous resets of the synctx_* synchronizers (clk -> txclk).
#   4. The token and divider registers, loaded on clk and copied on txclk once
#      the handshake flip has crossed a syncdff.
#
# All three get a datapath-only maximum delay. The bounds are required, not
# optional: the handshake only protects the token and divider data if they
# settle before the synchronized flip says they are stable.
#
# Usage: read this file AFTER the clocks exist (from the board constraints or,
# for MMCM-generated clocks, post-synthesis). Do NOT put clk and txclk in
# separate set_clock_groups -asynchronous groups (or false-path between them):
# Vivado gives clock groups and false paths priority over set_max_delay, which
# silently disables these bounds. Check with report_exceptions -ignored. This
# file must stay plain XDC (no if/foreach/puts): Vivado rejects Tcl control
# flow in an XDC file and drops the rest of it. The cell patterns match both
# the Verilog and VHDL netlists.

# Maximum delay on a crossing data path, in nanoseconds: at most the period of
# the FASTEST clock in a crossing (clk or txclk).
set spw_cdc_max_delay_ns 5.000

# 1. syncdff data inputs, clk -> txclk (synctx_*) and txclk -> clk (syncsys_*).
set_max_delay -datapath_only -from [all_clocks] \
    -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *xmit_fast_inst/*/syncdff_ff1*}] \
             -filter {REF_PIN_NAME == D}] \
    $spw_cdc_max_delay_ns

# 2. Asynchronous resets of the txclk reset synchronizers, clk -> txclk.
set_max_delay -datapath_only -from [all_clocks] \
    -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *xmit_fast_inst/synctx_*/syncdff_ff*}] \
             -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}] \
    $spw_cdc_max_delay_ns

# 4. Transmit token and divider registers, clk -> txclk.
set_max_delay -datapath_only \
    -from [get_cells -hierarchical -filter \
              {NAME =~ *xmit_fast_inst/*token0* || NAME =~ *xmit_fast_inst/*token1* || NAME =~ *xmit_fast_inst/*txdivreg* || NAME =~ *xmit_fast_inst/txdivnorm_reg* || NAME =~ *xmit_fast_inst/r_reg?txdivnorm?*}] \
    -to [get_cells -hierarchical -filter \
              {NAME =~ *xmit_fast_inst/*b_token* || NAME =~ *xmit_fast_inst/*txclkdiv* || NAME =~ *xmit_fast_inst/txdivnorm_tx* || NAME =~ *xmit_fast_inst/rtx_reg?txdivnorm?*}] \
    $spw_cdc_max_delay_ns
