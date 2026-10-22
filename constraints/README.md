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

Vivado and Radiant get a datapath-only maximum delay on 1-4 and a false path on
5. Quartus has no datapath-only delay, so its file false-paths each crossing
and bounds the routing with `set_net_delay` and `set_max_skew`.

## Files

| File                    | Tool flow                                   |
|-------------------------|---------------------------------------------|
| `spw_cdc.xdc`           | Xilinx Vivado                               |
| `spw_cdc.sdc`           | Intel Quartus Prime Pro                     |
| `spw_cdc_lattice.sdc`   | Lattice Radiant                             |

Verification status (fast configuration, Verilog and VHDL netlists):

- `spw_cdc.xdc`: verified in the Arty A7-100T fast build
  ([`examples/arty_a7100t`](../examples/arty_a7100t)). `report_exceptions`
  shows every crossing covered, none ignored, and no same-domain path affected.
  The Arty fast bitstreams pass the hardware suite.
- `spw_cdc.sdc`: verified with Quartus Pro 26.1 on Agilex 5
  (`A5EB013BB23BE4SR1`) in an out-of-context fast-core project. Without it,
  78 setup/recovery paths cross between the three clocks and three clock
  pairs fail timing.
  With it, no crossing path is left and no constraint is ignored, and the
  same-domain path counts match a clocks-only analysis of the same netlist.
- `spw_cdc_lattice.sdc`: written in the Radiant constraint syntax but **not yet
  run through Radiant** here. Check `sta_report_constraints` for constraints
  that matched nothing, and confirm the cell-name patterns against your
  synthesized netlist.

## How to use

1. Create the three core clocks (`clk`, `rxclk`, `txclk`) in your board/project
   constraints or clocking IP. These files deliberately do **not** create clocks.
2. Add the matching file for your tool to the project, read **after** the clock
   definitions. Keep `clk`, `rxclk` and `txclk` out of separate asynchronous
   clock groups (and do not false-path between them): clock groups and false
   paths take priority over `set_max_delay`, so they would silently disable
   these bounds (Vivado, Radiant). In Vivado, check with
   `report_exceptions -ignored`; in Quartus, `report_sdc -ignored`. The
   Quartus file's `set_net_delay`/`set_max_skew` bounds hold even under
   asynchronous clock groups. In the Lattice file, set the three clock-name
   variables at the top to your clock names.
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
