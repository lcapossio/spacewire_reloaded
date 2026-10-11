# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# Quartus Prime Pro project + compile script for the DE25-Nano (Agilex 5)
# SpaceWire loopback example. Normally driven by examples/de25_nano/build.py;
# run from the repository root:
#
#   quartus_sh -t examples/de25_nano/build_de25.tcl <hdl> <device> <flow> <outdir> <jobs>
#
#   <hdl>     verilog | vhdl  (the VHDL build uses the Verilog vendor wrapper)
#   <device>  Agilex 5 OPN; DE25-Nano = A5EB013BB23BE4SR1
#   <flow>    synth = Analysis & Synthesis only
#             full  = Synthesis + Fit + Timing Analysis + Assembler (.sof)
#   <outdir>  project directory, relative to the repository root
#   <jobs>    max parallel processors for Quartus

load_package flow

if {[llength $argv] != 5} {
    puts "usage: quartus_sh -t build_de25.tcl <hdl> <device> <flow> <outdir> <jobs>"
    exit 2
}
lassign $argv hdl device flow outdir jobs

# Absolute paths from the repo root (current dir); the project itself lives in
# $outdir so every generated file stays out of the source tree.
set repo    [pwd]
set here    [file join $repo examples de25_nano]
set engine  [file join $repo examples arty_a7100t rtl]
set project "spw_de25_nano_top"
set absout  [file join $repo $outdir]

file mkdir $absout
cd $absout
file delete -force "$project.qpf" "$project.qsf"
project_new -overwrite -part $device $project

set_global_assignment -name FAMILY "Agilex 5"
set_global_assignment -name DEVICE $device
set_global_assignment -name TOP_LEVEL_ENTITY $project
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output
set_global_assignment -name NUM_PARALLEL_PROCESSORS $jobs

if {$hdl eq "verilog"} {
    set core [file join $repo rtl verilog]
    foreach f {
        syncdff.v spwram.v spwlink.v spwxmit.v spwxmit_fast.v spwrecv.v
        spwrecvfront_generic.v spwrecvfront_fast.v spwstream.v
        spw_axis_tx.v spw_axis_rx.v spw_axi_lite_regs.v spw_axi_top.v
    } {
        set_global_assignment -name VERILOG_FILE [file join $core $f]
    }
    set_global_assignment -name VERILOG_FILE [file join $engine spw_loopback_axi.v]
    set_global_assignment -name VERILOG_FILE [file join $here rtl spw_de25_nano_top.v]
} elseif {$hdl eq "vhdl"} {
    set_global_assignment -name VHDL_INPUT_VERSION VHDL_2008
    set core [file join $repo rtl vhdl]
    foreach f {
        spwpkg.vhd spwlink.vhd spwrecv.vhd spwxmit.vhd spwxmit_fast.vhd
        spwrecvfront_generic.vhd spwrecvfront_fast.vhd syncdff.vhd spwram.vhd
        spwstream.vhd spw_axis_tx.vhd spw_axis_rx.vhd spw_axi_lite_regs.vhd
        spw_axi_top.vhd
    } {
        set_global_assignment -name VHDL_FILE [file join $core $f]
    }
    set_global_assignment -name VHDL_FILE [file join $engine spw_loopback_axi.vhd]
    set_global_assignment -name VHDL_FILE [file join $here rtl spw_de25_nano_top.vhd]
} else {
    puts "ERROR: unknown hdl '$hdl' (verilog|vhdl)"
    exit 2
}

# Vendor wrapper: Agilex configuration reset release (Verilog, both builds).
# The Reset Release IP is copied into the project so Quartus generates its HDL
# under $outdir instead of next to the tracked .ip source.
set_global_assignment -name VERILOG_FILE [file join $here rtl intel de25_reset_release.v]

# Vendor wrapper: fpgacapZero JTAG debug cores (Intel sld_virtual_jtag), from
# the fpgacapZero submodule shared with the Arty example (Verilog, both builds).
set fcapz [file join $repo examples arty_a7100t fpgacapZero rtl]
if {![file exists [file join $fcapz fcapz_ela_intel.v]]} {
    puts "BUILD_DE25_FAILED fpgacapZero submodule missing: git submodule update --init examples/arty_a7100t/fpgacapZero"
    project_close
    exit 1
}
set_global_assignment -name SEARCH_PATH $fcapz
foreach f {
    reset_sync.v dpram.v trig_compare.v fcapz_ela.v fcapz_ela_intel.v
    fcapz_async_fifo.v fcapz_ejtagaxi.v fcapz_ejtagaxi_intel.v
    fcapz_eio.v fcapz_eio_intel.v jtag_reg_iface.v jtag_burst_read.v
    jtag_pipe_iface.v jtag_tap/jtag_tap_intel.v
} {
    set_global_assignment -name VERILOG_FILE [file join $fcapz $f]
}
set_global_assignment -name VERILOG_FILE [file join $here rtl intel de25_debug.v]

file mkdir ip
file copy -force [file join $here rtl intel de25_reset_release_ip.ip] ip
set_global_assignment -name IP_FILE [file join ip de25_reset_release_ip.ip]

set_global_assignment -name SDC_FILE [file join $here de25_nano.sdc]
source [file join $here de25_nano_pins.tcl]

puts "=== DE25-Nano build: hdl=$hdl device=$device flow=$flow jobs=$jobs ==="

if {$flow eq "synth"} {
    # The full compile flow generates IP itself; a synthesis-only run must
    # generate the Reset Release IP explicitly first.
    if {[catch {execute_module -tool ipg -args "--run_default_mode_op"} res]} {
        puts "BUILD_DE25_FAILED ip generation: $res"
        project_close
        exit 1
    }
    if {[catch {execute_module -tool syn} res]} {
        puts "BUILD_DE25_FAILED synthesis: $res"
        project_close
        exit 1
    }
} elseif {$flow eq "full"} {
    if {[catch {execute_flow -compile} res]} {
        puts "BUILD_DE25_FAILED compile: $res"
        project_close
        exit 1
    }
} else {
    puts "ERROR: unknown flow '$flow' (synth|full)"
    project_close
    exit 2
}

project_close
puts "BUILD_DE25_DONE $hdl $device $flow"
