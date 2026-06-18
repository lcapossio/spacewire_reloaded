# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# Arty A7-100T constraints for the FAST SpaceWire loopback build (USE_MMCM=1,
# RXIMPL=TXIMPL=fast). Physical pins + primary clocks only; the MMCM-generated
# rxclk/txclk clock groups and the CDC max-delay (constraints/spw_cdc.xdc) are
# applied post-synthesis by build_arty.tcl because they reference objects that
# do not exist until the netlist is built.
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
# Outputs top row, inputs directly below, Data and Strobe in separate columns.
# External loopback: JA1->JA7 (Dout->Din), JA4->JA10 (Sout->Sin). Inputs have
# pulldowns so an absent jumper reads a clean static 0 (deterministic disconnect).
set_property -dict {PACKAGE_PIN G13 IOSTANDARD LVCMOS33} [get_ports spw_do_pin] ;# JA1
set_property -dict {PACKAGE_PIN D12 IOSTANDARD LVCMOS33} [get_ports spw_so_pin] ;# JA4
set_property -dict {PACKAGE_PIN D13 IOSTANDARD LVCMOS33 PULLTYPE PULLDOWN} [get_ports spw_di_pin] ;# JA7
set_property -dict {PACKAGE_PIN K16 IOSTANDARD LVCMOS33 PULLTYPE PULLDOWN} [get_ports spw_si_pin] ;# JA10

# ---- BSCANE2 TCK (JTAG-debug) primary clock ----
create_clock -name tck_bscan -period 100.0 \
    [get_pins -hierarchical -filter {NAME =~ *u_bscan/TCK}]
