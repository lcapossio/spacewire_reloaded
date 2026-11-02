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

Crossings 1-3 and 5 on the receive side, and 1, 2 and 4 on the transmit side,
are in separate files, so each side can be used on its own.

Vivado and Radiant get a datapath-only maximum delay on 1-4 and a false path on
5. Quartus false-paths each crossing and bounds it with `set_data_delay` (its
datapath-only maximum delay) plus `set_max_skew` on the multi-bit groups.

## Files

| Tool flow               | Receive side (`rxclk` != `clk`) | Transmit side (`txclk` != `clk`) |
|-------------------------|---------------------------------|----------------------------------|
| Xilinx Vivado           | `spw_cdc_rx.xdc`                | `spw_cdc_tx.xdc`                 |
| Intel Quartus Prime Pro | `spw_cdc_rx.sdc`                | `spw_cdc_tx.sdc`                 |
| Lattice Radiant         | `spw_cdc_rx_lattice.sdc`        | `spw_cdc_tx_lattice.sdc`         |

Which files to add:

| Configuration                                      | Add            |
|----------------------------------------------------|----------------|
| `RXIMPL` fast, `rxclk` a different clock from `clk` | receive file   |
| `TXIMPL` fast, `txclk` a different clock from `clk` | transmit file  |
| Generic front end, or its clock wired to `clk`      | nothing for that side |

Leaving a side out when its clock is `clk` matters: the core allows
`rxclk = clk` and `txclk = clk`, and in that case the "crossing" paths are
ordinary same-clock paths. The receive file would then relax them (Vivado and
Radiant drop their hold checks, Quartus cuts them), and with the generic front
end its rules match nothing (Vivado rejects them).

With `rxclk = clk` the D/S line samplers (crossing 5) also lose their false
path. They normally sample top-level input ports, which stay untimed unless you
give them an input delay. If your design drives them from internal logic (for
example an internal loopback from the transmitter), add the sampler
`set_false_path` from the receive file yourself.

Verification status (fast configuration, Verilog and VHDL netlists):

- Vivado files: verified in the Arty A7-100T fast build
  ([`examples/arty_a7100t`](../examples/arty_a7100t)), which reads both.
  `report_exceptions` shows every crossing covered, none ignored, and no
  same-domain path affected. The Arty fast bitstreams pass the hardware suite.
  Synthesis-only checks cover the mixed configurations (fast receive with
  generic transmit, and the reverse) and `rxclk` wired to `clk`, each reading
  only the files the table above says.
- Quartus files: verified with Quartus Pro 26.1 on Agilex 5
  (`A5EB013BB23BE4SR1`) in out-of-context fast-core projects. With three
  separate clocks and no constraints, 78 setup/recovery paths cross between the
  clocks and three clock pairs fail timing. With both files, no crossing path
  is left, every `set_data_delay` finds its paths (including the receive buffer
  read through the mux) and meets them, and no constraint is ignored. With
  `rxclk` wired to `clk` and only the transmit file, the `clk` same-domain path
  counts match a clocks-only analysis of the same netlist.
- Radiant files: written in the Radiant constraint syntax but **not yet run
  through Radiant** here. Check `sta_report_constraints` for constraints that
  matched nothing, and confirm the cell-name patterns against your synthesized
  netlist.

## How to use

1. Create the core clocks (`clk`, and `rxclk`/`txclk` where they are separate
   clocks) in your board/project constraints or clocking IP. These files
   deliberately do **not** create clocks.
2. Add the files for your tool and configuration (table above), read **after**
   the clock definitions. Keep `clk`, `rxclk` and `txclk` out of separate
   asynchronous clock groups (and do not false-path between them): clock groups
   and false paths take priority over `set_max_delay`, so they would silently
   disable these bounds (Vivado, Radiant). In Vivado, check with
   `report_exceptions -ignored`; in Quartus, `report_sdc -ignored`, plus
   `report_timing -setup -data_delay` and `report_timing -recovery -data_delay`
   (the reset-synchronizer clears show up only in the recovery report). The Quartus `set_data_delay`/`set_max_skew`
   bounds hold even under asynchronous clock groups. In the Radiant files, set
   the clock-name variables at the top to your clock names.
   The `.xdc` files must stay plain XDC: Vivado rejects Tcl control flow
   (`if`, `foreach`, `puts`) in an XDC file and drops the rest of it.
3. Set `spw_cdc_max_delay_ns` (the same value in both files) to the period (ns)
   of the **fastest** clock that participates in a crossing. This bounds each
   crossing data path and its bit-to-bit skew to under one capture period.

The synchronizer flip-flops already carry vendor attributes in the RTL
(`ASYNC_REG` for Xilinx, `syn_preserve`/`syn_srlstyle` for Synplify/Lattice,
`preserve` for Intel, plus `keep`), so the registers survive synthesis with
their net names intact and the tool will not pack them into a shift register.

## Why the bounds are required

The crossings are safe by design **only together with** these bounds:

- The receive head pointer is **gray-coded** before it crosses
  (`spwrecvfront_fast`), so only one bit changes per increment. That holds at
  the destination only if successive changes arrive in order, i.e. the bit-to-bit
  skew stays under one capture period. Without a bound, `000 -> 001 -> 011` can
  be sampled as `010` if the first change is delayed long enough, and the reader
  would see a pointer ahead of the writer.
- The receive buffer word and the transmit token/divider registers are only read
  after a synchronized pointer or handshake flip says they are stable. That
  protects them only if their own path is shorter than the synchronizer's
  settling window, which the maximum delay guarantees.

The constraints also stop the tool from timing the crossings against the launch
clock as if they were synchronous. The activity counter `bitcnt` crosses as
binary on purpose: it is only change-detected to produce `inact`, can advance
faster than one step per system clock, and tolerates a transient mismatch that
self-corrects on the next cycle.

## Required rate rule

Independent of these constraints, the receive front end requires the incoming
SpaceWire bit rate to stay below `rxchunk * sysclk` (and below `2 * rxclk`). This
keeps the 8-deep receive buffer from overflowing and keeps the head pointer to at
most one step per system-clock sample, which is what makes the gray-coded
crossing sufficient. See the header of
[`spwrecvfront_fast.vhd`](../rtl/vhdl/spwrecvfront_fast.vhd) for the full timing
notes.
