# SpaceWire Reloaded - timing constraints

Clock-domain-crossing (CDC) timing constraints for the SpaceWire core. Every
crossing in the core passes through the two-flip-flop synchronizer
[`syncdff`](../rtl/vhdl/syncdff.vhd), so these files only need to constrain that
one cell type wherever it is instantiated:

- `rxclk -> clk` in `spwrecvfront_fast` (receive head pointer, activity counter,
  reset synchronizer).
- `clk <-> txclk` in `spwxmit_fast` (transmit handshake flips, reset, divider).

## Files

| File                    | Tool flow                                   |
|-------------------------|---------------------------------------------|
| `spw_cdc.xdc`           | Xilinx Vivado                               |
| `spw_cdc.sdc`           | Intel Quartus (Prime / TimeQuest)           |
| `spw_cdc_lattice.sdc`   | Lattice Radiant / Diamond (Synplify Pro)    |

They are **templates**: they were written for the correct command syntax and
intent of each tool but have not been run through those tools in this repo (no
FPGA back-end runs here yet - the `build.py vivado` flow is still a stub). Treat
them as a starting point and confirm the synchronizer cell-name pattern against
your post-synthesis netlist, since hierarchy separators and `*_reg` suffixes
vary by tool and version.

## How to use

1. Create the three core clocks (`clk`, `rxclk`, `txclk`) in your board/project
   constraints or clocking IP. These files deliberately do **not** create clocks.
2. Add the matching file for your tool to the project, read **after** the clock
   definitions.
3. Set `spw_cdc_max_delay_ns` to the period (ns) of the **fastest** clock that
   participates in a crossing. This conservatively bounds each crossing data path
   and its bit-to-bit skew to under one capture period.

The synchronizer flip-flops already carry vendor attributes in the RTL
(`ASYNC_REG` for Xilinx, `syn_preserve`/`syn_srlstyle` for Synplify/Lattice,
`preserve` for Intel, plus `keep`), so the registers survive synthesis with
their net names intact and the tool will not pack them into a shift register.

## Why these are enough

The receive head pointer is **gray-coded** before it crosses
(`spwrecvfront_fast`), so only one bit changes per increment and the destination
can never latch an illegal intermediate pointer value - correctness does not
depend on these constraints. They exist to bound skew and latency and to stop the
tool from analysing the asynchronous crossing against the launch clock. The
activity counter `bitcnt` crosses as binary on purpose: it is only
change-detected to produce `inact`, can advance faster than one step per system
clock, and tolerates a transient mismatch that self-corrects on the next cycle.

## Required rate rule

Independent of these constraints, the receive front end requires the incoming
SpaceWire bit rate to stay below `rxchunk * sysclk` (and below `2 * rxclk`). This
keeps the 8-deep receive buffer from overflowing and keeps the head pointer to at
most one step per system-clock sample, which is what makes the gray-coded
crossing sufficient. See the header of
[`spwrecvfront_fast.vhd`](../rtl/vhdl/spwrecvfront_fast.vhd) for the full timing
notes.
