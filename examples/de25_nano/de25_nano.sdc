# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# Timing constraints for the DE25-Nano SpaceWire loopback example.
# Generic build: a single system clock domain (rxclk = txclk = clk). The clock
# is a DE25-Nano 50 MHz source (CLOCK1_50, PIN_V16); keep this in sync with the
# SYS_CLOCK_HZ generic.

# 50 MHz system clock (20.0 ns).
create_clock -name clk -period 20.000 [get_ports clk]

# JTAG TCK (on-board USB-Blaster III, default 15 MHz) clocks the fcapz
# sld_virtual_jtag cores. Constrained at 24 MHz for headroom; the fcapz cores
# cross between TCK and clk with explicit synchronizers/async FIFOs, so the two
# clocks are asynchronous. JTAG pin delays follow the Intel JTAG SDC template.
create_clock -name altera_reserved_tck -period 41.667 [get_ports {altera_reserved_tck}]
set_clock_groups -asynchronous -group [get_clocks {clk}] -group [get_clocks {altera_reserved_tck}]
set_input_delay  -clock altera_reserved_tck -clock_fall 3 [get_ports {altera_reserved_tdi}]
set_input_delay  -clock altera_reserved_tck -clock_fall 3 [get_ports {altera_reserved_tms}]
set_output_delay -clock altera_reserved_tck 3 [get_ports {altera_reserved_tdo}]

# Buttons and LEDs are asynchronous (buttons are synchronized in the design, or
# sampled by the EIO); do not time them.
set_false_path -from [get_ports {btn[*]}]
set_false_path -to [get_ports {led[*]}]

derive_clock_uncertainty
