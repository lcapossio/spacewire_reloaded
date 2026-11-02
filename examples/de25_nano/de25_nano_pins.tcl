# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# DE25-Nano (Agilex 5) pin and I/O-standard assignments for the SpaceWire
# loopback example. Pins taken from the Terasic DE25-Nano User Manual
# (Sep 5, 2025): Table 3-6 (clocks), Table 3-9 (push-buttons), Table 3-10 (LEDs).
# Sourced by build_de25.tcl when present.
#
#   clk    <- CLOCK1_50  (PIN_V16, 3.3-V LVCMOS, 50 MHz)
#   btn[0] <- KEY[0]     (PIN_C8,  3.3-V LVCMOS, active-low)
#   btn[1] <- KEY[1]     (PIN_C11, 3.3-V LVCMOS, active-low)
#   led[0] -> LEDR[0]    (PIN_DF35, 1.1 V, active-low)
#   led[1] -> LEDR[1]    (PIN_DJ32, 1.1 V, active-low)
#   led[2] -> LEDR[2]    (PIN_DN22, 1.1 V, active-low)
#   led[3] -> LEDR[3]    (PIN_DP23, 1.1 V, active-low)

# ---- system clock: CLOCK1_50 ----
set_location_assignment PIN_V16 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to clk

# ---- push-buttons: KEY0 (reset), KEY1 ----
set_location_assignment PIN_C8  -to btn[0]
set_location_assignment PIN_C11 -to btn[1]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to btn[0]
set_instance_assignment -name IO_STANDARD "3.3-V LVCMOS" -to btn[1]

# ---- status LEDs: LEDR[3:0] ----
set_location_assignment PIN_DF35 -to led[0]
set_location_assignment PIN_DJ32 -to led[1]
set_location_assignment PIN_DN22 -to led[2]
set_location_assignment PIN_DP23 -to led[3]
set_instance_assignment -name IO_STANDARD "1.1 V" -to led[0]
set_instance_assignment -name IO_STANDARD "1.1 V" -to led[1]
set_instance_assignment -name IO_STANDARD "1.1 V" -to led[2]
set_instance_assignment -name IO_STANDARD "1.1 V" -to led[3]
