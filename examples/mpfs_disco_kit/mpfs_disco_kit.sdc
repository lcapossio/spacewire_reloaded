# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# Timing constraints for the PolarFire SoC Discovery Kit SpaceWire loopback
# example (Libero SmartTime). Generic build: a single system clock domain
# (rxclk = txclk = clk), so the SpaceWire CDC constraint files are not needed.
# Keep the clock period in sync with the SYS_CLOCK_HZ generic.

# 50 MHz reference oscillator (REF_CLK_50MHz, 20.0 ns).
create_clock -name clk -period 20.000 [get_ports {clk}]

# JTAG TCK from the on-board FlashPro5 clocks the fcapz cores behind UJTAG.
# Constrained at 6 MHz, as in Microchip's Discovery Kit designs (the fcapz
# FTDI transport defaults to 6 MHz).
create_clock -name TCK -period 166.67 -waveform {0 83.33} [get_ports {TCK}]

# The fcapz cores cross between TCK and clk through their own synchronizers
# and Gray-pointer async FIFOs (EJTAG-AXI command/response/burst FIFOs). An
# asynchronous clock group would leave those paths untimed, so bound every
# crossing instead: a Gray pointer must reach its first synchronizer stage
# within one capture period, or its bits could be sampled out of step. 16 ns
# is under the 20 ns clk period (the faster side). SmartTime only analyzes
# these paths with an explicit bound: under set_clock_groups -asynchronous
# they are listed but not timed, and set_max_delay does not apply.
#
# A hold check between unrelated clocks has no meaning (every capture register
# is a synchronizer stage or is read only after a synchronized handshake), but
# SmartTime adds the clock skew to it: TCK arrives through UJTAG about 2.4 ns
# later than clk, so a 0 ns minimum fails by that much. The minimum delay of
# -20 ns (one clk period) removes the hold requirement while keeping the setup
# bound above; set_false_path would remove both.
set_max_delay 16.000 -from [get_clocks {clk}] -to [get_clocks {TCK}]
set_max_delay 16.000 -from [get_clocks {TCK}] -to [get_clocks {clk}]
set_min_delay -20.000 -from [get_clocks {clk}] -to [get_clocks {TCK}]
set_min_delay -20.000 -from [get_clocks {TCK}] -to [get_clocks {clk}]

# Buttons and LEDs are asynchronous (buttons are synchronized in the design, or
# sampled by the EIO); do not time them.
set_false_path -from [get_ports {btn[*]}]
set_false_path -to [get_ports {led[*]}]
