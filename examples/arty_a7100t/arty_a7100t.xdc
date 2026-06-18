# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# Arty A7-100T constraints for the SpaceWire Reloaded loopback example.
# Board: Digilent Arty A7-100T (xc7a100tcsg324-1).

# ---- System clock (100 MHz) ----
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk]
create_clock -period 10.000 -name board_clk [get_ports clk]

# ---- Push-buttons (active-high); btn[0] = reset ----
set_property -dict {PACKAGE_PIN D9 IOSTANDARD LVCMOS33} [get_ports {btn[0]}]
set_property -dict {PACKAGE_PIN C9 IOSTANDARD LVCMOS33} [get_ports {btn[1]}]
set_property -dict {PACKAGE_PIN B9 IOSTANDARD LVCMOS33} [get_ports {btn[2]}]
set_property -dict {PACKAGE_PIN B8 IOSTANDARD LVCMOS33} [get_ports {btn[3]}]

# ---- LEDs LD4-LD7 (status) ----
set_property -dict {PACKAGE_PIN H5  IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5  IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9  IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

# ---- SpaceWire Data/Strobe on Pmod JA (single-ended LVCMOS33, not LVDS) ----
# Four single-ended D/S signals: outputs on the top row, the matching inputs
# directly below, with Data and Strobe in separate columns to keep D/S crosstalk
# down. For external loopback (LOOPBACK_INTERNAL=0) fit two straight jumpers:
# JA1->JA7 (Dout->Din) and JA4->JA10 (Sout->Sin). For internal loopback the
# inputs are ignored, but the outputs still toggle so a scope/ELA can observe the
# link. The inputs have pulldowns so a removed/absent jumper reads a clean static
# 0 (deterministic disconnect) instead of floating.
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports spw_do_pin] ;# JA1
set_property -dict {PACKAGE_PIN D12 IOSTANDARD LVCMOS33} [get_ports spw_so_pin] ;# JA4
set_property -dict {PACKAGE_PIN D13 IOSTANDARD LVCMOS33 PULLTYPE PULLDOWN} [get_ports spw_di_pin] ;# JA7
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33 PULLTYPE PULLDOWN} [get_ports spw_si_pin] ;# JA10

# ---- BSCANE2 TCK / JTAG-debug CDC ----
# fpgacapZero debug cores cross between the JTAG (BSCANE2 TCK) domain and the
# 100 MHz design clock through their own synchronizers; declare the TCK clock
# and cut it from the design clock so the asynchronous crossings are not timed.
create_clock -name tck_bscan -period 100.0 \
    [get_pins -hierarchical -filter {NAME =~ *u_bscan/TCK}]

set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks board_clk] \
    -group [get_clocks tck_bscan]
