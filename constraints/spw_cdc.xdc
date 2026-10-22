# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# SpaceWire Reloaded - clock-domain-crossing timing constraints (Xilinx Vivado).
#
# Needed only with the fast front ends (RXIMPL/TXIMPL = fast), where rxclk and
# txclk can differ from the system clock clk. The crossings in the core are:
#
#   1. syncdff synchronizers (rxclk -> clk head pointer and activity counter,
#      clk <-> txclk handshake flips, enable and divider-safe flags). The
#      flip-flops carry ASYNC_REG/keep attributes in the RTL.
#   2. The asynchronous resets of the reset synchronizers that sit in another
#      domain (syncrx_reset in rxclk, synctx_* in txclk).
#   3. The receive buffer: LUTRAM written on rxclk, read into a clk register.
#      The gray-coded head pointer only advances after a word is written, so the
#      data is stable long before the reader can see it.
#   4. The transmit token and divider registers, loaded on clk and copied on
#      txclk only after the handshake flip has crossed a syncdff, so they are
#      stable while sampled.
#   5. The D/S line samplers, whose input is asynchronous by definition.
#
# 1-4 get a datapath-only maximum delay; 5 is a false path. Correctness does not
# depend on the bounds (the gray code and handshakes guarantee it); they bound
# skew and latency so a value is not still in flight a whole capture period
# after the protocol says it is stable.
#
# Usage: read this file AFTER the clocks clk, rxclk and txclk exist (from the
# board constraints or, for MMCM-generated clocks, post-synthesis). Do NOT put
# clk, rxclk and txclk in separate set_clock_groups -asynchronous groups (or
# false-path between them): Vivado gives clock groups and false paths priority
# over set_max_delay, which silently disables 1-4. Check with
# report_exceptions -ignored. This file must stay plain XDC (no if/foreach/puts):
# Vivado rejects Tcl control flow in an XDC file and drops the rest of it.
# The cell patterns match both the Verilog and VHDL netlists.

# Maximum delay on a crossing data path, in nanoseconds: at most the period of
# the FASTEST clock in a crossing (clk, rxclk or txclk).
set spw_cdc_max_delay_ns 5.000

# 1. syncdff data inputs.
set_max_delay -datapath_only -from [all_clocks] \
    -to [get_pins -of_objects [get_cells -hierarchical -filter {NAME =~ *syncdff_ff1*}] \
             -filter {REF_PIN_NAME == D}] \
    $spw_cdc_max_delay_ns

# 2. Asynchronous resets of the cross-domain reset synchronizers.
set_max_delay -datapath_only -from [all_clocks] \
    -to [get_pins -of_objects [get_cells -hierarchical -filter \
             {NAME =~ *xmit_fast_inst/synctx_*/syncdff_ff* || NAME =~ *recvfront_fast_inst/syncrx_reset/syncdff_ff*}] \
             -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE}] \
    $spw_cdc_max_delay_ns

# 3. Receive buffer LUTRAM (rxclk write) -> registered read (clk).
set_max_delay -datapath_only \
    -from [get_cells -hierarchical -filter {NAME =~ *recvfront_fast_inst/bufmem/*mem_reg* && IS_PRIMITIVE}] \
    -to [get_cells -hierarchical -filter {NAME =~ *recvfront_fast_inst/bufmem/rdata*}] \
    $spw_cdc_max_delay_ns

# 4. Transmit token and divider registers, clk -> txclk.
set_max_delay -datapath_only \
    -from [get_cells -hierarchical -filter \
              {NAME =~ *xmit_fast_inst/*token0* || NAME =~ *xmit_fast_inst/*token1* || NAME =~ *xmit_fast_inst/*txdivreg* || NAME =~ *xmit_fast_inst/txdivnorm_reg* || NAME =~ *xmit_fast_inst/r_reg?txdivnorm?*}] \
    -to [get_cells -hierarchical -filter \
              {NAME =~ *xmit_fast_inst/*b_token* || NAME =~ *xmit_fast_inst/*txclkdiv* || NAME =~ *xmit_fast_inst/txdivnorm_tx* || NAME =~ *xmit_fast_inst/rtx_reg?txdivnorm?*}] \
    $spw_cdc_max_delay_ns

# 5. D/S line samplers: the line input is asynchronous to rxclk.
set_false_path \
    -to [get_pins -of_objects [get_cells -hierarchical -filter \
             {NAME =~ *recvfront_fast_inst/*a_di1_reg || NAME =~ *recvfront_fast_inst/*a_si1_reg || NAME =~ *recvfront_fast_inst/*a_di2_reg || NAME =~ *recvfront_fast_inst/*a_si2_reg}] \
             -filter {REF_PIN_NAME == D}]
