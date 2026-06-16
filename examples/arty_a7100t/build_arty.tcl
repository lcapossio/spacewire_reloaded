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

read_xdc $example_dir/arty_a7100t.xdc

synth_design -top spw_arty_a7100t_top -part $part -include_dirs $fcapz/rtl
opt_design
place_design
route_design
report_timing_summary -file $example_dir/timing_verilog.rpt
report_utilization    -file $example_dir/utilization_verilog.rpt
write_bitstream -force $example_dir/spw_arty_a7100t_top.bit

puts "\n=== Verilog build complete: examples/arty_a7100t/spw_arty_a7100t_top.bit ==="
