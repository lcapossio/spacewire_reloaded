# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# Vivado non-project build of the Arty A7-100T SpaceWire loopback example
# (all-Verilog). Run via build.py, or directly:
#   vivado -mode batch -source examples/arty_a7100t/build_arty.tcl

set part        xc7a100tcsg324-1
set example_dir [file normalize [file dirname [info script]]]
set root        [file normalize $example_dir/../..]
set fcapz       $example_dir/fpgacapZero
set spw         $root/rtl/verilog

# Vivado 2025.2 can leave the per-user Tcl store support package outside the
# startup auto_path (tclapp::load_apps "Could not open ..." errors). Add the
# nested support paths when they already exist; no-op on clean installations.
if {[info exists ::env(APPDATA)]} {
    regsub -all {\\} $::env(APPDATA) {/} appdata_dir
    set xilinx_tcl_store [file join $appdata_dir Xilinx Vivado [version -short] XilinxTclStore]
    foreach support_dir [list \
        [file join $xilinx_tcl_store support] \
        [file join $xilinx_tcl_store support appinit] \
        [file join $xilinx_tcl_store support args] \
        [file join $xilinx_tcl_store tclapp] \
        [file join $xilinx_tcl_store tclapp xilinx] \
        [file join $xilinx_tcl_store tclapp xilinx xsim] \
    ] {
        if {[file isdirectory $support_dir] && [lsearch -exact $::auto_path $support_dir] < 0} {
            lappend ::auto_path $support_dir
        }
    }
}

read_verilog [list \
    $fcapz/rtl/reset_sync.v \
    $fcapz/rtl/dpram.v \
    $fcapz/rtl/trig_compare.v \
    $fcapz/rtl/fcapz_ela.v \
    $fcapz/rtl/fcapz_core_manager.v \
    $fcapz/rtl/fcapz_debug_multi_xilinx7.v \
    $fcapz/rtl/fcapz_ela_xilinx7.v \
    $fcapz/rtl/jtag_reg_iface.v \
    $fcapz/rtl/jtag_pipe_iface.v \
    $fcapz/rtl/jtag_burst_read.v \
    $fcapz/rtl/jtag_tap/jtag_tap_xilinx7.v \
    $fcapz/rtl/fcapz_async_fifo.v \
    $fcapz/rtl/fcapz_ejtagaxi.v \
    $fcapz/rtl/fcapz_ejtagaxi_xilinx7.v \
    $fcapz/rtl/fcapz_eio.v \
    $fcapz/rtl/fcapz_eio_xilinx7.v \
    $spw/syncdff.v \
    $spw/spwram.v \
    $spw/spwlink.v \
    $spw/spwxmit.v \
    $spw/spwxmit_fast.v \
    $spw/spwrecv.v \
    $spw/spwrecvfront_generic.v \
    $spw/spwrecvfront_fast.v \
    $spw/spwstream.v \
    $spw/spw_axis_tx.v \
    $spw/spw_axis_rx.v \
    $spw/spw_axi_lite_regs.v \
    $spw/spw_axi_top.v \
    $example_dir/rtl/spw_loopback_axi.v \
    $example_dir/rtl/spw_arty_a7100t_top.v ]

set fast 0
if {[info exists ::env(SPW_FAST)] && $::env(SPW_FAST) eq "1"} { set fast 1 }

if {$fast} {
    # Fast build: MMCM rxclk/txclk in their own domains -> exercises the
    # gray-coded rxclk->clk and clk<->txclk crossings and constraints/spw_cdc.xdc.
    read_xdc $example_dir/arty_a7100t_fast.xdc
    synth_design -top spw_arty_a7100t_top -part $part -include_dirs $fcapz/rtl \
        -generic RXIMPL=1 -generic TXIMPL=1 -generic RXCHUNK=2 -generic USE_MMCM=1 \
        -generic LINK_TXDIVCNT=0

    # Post-synthesis: the MMCM generated clocks and syncdff cells now exist.
    set rxc [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *u_mmcm/CLKOUT0}]]
    set txc [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *u_mmcm/CLKOUT1}]]
    set_clock_groups -asynchronous \
        -group [get_clocks board_clk] -group $rxc -group $txc \
        -group [get_clocks tck_bscan]
    read_xdc $root/constraints/spw_cdc.xdc
    set bit  $example_dir/spw_arty_a7100t_top_fast.bit
    set trpt $example_dir/timing_verilog_fast.rpt
    set urpt $example_dir/utilization_verilog_fast.rpt
} else {
    read_xdc $example_dir/arty_a7100t.xdc
    synth_design -top spw_arty_a7100t_top -part $part -include_dirs $fcapz/rtl
    set bit  $example_dir/spw_arty_a7100t_top.bit
    set trpt $example_dir/timing_verilog.rpt
    set urpt $example_dir/utilization_verilog.rpt
}

opt_design
place_design
route_design
report_timing_summary -file $trpt
report_utilization    -file $urpt
write_bitstream -force $bit

puts "\n=== Verilog build complete: $bit ==="
