# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# Vivado non-project mixed-language build of the Arty A7-100T SpaceWire loopback
# example: VHDL SpaceWire core + VHDL engine driven by the Verilog fpgacapZero
# vendor wrappers/TAP plumbing, which bind the VHDL fcapz_ela/fcapz_eio cores.
# Run via build.py --hdl vhdl, or directly:
#   vivado -mode batch -source examples/arty_a7100t/build_arty_vhdl.tcl

set part        xc7a100tcsg324-1
set example_dir [file normalize [file dirname [info script]]]
set root        [file normalize $example_dir/../..]
set fcapz       $example_dir/fpgacapZero
set spw         $root/rtl/vhdl

set_param project.enableUnifiedSimulation 0

read_vhdl -vhdl2008 [list \
    $fcapz/rtl/vhdl/pkg/fcapz_pkg.vhd \
    $fcapz/rtl/vhdl/pkg/fcapz_util_pkg.vhd \
    $fcapz/rtl/vhdl/core/fcapz_dpram.vhd \
    $fcapz/rtl/vhdl/core/fcapz_ela.vhd \
    $fcapz/rtl/vhdl/core/fcapz_eio.vhd \
    $spw/spwpkg.vhd \
    $spw/spwlink.vhd \
    $spw/spwrecv.vhd \
    $spw/spwxmit.vhd \
    $spw/spwxmit_fast.vhd \
    $spw/spwrecvfront_generic.vhd \
    $spw/spwrecvfront_fast.vhd \
    $spw/syncdff.vhd \
    $spw/spwram.vhd \
    $spw/spwstream.vhd \
    $spw/spw_axis_tx.vhd \
    $spw/spw_axis_rx.vhd \
    $spw/spw_axi_lite_regs.vhd \
    $spw/spw_axi_top.vhd \
    $example_dir/rtl/spw_loopback_axi.vhd \
    $example_dir/rtl/spw_arty_a7100t_top.vhd ]

read_verilog [list \
    $fcapz/rtl/reset_sync.v \
    $fcapz/rtl/dpram.v \
    $fcapz/rtl/trig_compare.v \
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
    $fcapz/rtl/fcapz_eio_xilinx7.v ]

set fast 0
if {[info exists ::env(SPW_FAST)] && $::env(SPW_FAST) eq "1"} { set fast 1 }

if {$fast} {
    read_xdc $example_dir/arty_a7100t_fast.xdc
    synth_design -top spw_arty_a7100t_top -part $part -include_dirs $fcapz/rtl \
        -generic RXIMPL=1 -generic TXIMPL=1 -generic RXCHUNK=2 -generic USE_MMCM=1
    set rxc [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *u_mmcm/CLKOUT0}]]
    set txc [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *u_mmcm/CLKOUT1}]]
    set_clock_groups -asynchronous \
        -group [get_clocks board_clk] -group $rxc -group $txc \
        -group [get_clocks tck_bscan]
    read_xdc $root/constraints/spw_cdc.xdc
    set bit  $example_dir/spw_arty_a7100t_top_vhdl_fast.bit
    set trpt $example_dir/timing_vhdl_fast.rpt
    set urpt $example_dir/utilization_vhdl_fast.rpt
} else {
    read_xdc $example_dir/arty_a7100t.xdc
    synth_design -top spw_arty_a7100t_top -part $part -include_dirs $fcapz/rtl
    set bit  $example_dir/spw_arty_a7100t_top_vhdl.bit
    set trpt $example_dir/timing_vhdl.rpt
    set urpt $example_dir/utilization_vhdl.rpt
}

opt_design
place_design
route_design
report_timing_summary -file $trpt
report_utilization    -file $urpt
write_bitstream -force $bit

puts "\n=== VHDL build complete: $bit ==="
