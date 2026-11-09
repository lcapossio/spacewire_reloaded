# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# Libero SoC batch project + compile script for the PolarFire SoC Discovery Kit
# (MPFS095T-1FCSG325E) SpaceWire loopback example. Normally driven by
# examples/mpfs_disco_kit/build.py:
#
#   libero SCRIPT:build_mpfs.tcl "SCRIPT_ARGS:<repo> <hdl> <flow> <outdir> <program>"
#
#   <repo>     repository root (relative to the working directory, or absolute)
#   <hdl>      verilog | vhdl  (the VHDL build uses the Verilog vendor wrapper)
#   <flow>     synth = synthesis only
#              full  = synthesis + place-and-route + timing + programming data
#   <outdir>   project directory (relative or absolute); deleted and recreated
#   <program>  1 = program the board through the first FlashPro found (full only)

if {$argc != 5} {
    puts "usage: SCRIPT_ARGS:<repo> <hdl> <flow> <outdir> <program>"
    exit 2
}
lassign $argv repo hdl flow outdir program
# build.py passes repository-relative paths (SCRIPT_ARGS is split on spaces, and
# the checkout path may contain some); make them absolute before Libero changes
# its working directory.
set repo   [file normalize $repo]
set outdir [file normalize $outdir]

set here    "$repo/examples/mpfs_disco_kit"
set engine  "$repo/examples/arty_a7100t/rtl"
set fcapz   "$repo/examples/arty_a7100t/fpgacapZero/rtl"
set top     "spw_mpfs_disco_kit_top"
set project $top

if {[file isdirectory $outdir]} {
    file delete -force $outdir
}
file mkdir [file dirname $outdir]

new_project \
    -location $outdir \
    -name $project \
    -project_description {SpaceWire Reloaded loopback on the PolarFire SoC Discovery Kit} \
    -hdl [string toupper $hdl] \
    -family {PolarFireSoC} \
    -die {MPFS095T} \
    -package {FCSG325} \
    -speed {-1} \
    -die_voltage {1.0} \
    -part_range {EXT} \
    -adv_options {IO_DEFT_STD:LVCMOS 1.8V}

set sources {}
if {$hdl eq "verilog"} {
    foreach f {
        syncdff.v spwram.v spwlink.v spwxmit.v spwxmit_fast.v spwrecv.v
        spwrecvfront_generic.v spwrecvfront_fast.v spwstream.v
        spw_axis_tx.v spw_axis_rx.v spw_axi_lite_regs.v spw_axi_top.v
    } {
        lappend sources "$repo/rtl/verilog/$f"
    }
    lappend sources "$engine/spw_loopback_axi.v" "$here/rtl/$top.v"
} elseif {$hdl eq "vhdl"} {
    project_settings -vhdl_mode {VHDL_2008}
    foreach f {
        spwpkg.vhd spwlink.vhd spwrecv.vhd spwxmit.vhd spwxmit_fast.vhd
        spwrecvfront_generic.vhd spwrecvfront_fast.vhd syncdff.vhd spwram.vhd
        spwstream.vhd spw_axis_tx.vhd spw_axis_rx.vhd spw_axi_lite_regs.vhd
        spw_axi_top.vhd
    } {
        lappend sources "$repo/rtl/vhdl/$f"
    }
    lappend sources "$engine/spw_loopback_axi.vhd" "$here/rtl/$top.vhd"
} else {
    puts "ERROR: unknown hdl '$hdl' (verilog|vhdl)"
    exit 2
}

# Vendor wrapper: fcapz JTAG debug cores on the PolarFire UJTAG (Verilog, both
# builds), from the fpgacapZero submodule shared with the Arty example.
foreach f {
    fcapz_version.vh reset_sync.v dpram.v trig_compare.v
    fcapz_ela.v fcapz_eio.v fcapz_core_manager.v fcapz_debug_multi_core.v
    fcapz_hub_reset.v fcapz_debug_multi.v jtag_pipe_iface.v
    fcapz_async_fifo.v fcapz_ejtagaxi.v jtag_tap/jtag_tap_polarfire.v
} {
    lappend sources "$fcapz/$f"
}
lappend sources "$here/rtl/microchip/mpfs_por.v"
lappend sources "$here/rtl/microchip/mpfs_debug.v"

foreach src $sources {
    create_links -hdl_source $src
}
create_links -io_pdc "$here/mpfs_disco_kit_io.pdc"
create_links -sdc    "$here/mpfs_disco_kit.sdc"

build_design_hierarchy
set_root -module "${top}::work"

organize_tool_files -tool {SYNTHESIZE} \
    -file "$here/mpfs_disco_kit.sdc" \
    -module "${top}::work" -input_type {constraint}
organize_tool_files -tool {PLACEROUTE} \
    -file "$here/mpfs_disco_kit_io.pdc" \
    -file "$here/mpfs_disco_kit.sdc" \
    -module "${top}::work" -input_type {constraint}
organize_tool_files -tool {VERIFYTIMING} \
    -file "$here/mpfs_disco_kit.sdc" \
    -module "${top}::work" -input_type {constraint}

run_tool -name {SYNTHESIZE}
if {$flow eq "full"} {
    run_tool -name {PLACEROUTE}
    run_tool -name {VERIFYTIMING}
    run_tool -name {GENERATEPROGRAMMINGDATA}
    if {$program} {
        run_tool -name {PROGRAMDEVICE}
    }
}

save_project
close_project
exit 0
