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

# The asynchronous clock groups cut the timing of the fcapz Gray-pointer FIFO
# crossings (EJTAG-AXI cmd/resp/burst FIFOs), so bound them explicitly: the
# pointer bits must reach the first synchronizer stage with little delay and
# skew, or a multi-bit Gray code could be sampled out of step. 8 ns is well
# under the 20 ns clk period (the faster side). Quartus still analyzes
# set_max_skew/set_net_delay under set_clock_groups (see the STA report).
set fcapz_wptr_gray [get_keepers -nowarn {*wptr_gray[*]}]
set fcapz_wptr_sync [get_keepers -nowarn {*wptr_sync1_r[*]}]
set fcapz_rptr_gray [get_keepers -nowarn {*rptr_gray[*]}]
set fcapz_rptr_sync [get_keepers -nowarn {*rptr_sync1_w[*]}]
set_max_skew -from $fcapz_wptr_gray -to $fcapz_wptr_sync 8.000
set_max_skew -from $fcapz_rptr_gray -to $fcapz_rptr_sync 8.000
set_net_delay -max 8.000 -from $fcapz_wptr_gray -to $fcapz_wptr_sync
set_net_delay -max 8.000 -from $fcapz_rptr_gray -to $fcapz_rptr_sync

# Buttons and LEDs are asynchronous (buttons are synchronized in the design, or
# sampled by the EIO); do not time them.
set_false_path -from [get_ports {btn[*]}]
set_false_path -to [get_ports {led[*]}]

derive_clock_uncertainty
