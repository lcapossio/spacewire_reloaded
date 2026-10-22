# SpaceWire Reloaded - timing constraints

Clock-domain-crossing (CDC) timing constraints for the SpaceWire core. They
matter only with the fast front ends (`RXIMPL`/`TXIMPL` = fast), where `rxclk`
and `txclk` can differ from the system clock `clk`. The core crosses clock
domains in five ways:

1. The two-flip-flop synchronizer [`syncdff`](../rtl/vhdl/syncdff.vhd):
   `rxclk -> clk` in `spwrecvfront_fast` (receive head pointer, activity
   counter) and `clk <-> txclk` in `spwxmit_fast` (handshake flips, enable,
   divider-safe flag).
2. The asynchronous resets of the reset synchronizers in the other domain
   (`syncrx_reset` in `rxclk`, `synctx_*` in `txclk`).
3. The 8-deep receive buffer: LUTRAM written on `rxclk`, read into a `clk`
   register. The gray-coded head pointer advances only after a word is written.
4. The transmit token and divider registers: loaded on `clk`, copied on `txclk`
   only after the handshake flip has crossed a `syncdff`.
5. The D/S line samplers, whose input is asynchronous by definition.

The constraints give 1-4 a datapath-only maximum delay and make 5 a false path.

## Files

| File                    | Tool flow                                   |
|-------------------------|---------------------------------------------|
| `spw_cdc.xdc`           | Xilinx Vivado                               |
| `spw_cdc.sdc`           | Intel Quartus (Prime / TimeQuest)           |
| `spw_cdc_lattice.sdc`   | Lattice Radiant / Diamond (Synplify Pro)    |

`spw_cdc.xdc` is verified: the Arty A7-100T fast build
([`examples/arty_a7100t`](../examples/arty_a7100t)) reads it, and
`report_exceptions` shows every crossing above covered, none ignored, and no
same-domain path affected, in both the Verilog and VHDL netlists. The Intel and
Lattice files are still **templates**: they constrain only the `syncdff`
crossings (1) and have not been run through those tools in this repo. Confirm
the cell-name patterns against your post-synthesis netlist, since hierarchy
separators and `*_reg` suffixes vary by tool and version.

## How to use

1. Create the three core clocks (`clk`, `rxclk`, `txclk`) in your board/project
   constraints or clocking IP. These files deliberately do **not** create clocks.
2. Add the matching file for your tool to the project, read **after** the clock
   definitions. Keep `clk`, `rxclk` and `txclk` out of separate asynchronous
   clock groups (and do not false-path between them): clock groups and false
   paths take priority over `set_max_delay`, so they would silently disable
   these bounds. In Vivado, check with `report_exceptions -ignored`.
   `spw_cdc.xdc` must stay plain XDC: Vivado rejects Tcl control flow
   (`if`, `foreach`, `puts`) in an XDC file and drops the rest of it.
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
can never latch an illegal intermediate pointer value; the buffer data and the
transmit token are only read after a synchronized pointer or handshake says
they are stable - correctness does not depend on these constraints. They exist to bound skew and latency and to stop the
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
