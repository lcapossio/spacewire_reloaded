# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# Program the PolarFire SoC Discovery Kit from a project that build_mpfs.tcl
# made, through the first FlashPro found (the board's embedded FlashPro5).
# Normally driven by examples/mpfs_disco_kit/build.py --program-only:
#
#   libero SCRIPT:program_mpfs.tcl "SCRIPT_ARGS:<project dir>"
#
# <project dir> is relative to the working directory, or absolute.
#
# Nothing else (an fcapz host, OpenOCD) may hold the FlashPro's JTAG channel
# while this runs.

if {$argc != 1} {
    puts "usage: SCRIPT_ARGS:<project dir>"
    exit 2
}
set outdir [file normalize [lindex $argv 0]]
open_project -file "$outdir/spw_mpfs_disco_kit_top.prjx"
run_tool -name {PROGRAMDEVICE}
close_project
exit 0
