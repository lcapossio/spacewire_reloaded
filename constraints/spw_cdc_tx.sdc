# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# SpaceWire Reloaded - transmit-side clock-domain-crossing timing constraints
# (Intel Quartus Prime Pro).
#
# Companion to constraints/spw_cdc_tx.xdc; see that file for the crossings.
# Add this file only when TXIMPL = fast AND txclk is a different clock from
# the system clock clk. With txclk wired to clk, leave it out: its false paths
# would then cut same-clock paths. The receive side is in spw_cdc_rx.sdc.
#
# Each crossing is cut with set_false_path and bounded with set_data_delay (a
# datapath-only maximum delay, Tco + logic + routing + Tsu); the multi-bit token
# and divider group also gets set_max_skew. Quartus analyzes set_data_delay and
# set_max_skew independently of false paths and asynchronous clock groups, so
# these bounds hold whatever clock groups the project uses. The bounds are
# required, not optional: the handshake only protects the token and divider
# data if they settle before the synchronized flip says they are stable.
#
# Usage: add this .sdc to the Quartus project AFTER the clocks clk and txclk
# exist. It creates no clocks. Check report_sdc -ignored and the
# TMC-20025/20026 (empty collection / ignored constraint) messages.

# Maximum data delay and skew on a crossing, in nanoseconds: at most the period
# of the FASTEST clock in a crossing (clk or txclk).
set spw_cdc_max_delay_ns 5.000

# Instance scope: a glob for the hierarchy above xmit_fast_inst, ending
# in "*" (default "*": every fast transmitter in the design). With several
# cores where some have txclk wired to clk, set spw_cdc_tx_scope (e.g.
# "*u_spw_a|*") before this file, and read the file once per core whose
# txclk is a separate clock. The variable persists for files read later.
# See constraints/README.md.
set spw_cdc_tx_scope [expr {[info exists spw_cdc_tx_scope] ? $spw_cdc_tx_scope : "*"}]

# 1. syncdff synchronizers clk <-> txclk (the D pin only for the false path, so
#    a same-domain clear stays timed).
set spw_tx_sync_ff1 [get_registers -nowarn "${spw_cdc_tx_scope}xmit_fast_inst|*|syncdff_ff1"]
set spw_tx_sync_d   [get_pins -nowarn -compatibility_mode "${spw_cdc_tx_scope}xmit_fast_inst|*|syncdff_ff1|d"]
# 2. Asynchronous clears of the txclk reset synchronizers (clk -> txclk).
set spw_tx_sync_rst [get_pins -nowarn -compatibility_mode "${spw_cdc_tx_scope}xmit_fast_inst|synctx_*|syncdff_ff*|clrn"]
# 4. Transmit token and divider registers, clk -> txclk.
set spw_tx_src [get_registers -nowarn \
    "${spw_cdc_tx_scope}xmit_fast_inst|*token0* ${spw_cdc_tx_scope}xmit_fast_inst|*token1* ${spw_cdc_tx_scope}xmit_fast_inst|*txdivreg* ${spw_cdc_tx_scope}xmit_fast_inst|txdivnorm ${spw_cdc_tx_scope}xmit_fast_inst|r.txdivnorm"]
set spw_tx_dst [get_registers -nowarn \
    "${spw_cdc_tx_scope}xmit_fast_inst|*b_token* ${spw_cdc_tx_scope}xmit_fast_inst|*txclkdiv* ${spw_cdc_tx_scope}xmit_fast_inst|txdivnorm_tx ${spw_cdc_tx_scope}xmit_fast_inst|rtx.txdivnorm"]

if {[get_collection_size $spw_tx_sync_ff1] > 0} {
    set_false_path -to $spw_tx_sync_d
    set_data_delay -from [all_registers] -to $spw_tx_sync_d $spw_cdc_max_delay_ns
} else {
    post_message -type warning "spw_cdc_tx.sdc found no transmit syncdff_ff1 registers; check instance names."
}
if {[get_collection_size $spw_tx_sync_rst] > 0} {
    set_false_path -to $spw_tx_sync_rst
    set_data_delay -from [all_registers] -to $spw_tx_sync_rst $spw_cdc_max_delay_ns
}
if {[get_collection_size $spw_tx_src] > 0 && [get_collection_size $spw_tx_dst] > 0} {
    set_false_path -from $spw_tx_src -to $spw_tx_dst
    set_data_delay -from $spw_tx_src -to $spw_tx_dst $spw_cdc_max_delay_ns
    set_max_skew -from $spw_tx_src -to $spw_tx_dst $spw_cdc_max_delay_ns
}
