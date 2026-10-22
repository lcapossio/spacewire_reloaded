# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# SpaceWire Reloaded - clock-domain-crossing timing constraints (Intel Quartus
# Prime Pro).
#
# Companion to constraints/spw_cdc.xdc; see that file for the five crossing
# types. Needed only with the fast front ends, where rxclk and txclk can differ
# from clk.
#
# Quartus has no datapath-only max delay, so this file uses the Intel CDC idiom:
# a false path cuts the clock relationship of each crossing, and set_net_delay
# (plus set_max_skew on the multi-bit groups) bounds the routing. Quartus still
# analyzes set_net_delay and set_max_skew under false paths and asynchronous
# clock groups, so these bounds hold whatever clock groups the project uses.
# The receive head pointer is gray-coded and the buffer/token data is only read
# after a synchronized pointer or handshake, so correctness does not depend on
# these bounds; they keep a value from still being in flight a whole capture
# period after the protocol says it is stable.
#
# Usage: add this .sdc to the Quartus project AFTER the clocks clk, rxclk and
# txclk exist. It creates no clocks. Check report_sdc -ignored and the
# TMC-20025/20026 (empty collection / ignored constraint) messages.

# Maximum routing delay and skew on a crossing, in nanoseconds: at most the
# period of the FASTEST clock in a crossing (clk, rxclk or txclk).
set spw_cdc_max_delay_ns 5.000

# 1. syncdff synchronizer inputs (the D pin only, so a same-domain clear stays
#    timed).
set spw_sync_ff1 [get_registers -nowarn {*syncdff_ff1}]
set spw_sync_d   [get_pins -nowarn -compatibility_mode {*|syncdff_ff1|d}]
# 2. Asynchronous clears of the cross-domain reset synchronizers.
set spw_sync_rst [get_pins -nowarn -compatibility_mode \
    {*xmit_fast_inst|synctx_*|syncdff_ff*|clrn *recvfront_fast_inst|syncrx_reset|syncdff_ff*|clrn}]
# 3. Receive buffer (rxclk write) -> registered read (clk).
set spw_rxbuf_mem [get_registers -nowarn {*recvfront_fast_inst|bufmem|*mem*}]
set spw_rxbuf_rd  [get_registers -nowarn {*recvfront_fast_inst|bufmem|rdata*}]
# 4. Transmit token and divider registers, clk -> txclk.
set spw_tx_src [get_registers -nowarn \
    {*xmit_fast_inst|*token0* *xmit_fast_inst|*token1* *xmit_fast_inst|*txdivreg* *xmit_fast_inst|txdivnorm *xmit_fast_inst|r.txdivnorm}]
set spw_tx_dst [get_registers -nowarn \
    {*xmit_fast_inst|*b_token* *xmit_fast_inst|*txclkdiv* *xmit_fast_inst|txdivnorm_tx *xmit_fast_inst|rtx.txdivnorm}]
# 5. D/S line samplers (asynchronous input by definition).
set spw_line_smp [get_registers -nowarn \
    {*recvfront_fast_inst|*a_di1 *recvfront_fast_inst|*a_si1 *recvfront_fast_inst|*a_di2 *recvfront_fast_inst|*a_si2}]

if {[get_collection_size $spw_sync_ff1] > 0} {
    set_false_path -to $spw_sync_d
    set_net_delay -max $spw_cdc_max_delay_ns -from [all_registers] -to $spw_sync_ff1
    # Gray-coded head pointer: keep its bits within one capture period.
    set_max_skew -from [get_registers -nowarn {*recvfront_fast_inst|*headptr*}] \
        -to [get_registers -nowarn {*syncsys_headptr*|syncdff_ff1}] $spw_cdc_max_delay_ns
}
if {[get_collection_size $spw_sync_rst] > 0} {
    set_false_path -to $spw_sync_rst
}
if {[get_collection_size $spw_rxbuf_mem] > 0 && [get_collection_size $spw_rxbuf_rd] > 0} {
    # The read goes through the address mux, so there is no single net for
    # set_net_delay to bound. None is needed: the head pointer reaches the
    # reader through a two-stage syncdff at least two clk cycles after the write.
    set_false_path -from $spw_rxbuf_mem -to $spw_rxbuf_rd
}
if {[get_collection_size $spw_tx_src] > 0 && [get_collection_size $spw_tx_dst] > 0} {
    set_false_path -from $spw_tx_src -to $spw_tx_dst
    set_net_delay -max $spw_cdc_max_delay_ns -from $spw_tx_src -to $spw_tx_dst
    set_max_skew -from $spw_tx_src -to $spw_tx_dst $spw_cdc_max_delay_ns
}
if {[get_collection_size $spw_line_smp] > 0} {
    set_false_path -to $spw_line_smp
}
if {[get_collection_size $spw_sync_ff1] == 0} {
    post_message -type warning "spw_cdc.sdc found no syncdff_ff1 registers; check instance names."
}
