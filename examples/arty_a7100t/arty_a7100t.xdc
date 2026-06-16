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

# ---- SpaceWire Data/Strobe on Pmod JA ----
# For external loopback (LOOPBACK_INTERNAL=0) wire JA1->JA3 (Dout->Din) and
# JA2->JA4 (Sout->Sin). For internal loopback the inputs are ignored but the
# outputs still toggle so a scope can observe the link.
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports spw_do_pin] ;# JA1
set_property -dict {PACKAGE_PIN B11 IOSTANDARD LVCMOS33} [get_ports spw_so_pin] ;# JA2
set_property -dict {PACKAGE_PIN A11 IOSTANDARD LVCMOS33} [get_ports spw_di_pin] ;# JA3
set_property -dict {PACKAGE_PIN D12 IOSTANDARD LVCMOS33} [get_ports spw_si_pin] ;# JA4

# ---- BSCANE2 TCK / JTAG-debug CDC ----
# fpgacapZero debug cores cross between the JTAG (BSCANE2 TCK) domain and the
# 100 MHz design clock through their own synchronizers; declare the TCK clock
# and cut it from the design clock so the asynchronous crossings are not timed.
create_clock -name tck_bscan -period 100.0 \
    [get_pins -hierarchical -filter {NAME =~ *u_bscan/TCK}]

set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks board_clk] \
    -group [get_clocks tck_bscan]
