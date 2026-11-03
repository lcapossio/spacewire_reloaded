# PolarFire SoC Discovery Kit SpaceWire Loopback Example

Hardware example for **SpaceWire Reloaded** on the Microchip PolarFire SoC
Discovery Kit (MPFS-DISCO-KIT, `MPFS095T-1FCSG325E`). A single `spw_axi_top`
SpaceWire link runs in internal loopback, driven by the same
`spw_loopback_axi` engine as the [Arty A7-100T](../arty_a7100t/README.md) and
[DE25-Nano](../de25_nano/README.md) examples, and the link and self-check
status is shown on the board LEDs. The design comes in **both Verilog and
VHDL**, uses the FPGA fabric only (the MSS, the RISC-V processor subsystem, is
left unconfigured) and tests itself: no host is needed after programming. With
a host, the same [fpgacapZero](https://github.com/lcapossio/fpgacapZero)
("fcapz") JTAG verification as on the other boards runs over the board's
embedded FlashPro5.

The SpaceWire core and the engine are the same vendor-neutral RTL that runs on
Artix-7 and Agilex 5. The Microchip-specific parts, the fabric power-on reset
and the fcapz JTAG debug cores on the PolarFire user JTAG primitive, are
isolated in two wrappers (see [Vendor-specific parts](#vendor-specific-parts)).

## Index

- [What it does](#what-it-does)
- [Status LEDs](#status-leds)
- [Pins](#pins)
- [Files](#files)
- [Vendor-specific parts](#vendor-specific-parts)
  - [Power-on reset](#power-on-reset)
- [Build](#build)
- [Simulate (no board)](#simulate-no-board)
- [Program and check on the board](#program-and-check-on-the-board)
- [Host verification over JTAG (fcapz)](#host-verification-over-jtag-fcapz)
- [FPGA resource usage and timing](#fpga-resource-usage-and-timing)
- [Hardware results](#hardware-results)
- [Author and License](#author-and-license)

## What it does

- On power-up (or `SWITCH1`), the engine acts as the **AXI-Lite master**. It
  brings the link up (`CONTROL`/`TXDIVCNT`), reads back the SpaceWire
  `CORE_ID` and polls `STATUS`.
- It then runs the fabric **self-check**: 4 back-to-back packets of 16 PRBS
  bytes + EOP go out over the looped-back link and are checked on the way in
  (a dropped, duplicated or corrupted character fails the check).
- The link runs from the board's 50 MHz reference clock (`REF_CLK_50MHz`) in
  one clock domain (generic RX/TX front ends). It runs at **10 Mbit/s**
  (`LINK_TXDIVCNT = 4`: 50 MHz / 5), and the core derives its SpaceWire reset,
  disconnect and 10 Mbit/s start-up timing from `SYS_CLOCK_HZ = 50e6`.

Bring-up and the self-check start on their own. The engine's AXI4 host port is
also connected to the fcapz EJTAG-AXI bridge, so a host can take over over
JTAG (see [Host verification over JTAG](#host-verification-over-jtag-fcapz)).

## Status LEDs

The Discovery Kit LEDs are active-high (a lit LED means the pin is driven 1):

| LED | Meaning |
| --- | --- |
| `LED1` | AXI-Lite bring-up sequence completed |
| `LED2` | SpaceWire link running |
| `LED3` | self-check done |
| `LED4` | self-check passed |

All four lit = link up and loopback self-check passed. `SWITCH1` resets the
design.

## Pins

Pins and bank voltages follow Microchip's Discovery Kit reference design
(`MPFS_DISCOVERY_KIT_BOARD_MISC.pdc` / `_BANK_SETTINGS.pdc`), as used by the
fpgacapZero `mpfs_disco_kit` example; assigned in
[`mpfs_disco_kit_io.pdc`](mpfs_disco_kit_io.pdc) (Bank 0 at 1.8 V, Bank 1 at
3.3 V):

| Port | Board signal | Pin |
| --- | --- | --- |
| `clk` | `REF_CLK_50MHz` (50 MHz) | `R18` (LVCMOS18) |
| `btn[0]` | `SWITCH1` (reset, active-low) | `T19` |
| `btn[1]` | `SWITCH2` (visible on the EIO only, active-low) | `U18` |
| `led[3:0]` | `LED4`..`LED1` (active-high) | `U21`, `U20`, `V17`, `T18` |
| `TCK`, `TMS`, `TDI`, `TRSTB`, `TDO` | dedicated JTAG pins | bound by Libero (no PDC entry) |

## Files

| File | Purpose |
| --- | --- |
| `rtl/spw_mpfs_disco_kit_top.v` / `.vhd` | Top-level (reset, loopback + error injection, engine, debug, LEDs) |
| `rtl/microchip/mpfs_por.v` | Vendor wrapper: fabric power-on reset (`FABRIC_POR_N` of the PolarFire `INIT` block, Libero only) |
| `rtl/microchip/mpfs_debug.v` | Vendor wrapper: fcapz ELA, EIO and EJTAG-AXI on the PolarFire UJTAG (Libero only) |
| `mpfs_disco_kit.sdc` | Timing constraints (50 MHz `clk`, 6 MHz JTAG TCK, bounds on the TCK <-> `clk` crossings) |
| `mpfs_disco_kit_io.pdc` | Pin, bank-voltage and I/O assignments |
| `build_mpfs.tcl` | Libero project/compile script (driven by `build.py`) |
| `program_mpfs.tcl` | Libero programming script (`build.py --program-only`) |
| `build.py` | Build (and optional programming) launcher |
| `host_loopback_test.py` | fcapz host verification (wraps the Arty script with the `ftdi` backend) |
| `ela_capture_demo.py` | fcapz ELA capture of the live D/S lines (wraps the Arty script) |
| `tb/` | Board-level cocotb sim, Verilog (Icarus) and VHDL (GHDL), plus the vendor-wrapper sim stubs |

The loopback engine and the host scripts are shared with the Arty example
([`../arty_a7100t/rtl/spw_loopback_axi.v`](../arty_a7100t/rtl/spw_loopback_axi.v) / `.vhd`),
and so is the fpgacapZero submodule (`examples/arty_a7100t/fpgacapZero`,
needed for the Libero build:
`git submodule update --init examples/arty_a7100t/fpgacapZero`).

## Vendor-specific parts

There are two Microchip-specific parts, each a wrapper under `rtl/microchip/`
with behavioral stubs for simulation under `tb/`: the fabric power-on reset
(`mpfs_por`, see [Power-on reset](#power-on-reset)) and the fcapz debug cores
(`mpfs_debug`).

PolarFire has a single user JTAG primitive (`UJTAG`) per device, so every
fcapz core has to share it. fcapz has no PolarFire EJTAG-AXI wrapper, and its
`fcapz_ela_polarfire` wrapper owns the `UJTAG` itself, so the example wraps the
vendor-neutral fcapz cores directly in `rtl/microchip/mpfs_debug.v`:

| User instruction | fcapz chain | Core |
| --- | --- | --- |
| `USER1` (IR `0x20`) | 1 | `fcapz_debug_multi` core manager: slot 0 = ELA (16 bits x 1024), slot 1 = EIO (8 in / 8 out) |
| `USER2` (IR `0x21`) | 2 | `fcapz_ejtagaxi` bridge (AXI4 master -> loopback engine), behavioral async FIFOs |

These are the fcapz host's PolarFire IR codes. IR `0x10`/`0x11` are avoided:
on PolarFire SoC the MSS debug module answers there.

- **Libero:** `rtl/microchip/mpfs_debug.v` instantiates `jtag_tap_polarfire`
  (the `UJTAG` decode) once and puts the two cores behind it. The five JTAG
  pins are ports of the top level; Libero binds them to the dedicated JTAG
  pins.
- **Simulation:** `tb/mpfs_debug_sim.v` / `.vhd` keep the AXI4 master idle,
  the EIO outputs and `TDO` at 0, which is how the design runs with no host
  attached.
- **Another vendor:** the top-level only sees the vendor-neutral interface (an
  AXI4 master, a 16-bit logic-analyzer probe and 8 EIO bits in and out), the
  same as the DE25-Nano's `de25_debug`.

The VHDL top declares both wrappers as components. Libero binds them to the
Verilog wrappers (mixed-language build), and GHDL binds them to the VHDL stubs.

### Power-on reset

PolarFire fabric registers have no power-up value: Synplify ignores register
initial values, and **reprogramming the device over JTAG keeps the registers'
previous contents**. Measured on the Discovery Kit: with `SCRATCH` written to
`0x5EEDF00D` and the self-check left running in loop mode, reprogramming the
same bitstream left both unchanged and the self-check still counting. A reset
built only from fabric registers (a shift register preset to ones, or a
counter assumed to start at 0) can therefore start already released, and the
design then runs from stale state.

`rtl/microchip/mpfs_por.v` instantiates the device `INIT` block, whose
`FABRIC_POR_N` is low while the fabric is initialized, including after every
reprogram. In the top-level it clears the reset synchronizer and a 16-clock
counter asynchronously (no register state can be trusted, and `clk` may not be
running yet). Release is synchronous: reset is held for 16 clocks after the
synchronized release, then follows the synchronized `SWITCH1`. The same signal,
inverted, drives the fcapz core manager's `hub_por` input in `mpfs_debug`: it
resets the manager and every slot through fcapz's own reset synchronizers, so
the manager's reset epochs and owner token start from known values after every
reprogram. These two are the only asynchronous resets in the design. On
another vendor, the wrapper becomes
that device's configuration-done or power-on reset (on the DE25-Nano, the
Agilex reset release IP). In simulation `tb/mpfs_por_sim.v` / `.vhd` hold
`fabric_por_n` low for the first 200 ns.

## Build

Libero SoC (built with 2025.2) must be on `PATH` (`libero`), or pass
`--libero-bin` pointing at its `Designer/bin` directory. The launcher stops with
an error if Libero cannot be found. Synthesis needs the Synplify licence: if
Synplify reports `synplifypro_actel` as unavailable, point it at your licence
server, for example `SNPSLMD_LICENSE_FILE=1702@localhost` (the launcher prints
this hint when it sees that error).

```sh
python build.py libero --dry-run                              # check tools and sources
python build.py libero                                        # Verilog, full flow
python build.py libero --hdl vhdl                             # VHDL build
python build.py libero --flow synth                           # synthesis only (quick check)
python build.py libero --program                              # build, then program the board
python examples/mpfs_disco_kit/build.py --program-only        # program the last build
python examples/mpfs_disco_kit/build.py --libero-bin <dir>    # launcher with all options
```

The project and all generated files go to `libero/mpfs_disco_kit_<hdl>/` at
the repository root; the launcher prints the resource usage and the worst
setup/hold slack per clock at the end.

## Simulate (no board)

A board-level cocotb test drives only the real board pins (50 MHz clock,
`SWITCH` buttons, idle JTAG pins) of the actual top-level, with the sim stubs
in place of the vendor wrappers (no JTAG host attached). It checks what you
would see on the LEDs:

- while the power-on reset holds the design, all LEDs are off;
- the reset releases 16 clocks after `fabric_por_n` (synchronized) goes high,
  `LED1` lights first, then all four
  (bring-up, link, self-check done and passed) light and stay lit;
- pressing `SWITCH1` turns every LED off, and releasing it brings the link back
  up and passes the self-check again.

```sh
python -m pytest examples/mpfs_disco_kit/tb -k verilog                       # Icarus
SPW_RUN_VHDL_COCOTB=1 python -m pytest examples/mpfs_disco_kit/tb -k vhdl    # GHDL
```

These tests are part of `python build.py test` (and `--hdl vhdl`) and run in
CI. In simulation all four LEDs light about 108 µs after the reset release, in
both languages.

## Program and check on the board

```sh
python build.py libero --program
```

or `python examples/mpfs_disco_kit/build.py --program-only` to program the
last build. Programming goes through the first FlashPro Libero finds, normally
the board's embedded FlashPro5; nothing else (an fcapz host, OpenOCD) may hold
its JTAG channel at that moment. Programming replaces whatever the device held,
including MSS firmware in eNVM. All four `LED1`–`LED4` lit = pass.

## Host verification over JTAG (fcapz)

With the board programmed, the fcapz host package talks to the design directly
over the embedded FlashPro5 (fcapz `ftdi` backend, `FtdiMpsseTransport`, FTDI
D2XX driver; no OpenOCD). On Windows that is the driver Microchip installs for
the FlashPro5, so fcapz and Libero share the programmer one at a time. The
checks are the Arty example's, run unchanged. Install the host from the
submodule so it matches the debug-core RTL in the build:
`python -m pip install ./examples/arty_a7100t/fpgacapZero`.

`host_loopback_test.py` programs the board first on every run (`--hdl`
selects the build, `--no-program` skips it), so each check starts from a
freshly configured design. The JTAG channel defaults to
`"Embedded FlashPro5 A"`, so other FTDI adapters (an Arty, say) can stay
plugged in.

```sh
python examples/mpfs_disco_kit/host_loopback_test.py              # identity, CORE_ID, self-check, data-mover, EIO
python examples/mpfs_disco_kit/host_loopback_test.py --inject     # transmit-side error injection + recovery
python examples/mpfs_disco_kit/host_loopback_test.py --timecode   # TimeCode loopback
python examples/mpfs_disco_kit/host_loopback_test.py --eep        # EEP vs EOP round-trip
python examples/mpfs_disco_kit/host_loopback_test.py --loadfault  # fault under load + clean recovery
python examples/mpfs_disco_kit/host_loopback_test.py --stress 60  # back-to-back PRBS soak
python examples/mpfs_disco_kit/ela_capture_demo.py                # ELA capture of the D/S lines -> VCD
```

Probe map (the same in the Verilog and VHDL tops, and the same as on the
DE25-Nano):

| Core | Bits |
| --- | --- |
| ELA `[7:0]` | `spw_do`, `spw_so`, `spw_di`, `spw_si` (bits 7..4), bring-up, link, self-check done, pass (bits 3..0) |
| ELA `[15:8]` | received N-Char byte |
| EIO in | bit 0 link running, 1 bring-up, 2 self-check done, 3 pass, 4 `SWITCH1` pressed, 5 `SWITCH2` pressed |
| EIO out | bit 4 = ELA external trigger |

## FPGA resource usage and timing

Full design (`spw_axi_top`, the `spw_loopback_axi` engine, the fcapz debug
cores and the reset logic, with I/O), Libero SoC 2025.2 (Synplify Pro
synthesis), `MPFS095T-1FCSG325E` (speed grade -1, core voltage 1.0 V, extended
temperature range), built on 2026-11-04 with fpgacapZero main (`552958c`).
`clk` is constrained at 50 MHz and JTAG TCK at 6 MHz; the design is fully
constrained (the TCK/`clk` crossings are bounded, see below). Slack is the
worst case over SmartTime's three multi-corner conditions (`slow_lv_ht`,
`slow_lv_lt`, `fast_hv_lt`: slow/fast process, low/high voltage, high/low
temperature). Fmax is computed from the worst `clk`
register-to-register setup slack (`1 / (20 ns - slack)`, slowest corner).

| Source | 4LUT | DFF | uSRAM | LSRAM | Math | Globals | `clk` setup / hold slack @ 50 MHz | TCK setup / hold slack @ 6 MHz | `clk` Fmax |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Verilog | 4,894 / 93,516 | 3,674 | 15 | 5 | 0 | 2 | +12.738 / +0.041 ns | +13.503 / +0.074 ns | 179 MHz |
| VHDL | 4,879 / 93,516 | 3,666 | 15 | 5 | 0 | 2 | +12.840 / +0.067 ns | +13.451 / +0.068 ns | 198 MHz |

Per block (from Libero's hierarchical resource report, LUT and DFF include
the RAM interface logic):

| Block | Verilog 4LUT / DFF / uSRAM / LSRAM | VHDL 4LUT / DFF / uSRAM / LSRAM |
| --- | ---: | ---: |
| `u_spw` (`spw_axi_top`, generic configuration) | 552 / 337 / 0 / 2 | 559 / 337 / 0 / 2 |
| `u_engine` (`spw_loopback_axi`) | 937 / 549 / 1 / 0 | 905 / 541 / 1 / 0 |
| `u_debug` (fcapz ELA, EIO, EJTAG-AXI, `UJTAG` decode) | 3,396 / 2,779 / 14 / 3 | 3,406 / 2,779 / 14 / 3 |
| top-level reset and I/O (plus the `INIT` block) | 9 / 9 / 0 / 0 | 9 / 9 / 0 / 0 |

As on the other boards, most of the area is the debug infrastructure; the
SpaceWire core is about 550 LUTs plus its two FIFO RAMs (LSRAM). The setup
slack per clock in the first table is set by the bounded TCK/`clk` crossings
(16 ns budget), not by logic inside one domain; inside `clk` the worst path is
the engine's register-read mux. Libero closes timing to the 50 MHz
requirement only, so Fmax varies between builds (179 and 198 MHz here).

**Clock-domain crossings.** The fcapz cores cross between TCK and `clk`
through synchronizers and Gray-pointer async FIFOs. `mpfs_disco_kit.sdc`
bounds every crossing with `set_max_delay 16` (under one 20 ns `clk` period,
so a Gray pointer never reaches a synchronizer out of step) instead of an
asynchronous clock group, which SmartTime would leave untimed. The hold check
across the two unrelated clocks is removed with `set_min_delay -20`: it has no
meaning there, and SmartTime would otherwise charge the 2–3 ns UJTAG clock
insertion delay of TCK against it.

## Hardware results

Measured on a PolarFire SoC Discovery Kit (`MPFS095T-1FCSG325E`, embedded
FlashPro5, fcapz `ftdi` backend at 6 MHz TCK) on 2026-11-04, with fpgacapZero
main (`552958c`, cores and host installed from the submodule) and Libero SoC
2025.2, on the builds whose resources and timing are listed above. Each
`host_loopback_test.py` run programs the board first (`build.py
--program-only`); `ela_capture_demo.py` runs straight after the soak, without
reprogramming. The Verilog and VHDL builds gave the same results: all 14 runs
passed (7 per build).

| Check | Result |
| --- | --- |
| LEDs after programming | all four lit (bring-up, link, self-check done, passed) |
| Reset after reprogramming | `SCRATCH` and `CTRL` back to their reset values, fresh self-check, also when the same bitstream is reprogrammed |
| Identity / `CORE_ID` / scratch | `SPWL`, `SPWR`, HDL fingerprint `V` / `H`, no aliasing at 0x100 |
| Power-on self-check | 4 packets x (16 PRBS + EOP): TX = RX = 68, 0 errors |
| Host data-mover | 5-byte packet + EOP looped back intact |
| EIO | `0x0F` (link, bring-up, done, pass) |
| Error injection | freeze -> `errdisc`, invert D -> `errpar` (`erresc` on the DE25-Nano); link drops and recovers, and the interrupted self-check re-runs with 0 errors |
| TimeCodes | 4/4 round-tripped |
| EEP / EOP | `0x42` + EEP (`tuser = 1`), `0x42` + EOP (`tuser = 0`) |
| Fault under load | detected mid-stream; clean recovery, no new errors |
| PRBS soak (10 Mbit/s, 60 s, fresh programming) | Verilog 3,482,059 / VHDL 3,483,721 back-to-back packets, ~59.2 M characters, 0 errors, ~0.99 MChar/s |
| ELA capture (50 MHz sampling) | D/S toggling (about 5 samples per bit), `spw_do == spw_di` and `spw_so == spw_si` in all 256 samples |

**fpgacapZero version.** fpgacapZero v0.5.1 kept the core manager's reset
epochs and owner token in registers with no reset, relying on initial values
that PolarFire does not load. When an epoch came up odd the host refused the
ELA demo (`ManagerResetError: ... MGR_SLOT_EPOCH ... is odd`), and because
PolarFire registers survive a reprogram, the Verilog build was refused in
every attempt. fpgacapZero main `552958c` derives the epoch parity from the
live reset level and adds the `hub_por` input, which `mpfs_debug` drives from
`FABRIC_POR_N`; with it the ELA demo passes on both builds and the host's
"carries owner token" warning is gone.

## Author and License

Author: Leonardo Capossio - [bard0 design](https://www.bard0.com) - hello@bard0.com.
License: LGPL-2.1-or-later.
