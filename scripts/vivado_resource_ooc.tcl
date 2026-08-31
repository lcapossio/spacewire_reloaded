# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Leonardo Capossio - bard0 design
# Author: Leonardo Capossio - bard0 design - hello@bard0.com
#
# Out-of-context Vivado resource/timing report for spw_axi_top on the Arty
# A7-100T part. Reports post-route LUT/FF/BRAM/DSP utilization and the achieved
# per-clock-domain Fmax. The three clocks (clk/rxclk/txclk) are true CDC
# crossings and are timed as mutually asynchronous.
#
# Run once per configuration/language from the repository root, e.g.:
#   vivado -mode batch -nojournal -nolog -source scripts/vivado_resource_ooc.tcl \
#          -tclargs verilog generic build/ooc/vlog_generic
#   vivado -mode batch -nojournal -nolog -source scripts/vivado_resource_ooc.tcl \
#          -tclargs verilog fast    build/ooc/vlog_fast
#   vivado -mode batch -nojournal -nolog -source scripts/vivado_resource_ooc.tcl \
#          -tclargs vhdl    generic build/ooc/vhdl_generic
#   vivado -mode batch -nojournal -nolog -source scripts/vivado_resource_ooc.tcl \
#          -tclargs vhdl    fast    build/ooc/vhdl_fast
#
# Each run prints "RESULT <lang> <cfg> <clock> slack=<ns> fmax=<MHz>" lines and
# writes util.rpt / timing.rpt into <outdir>.

set part xc7a100tcsg324-1
set lang   [lindex $argv 0]
set cfg    [lindex $argv 1]
set outdir [lindex $argv 2]
file mkdir $outdir

set vsrc {
    rtl/verilog/syncdff.v rtl/verilog/spwram.v rtl/verilog/spwlink.v
    rtl/verilog/spwxmit.v rtl/verilog/spwxmit_fast.v rtl/verilog/spwrecv.v
    rtl/verilog/spwrecvfront_generic.v rtl/verilog/spwrecvfront_fast.v
    rtl/verilog/spwstream.v rtl/verilog/spw_axis_tx.v rtl/verilog/spw_axis_rx.v
    rtl/verilog/spw_axi_lite_regs.v rtl/verilog/spw_axi_top.v
}
set hsrc {
    rtl/vhdl/spwpkg.vhd rtl/vhdl/spwlink.vhd rtl/vhdl/spwrecv.vhd rtl/vhdl/spwxmit.vhd
    rtl/vhdl/spwxmit_fast.vhd rtl/vhdl/spwrecvfront_generic.vhd rtl/vhdl/spwrecvfront_fast.vhd
    rtl/vhdl/syncdff.vhd rtl/vhdl/spwram.vhd rtl/vhdl/spwstream.vhd
    rtl/vhdl/spw_axis_tx.vhd rtl/vhdl/spw_axis_rx.vhd rtl/vhdl/spw_axi_lite_regs.vhd
    rtl/vhdl/spw_axi_top.vhd syn/vhdl/spw_axi_synth_wrappers.vhd
}

if {$lang eq "verilog"} {
    read_verilog $vsrc
    set top spw_axi_top
    if {$cfg eq "generic"} {
        set gopt {-generic SYS_CLOCK_HZ=20000000 -generic TX_CLOCK_HZ=20000000 -generic RXIMPL=0 -generic TXIMPL=0 -generic RXCHUNK=1}
    } else {
        set gopt {-generic SYS_CLOCK_HZ=50000000 -generic TX_CLOCK_HZ=100000000 -generic RXIMPL=1 -generic TXIMPL=1 -generic RXCHUNK=4}
    }
    synth_design -top $top -part $part -mode out_of_context {*}$gopt
} else {
    read_vhdl -vhdl2008 $hsrc
    if {$cfg eq "generic"} { set top spw_axi_top_synth_generic } else { set top spw_axi_top_synth_fast }
    synth_design -top $top -part $part -mode out_of_context
}

# Probe Fmax with an aggressive common period; the three clock domains are true
# CDC crossings (through syncdff), so time them as mutually asynchronous.
create_clock -name clk   -period 5.0 [get_ports clk]
create_clock -name rxclk -period 5.0 [get_ports rxclk]
create_clock -name txclk -period 5.0 [get_ports txclk]
set_clock_groups -asynchronous -group [get_clocks clk] -group [get_clocks rxclk] -group [get_clocks txclk]

opt_design
place_design
route_design

report_utilization -file $outdir/util.rpt
report_timing_summary -file $outdir/timing.rpt

foreach c {clk rxclk txclk} {
    set paths [get_timing_paths -setup -max_paths 1 -nworst 1 -to [get_clocks $c]]
    if {[llength $paths] > 0} {
        set s [get_property SLACK [lindex $paths 0]]
        set fmax [expr {1000.0 / (5.0 - $s)}]
        puts [format "RESULT %s %s %-5s slack=%.3f fmax=%.1fMHz" $lang $cfg $c $s $fmax]
    }
}
puts "OOC_DONE $lang $cfg"
