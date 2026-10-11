# DE25-Nano (Agilex 5) SpaceWire Loopback Example

Hardware example for **SpaceWire Reloaded** on the Terasic DE25-Nano
(Intel/Altera Agilex 5 E-series SoC FPGA, `A5EB013BB23BE4SR1`). A single
`spw_axi_top` SpaceWire link runs in internal loopback. It is driven by the same
`spw_loopback_axi` engine as the [Arty A7-100T example](../arty_a7100t/README.md),
and the link and self-check status is shown on the board LEDs. The design comes in
**both Verilog and VHDL** and tests itself: no host is needed after programming.
With a host, the same [fpgacapZero](https://github.com/lcapossio/fpgacapZero)
("fcapz") JTAG verification as on the Arty board runs over the board's
USB-Blaster III.

The point of this example is portability. The SpaceWire core and the engine are
the same vendor-neutral RTL that runs on Artix-7. The Intel-specific parts, the
configuration reset release and the fcapz JTAG debug cores, are isolated in
wrappers (see [Vendor-specific parts](#vendor-specific-parts)).

## What it does

- On power-up (or `KEY0`), the engine acts as the **AXI-Lite master**. It brings the link
  up (`CONTROL`/`TXDIVCNT`), reads back the SpaceWire `CORE_ID` and polls
  `STATUS`.
- It then runs the fabric **self-check**: 4 back-to-back packets of 16 PRBS
  bytes + EOP go out over the looped-back link and are checked on the way in
  (a dropped, duplicated or corrupted character fails the check).
- The link runs from the board's 50 MHz clock (`CLOCK1_50`) in one clock
  domain (generic RX/TX front ends). It runs at **10 Mbit/s**
  (`LINK_TXDIVCNT = 4`: 50 MHz / 5), and the core derives its SpaceWire reset,
  disconnect and 10 Mbit/s start-up timing from `SYS_CLOCK_HZ = 50e6`.

Bring-up and the self-check start on their own. The engine's AXI4 host port is
also connected to the fcapz EJTAG-AXI bridge, so a host can take over over JTAG
(see [Host verification over JTAG](#host-verification-over-jtag-fcapz)).

## Status LEDs

The DE25-Nano LEDs are active-low (a lit LED means the pin is driven 0). The top-level
inverts the status bits, so a lit LED always means "true":

| LED | Meaning |
| --- | --- |
| `LEDR0` | AXI-Lite bring-up sequence completed |
| `LEDR1` | SpaceWire link running |
| `LEDR2` | self-check done |
| `LEDR3` | self-check passed |

All four lit = link up and loopback self-check passed. `KEY0` resets the design.

## Pins

From the Terasic DE25-Nano User Manual (Sep 5, 2025), Tables 3-6, 3-9 and 3-10;
assigned in [`de25_nano_pins.tcl`](de25_nano_pins.tcl):

| Port | Board signal | Pin | I/O standard |
| --- | --- | --- | --- |
| `clk` | `CLOCK1_50` (50 MHz) | `PIN_V16` | 3.3-V LVCMOS |
| `btn[0]` | `KEY0` (reset, active-low) | `PIN_C8` | 3.3-V LVCMOS |
| `btn[1]` | `KEY1` (visible on the EIO only) | `PIN_C11` | 3.3-V LVCMOS |
| `led[3:0]` | `LEDR[3:0]` (active-low) | `PIN_DP23`, `PIN_DN22`, `PIN_DJ32`, `PIN_DF35` | 1.1 V |

## Files

| File | Purpose |
| --- | --- |
| `rtl/spw_de25_nano_top.v` / `.vhd` | Top-level (reset, loopback + error injection, engine, debug, LEDs) |
| `rtl/intel/de25_reset_release.v` | Vendor wrapper: Agilex configuration reset release (Quartus only) |
| `rtl/intel/de25_reset_release_ip.ip` | Altera Reset Release IP used by the wrapper |
| `rtl/intel/de25_debug.v` | Vendor wrapper: fcapz Intel ELA, EIO and EJTAG-AXI cores (Quartus only) |
| `de25_nano.sdc` | Timing constraints (50 MHz `clk`) |
| `de25_nano_pins.tcl` | Pin and I/O-standard assignments |
| `build_de25.tcl` | Quartus project/compile script (driven by `build.py`) |
| `build.py` | Build (and optional JTAG program) launcher |
| `host_loopback_test.py` | fcapz host verification (wraps the Arty script with the `usb_blaster` backend) |
| `ela_capture_demo.py` | fcapz ELA capture of the live D/S lines (wraps the Arty script) |
| `tb/` | Board-level cocotb sim, Verilog (Icarus) and VHDL (GHDL), plus vendor-wrapper sim stubs |

The loopback engine and the host scripts are shared with the Arty example
([`../arty_a7100t/rtl/spw_loopback_axi.v`](../arty_a7100t/rtl/spw_loopback_axi.v) / `.vhd`),
and so is the fpgacapZero submodule (`examples/arty_a7100t/fpgacapZero`, needed
for the Quartus build: `git submodule update --init examples/arty_a7100t/fpgacapZero`).

## Vendor-specific parts

Agilex devices release fabric sectors at different times as configuration
finishes, so user logic must be held in reset until the SDM reports that the
whole device is in user mode. The top-level gets this `ninit_done` signal from
`de25_reset_release`. It synchronizes the signal to `clk` with two flops and ORs it into the
synchronous reset, together with a power-on pulse and the synchronized `KEY0`.

- **Quartus:** `rtl/intel/de25_reset_release.v` instantiates the Altera
  **Reset Release IP** (`altera_s10_user_rst_clkgate`). The packaged IP is used
  rather than its underlying atom because Quartus's Agilex 5 design rule
  RES-10204 requires exactly one Reset Release IP per project. The build copies
  the `.ip` file into the project directory so the generated IP HDL stays out
  of the source tree.
- **Simulation:** `tb/de25_reset_release_sim.v` / `.vhd` are behavioral stubs with the same
  module/entity name: `ninit_done` is high for the first 500 ns.
- **Another vendor:** provide a different implementation of this one-output
  module (or a stub that ties `ninit_done` low where the device has no such
  requirement).

The JTAG debug cores sit behind a second wrapper, `de25_debug`. The top-level
only sees a vendor-neutral interface: an AXI4 master, a 16-bit logic-analyzer
probe and 8 EIO bits in and out.

- **Quartus:** `rtl/intel/de25_debug.v` maps it onto the fcapz Intel wrappers,
  which use `sld_virtual_jtag`. The instance map is the same as the fpgacapZero
  DE25-Nano reference design:

  | `sld_virtual_jtag` instance | Core |
  | --- | --- |
  | 1 | ELA control/registers |
  | 2 | ELA burst readout |
  | 3 | EIO |
  | 4 | EJTAG-AXI bridge -> loopback engine |

- **Simulation:** `tb/de25_debug_sim.v` / `.vhd` keep the AXI4 master idle and
  the EIO outputs at 0, which is how the design runs with no host attached.
- **Another vendor:** use the matching fcapz wrappers (`*_xilinx7`, `*_ecp5`,
  ...) behind the same ports.

The VHDL top declares both wrappers as components. Quartus binds them to the
Verilog wrappers (mixed-language build), and GHDL binds them to the VHDL stubs.

## Build

Quartus Prime Pro (Agilex 5 support; built with 26.1) must be on `PATH`
(`quartus_sh`, plus `quartus_pgm` to program), or pass `--quartus-bin` pointing at its `bin64`
directory. The launcher stops with an error if the tools cannot be found.

```sh
python build.py quartus --dry-run                        # check tools and sources
python build.py quartus                                  # Verilog, full compile -> .sof
python build.py quartus --hdl vhdl                       # VHDL build
python build.py quartus --flow synth                     # synthesis only (quick check)
python build.py quartus --program                        # compile, then program over JTAG
python examples/de25_nano/build.py --quartus-bin <dir>   # launcher with all options
```

The project and all generated files go to `quartus/de25_nano_<hdl>/` at the
repository root. The programming file is
`quartus/de25_nano_<hdl>/output/spw_de25_nano_top.sof`. Quartus is limited to
half the machine's cores (`--jobs` overrides this).

## Simulate (no board)

A board-level cocotb test drives only the real board pins (50 MHz clock, `KEY`
buttons) of the actual top-level, with the reset-release and debug stubs in
place of the vendor wrappers (no JTAG host attached). It checks what you would
see on the LEDs:

- while `ninit_done` is high, the design is held in reset and all LEDs are off;
- the reset releases after `ninit_done` falls, and all four LEDs light
  (bring-up, link, self-check done and passed) and stay lit;
- pressing `KEY0` turns every LED off, and releasing it brings the link back
  up and passes the self-check again.

```sh
python -m pytest examples/de25_nano/tb -k verilog                            # Icarus
SPW_RUN_VHDL_COCOTB=1 python -m pytest examples/de25_nano/tb -k vhdl         # GHDL
```

These tests are part of `python build.py test` (and `--hdl vhdl`) and run in CI.
In simulation all four LEDs light about 108 µs after the reset release, in both
languages.

## Program and check on the board

```sh
python build.py quartus --program
```

or program an existing `.sof` with the Quartus Programmer (JTAG, cable
"DE25-Nano"). All four `LEDR0`–`LEDR3` lit = pass.

## Host verification over JTAG (fcapz)

With the board programmed, the fcapz host package (`pip install` the
fpgacapZero host, 0.4.9 or later) talks to the design over the on-board
USB-Blaster III through Quartus `quartus_stp` (fcapz `usb_blaster` backend;
`quartus_stp` must be on `PATH`, or pass `--quartus-stp <path>`). The checks are
the Arty example's, run unchanged:

```sh
python examples/de25_nano/host_loopback_test.py              # identity, CORE_ID, self-check, data-mover, EIO
python examples/de25_nano/host_loopback_test.py --inject     # transmit-side error injection + recovery
python examples/de25_nano/host_loopback_test.py --timecode   # TimeCode loopback
python examples/de25_nano/host_loopback_test.py --eep        # EEP vs EOP round-trip
python examples/de25_nano/host_loopback_test.py --loadfault  # fault under load + clean recovery
python examples/de25_nano/host_loopback_test.py --stress 60  # back-to-back PRBS soak
python examples/de25_nano/ela_capture_demo.py                # ELA capture of the D/S lines -> VCD
```

Probe map (the same in the Verilog and VHDL tops):

| Core | Bits |
| --- | --- |
| ELA `[7:0]` | `spw_do`, `spw_so`, `spw_di`, `spw_si` (bits 7..4), bring-up, link, self-check done, pass (bits 3..0) |
| ELA `[15:8]` | received N-Char byte |
| EIO in | bit 0 link running, 1 bring-up, 2 self-check done, 3 pass, 4 `KEY0` pressed, 5 `KEY1` pressed |
| EIO out | bit 4 = ELA external trigger |

Results measured on the board are listed under [Hardware results](#hardware-results).

## FPGA resource usage and timing

Test conditions: Quartus Prime Pro 26.1, `A5EB013BB23BE4SR1` (DE25-Nano;
device timing models Preliminary), full compile (synthesis, place and route,
timing analysis), `clk` constrained at 50 MHz and JTAG TCK (`altera_reserved_tck`)
at 24 MHz, generic RX/TX front ends (`RXIMPL = TXIMPL = 0`), worst case across all
timing corners. The design is fully constrained (no unconstrained clocks or
ports), and both builds have no critical warnings.

Whole design (SpaceWire core, loopback engine, fcapz debug cores, reset logic):

| Build | ALMs | Registers | RAM blocks (bits) | DSP / PLL | Pins | `clk` setup / hold slack | `clk` Fmax | TCK Fmax |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Verilog | 4,031 / 46,800 | 6,135 | 5 (86,016) | 0 / 0 | 7 | +15.169 / +0.044 ns | 207 MHz | 49.7 MHz |
| VHDL | 4,015 / 46,800 | 6,096 | 5 (86,016) | 0 / 0 | 7 | +15.707 / +0.044 ns | 233 MHz | 49.7 MHz |

By entity (Quartus fitter "ALMs needed"):

| Entity | Verilog ALMs / registers / M20K | VHDL ALMs / registers / M20K |
| --- | --- | --- |
| SpaceWire core (`spw_axi_top`) | 227 / 292 / 2 | 227 / 294 / 2 |
| Loopback engine (`spw_loopback_axi`) | 598 / 550 / 0 | 554 / 542 / 0 |
| fcapz debug (`de25_debug`: ELA 16 x 1024, EIO, EJTAG-AXI) | 3,118 / 4,769 / 3 | 3,145 / 4,769 / 3 |

The fcapz debug cores are most of the design. The SpaceWire core itself is about
230 ALMs plus its two RX/TX FIFO RAMs. Fmax is the Quartus restricted Fmax of the
slowest corner. A full compile takes about 4.5 minutes on a 16-core machine
(8 Quartus processors); synthesis alone takes about 1 minute.

## Hardware results

Measured on a DE25-Nano (`A5EB013BB23BE4SR1`, on-board USB-Blaster III) on
2026-09-24, with fcapz host 0.4.9 and Quartus Prime Pro 26.1 `quartus_stp`. The
same results were obtained for the Verilog and VHDL builds; each run programs
the board first.

| Check | Result |
| --- | --- |
| LEDs after configuration | all four lit (bring-up, link, self-check done, passed) |
| Identity / `CORE_ID` / scratch | `SPWL`, `SPWR`, HDL fingerprint `V` / `H`, no aliasing at 0x100 |
| Power-on self-check | 4 packets x (16 PRBS + EOP): TX = RX = 68, 0 errors |
| Host data-mover | 5-byte packet + EOP looped back intact |
| EIO | `0x0F` (link, bring-up, done, pass) |
| Error injection | freeze -> `errdisc`, invert D -> `erresc`; link drops and recovers |
| TimeCodes | 4/4 round-tripped |
| EEP / EOP | EEP arrives with `tuser = 1`, EOP with `tuser = 0` |
| Fault under load | detected mid-stream; clean recovery, no new errors |
| PRBS soak (10 Mbit/s, 10 s, straight after the fault-under-load run) | ~585,000 back-to-back packets, ~9.95 M characters, 0 errors, ~0.99 MChar/s |
| PRBS soak (fresh configuration, 20 s) | 1,167,326 packets, 19.8 M characters, 0 errors |
| ELA capture (50 MHz sampling) | D/S toggling (about 5 samples per bit), `spw_do == spw_di` and `spw_so == spw_si` in every sample |

The soak right after the fault-under-load run is the hardware regression for the
self-check restart fix (the engine flushes the stale tail of a stopped run
before restarting). Without the fix, that run reported millions of errors.

## Author and License

Author: Leonardo Capossio - [bard0 design](https://www.bard0.com) - hello@bard0.com.
License: LGPL-2.1-or-later.
