# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# Post-synthesis constraints for the FAST Arty A7-100T build, read by
# build_arty.tcl / build_arty_vhdl.tcl after synth_design (the MMCM-generated
# clocks do not exist before), followed by constraints/spw_cdc.xdc.
#
# rxclk (150 MHz) and txclk (100 MHz) are MMCM outputs of board_clk, so they
# stay in the board_clk group: the SpaceWire crossings between them are bounded
# by constraints/spw_cdc.xdc, which asynchronous clock groups would override.
# Only the JTAG TCK is asynchronous; the fpgacapZero cores synchronize it.
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks board_clk] \
    -group [get_clocks tck_bscan]

# ELA0 samples the transmit D/S outputs (txclk) in clk purely for observation;
# the capture is asynchronous by design.
set_false_path \
    -from [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *u_mmcm/CLKOUT1}]] \
    -to [get_cells -hierarchical -filter {NAME =~ u_debug/*}]

# The VHDL fast transmitter asks for its D/S output registers in the IOB, but
# this example puts error injection and the internal loopback between them and
# the pins, so they cannot be packed (Place 30-73 critical warning). Keep them
# in the fabric; the patterns cover the VHDL and Verilog register names.
set_property IOB FALSE [get_cells -hierarchical -filter \
    {NAME =~ *xmit_fast_inst/s_spwdo_reg || NAME =~ *xmit_fast_inst/s_spwso_reg || NAME =~ *xmit_fast_inst/spwdo_r_reg || NAME =~ *xmit_fast_inst/spwso_r_reg}]
