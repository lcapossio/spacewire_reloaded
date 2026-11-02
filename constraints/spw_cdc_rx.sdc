# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# SpaceWire Reloaded - receive-side clock-domain-crossing timing constraints
# (Intel Quartus Prime Pro).
#
# Companion to constraints/spw_cdc_rx.xdc; see that file for the crossings.
# Add this file only when RXIMPL = fast AND rxclk is a different clock from
# the system clock clk. With rxclk wired to clk, leave it out: its false paths
# would then cut same-clock paths. The transmit side is in spw_cdc_tx.sdc.
#
# Each crossing is cut with set_false_path and bounded with set_data_delay (a
# datapath-only maximum delay, Tco + logic + routing + Tsu); the gray-coded head
# pointer also gets set_max_skew. Quartus analyzes set_data_delay and
# set_max_skew independently of false paths and asynchronous clock groups, so
# these bounds hold whatever clock groups the project uses. The bounds are
# required, not optional: the gray-coded pointer is only safe if its bits
# arrive within one capture period of each other, and the buffer word is only
# safe if it settles before the synchronized pointer says it is there.
#
# Usage: add this .sdc to the Quartus project AFTER the clocks clk and rxclk
# exist. It creates no clocks. Check report_sdc -ignored and the
# TMC-20025/20026 (empty collection / ignored constraint) messages.

# Maximum data delay and skew on a crossing, in nanoseconds: at most the period
# of the FASTEST clock in a crossing (clk or rxclk).
set spw_cdc_max_delay_ns 5.000

# 1. syncdff synchronizers rxclk -> clk (the D pin only for the false path, so
#    a same-domain clear stays timed).
set spw_rx_sync_ff1 [get_registers -nowarn {*recvfront_fast_inst|syncsys_*|syncdff_ff1}]
set spw_rx_sync_d   [get_pins -nowarn -compatibility_mode {*recvfront_fast_inst|syncsys_*|syncdff_ff1|d}]
# 2. Asynchronous clear of the rxclk reset synchronizer (clk -> rxclk).
set spw_rx_sync_rst [get_pins -nowarn -compatibility_mode {*recvfront_fast_inst|syncrx_reset|syncdff_ff*|clrn}]
# 3. Receive buffer (rxclk write) -> registered read through the mux (clk).
set spw_rxbuf_mem [get_registers -nowarn {*recvfront_fast_inst|bufmem|*mem*}]
set spw_rxbuf_rd  [get_registers -nowarn {*recvfront_fast_inst|bufmem|rdata*}]
# 5. D/S line samplers (asynchronous input by definition).
set spw_line_smp [get_registers -nowarn \
    {*recvfront_fast_inst|*a_di1 *recvfront_fast_inst|*a_si1 *recvfront_fast_inst|*a_di2 *recvfront_fast_inst|*a_si2}]

if {[get_collection_size $spw_rx_sync_ff1] > 0} {
    set_false_path -to $spw_rx_sync_d
    set_data_delay -from [all_registers] -to $spw_rx_sync_d $spw_cdc_max_delay_ns
    # Gray-coded head pointer: keep its bits within one capture period.
    set_max_skew -from [get_registers -nowarn {*recvfront_fast_inst|*headptr*}] \
        -to [get_registers -nowarn {*recvfront_fast_inst|syncsys_headptr*|syncdff_ff1}] $spw_cdc_max_delay_ns
} else {
    post_message -type warning "spw_cdc_rx.sdc found no receive syncdff_ff1 registers; check instance names."
}
if {[get_collection_size $spw_rx_sync_rst] > 0} {
    set_false_path -to $spw_rx_sync_rst
    set_data_delay -from [all_registers] -to $spw_rx_sync_rst $spw_cdc_max_delay_ns
}
if {[get_collection_size $spw_rxbuf_mem] > 0 && [get_collection_size $spw_rxbuf_rd] > 0} {
    set_false_path -from $spw_rxbuf_mem -to $spw_rxbuf_rd
    set_data_delay -from $spw_rxbuf_mem -to $spw_rxbuf_rd $spw_cdc_max_delay_ns
}
if {[get_collection_size $spw_line_smp] > 0} {
    set_false_path -to $spw_line_smp
}
