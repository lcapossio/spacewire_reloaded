# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com

"""Shared ready/valid backpressure helpers for the AXI cocotb tests.

Holding the DUT-driven channels' READY low for some cycles is what makes the
cocotbext-axi fork's check_protocol handshake checker non-vacuous: the
"VALID must stay asserted (with stable payload) until the handshake" rule can
only be exercised when READY actually goes low while VALID is high. The mild
fixed patterns below guarantee such stall cycles without starving throughput."""


def pause_cycles(pattern):
    while True:
        for paused in pattern:
            yield paused


def backpressure_axil(master):
    """Backpressure all five AXI-Lite channels of an AxiLiteMaster, including the
    DUT-driven B/R response channels (where the slave must hold VALID)."""
    master.write_if.aw_channel.set_pause_generator(pause_cycles([False, True, False, False]))
    master.write_if.w_channel.set_pause_generator(pause_cycles([False, False, True]))
    master.write_if.b_channel.set_pause_generator(pause_cycles([True, False, False, True, False]))
    master.read_if.ar_channel.set_pause_generator(pause_cycles([False, False, True, False]))
    master.read_if.r_channel.set_pause_generator(pause_cycles([True, False, True, False]))


def backpressure_axis_sink(sink):
    """Backpressure a DUT-source AXI-Stream sink (where the DUT must hold TVALID)."""
    sink.set_pause_generator(pause_cycles([True, False, False, True, False]))


def backpressure_axis_source(source):
    source.set_pause_generator(pause_cycles([False, False, True, False]))
