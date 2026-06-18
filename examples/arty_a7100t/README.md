# Arty A7-100T SpaceWire Loopback Example

Hardware-validation design for **SpaceWire Reloaded** on the Digilent
Arty A7-100T (`xc7a100tcsg324-1`). A single `spw_axi_top` SpaceWire link is run
in loopback and verified over JTAG with [fpgacapZero](https://github.com/lcapossio/fpgacapZero)
("fcapz"). The design is provided in **both Verilog and VHDL** and is
self-stimulating, so it lights its status LEDs and passes its self-check with no
host attached.

## What it does

`spw_axi_top` exposes an AXI4-Lite control/status interface and an AXI-Stream
N-Char data path. The example wraps it with a small engine (`spw_loopback_axi`)
that:

- is the **AXI-Lite master** that brings the link up (writes `CONTROL`/`TXDIVCNT`),
  reads back the SpaceWire `CORE_ID`, and polls `STATUS`;
- owns the N-Char **AXI-Stream** TX/RX and runs either a fabric **self-check**
  (sends `SELFTEST_PKTS` back-to-back packets, each `SELFTEST_LEN` PRBS bytes +
  EOP, with the PRBS sequence continuing across packets so any dropped or
  duplicated char is caught, and checks the looped-back stream at link rate) or a
  host **data-mover** (push/pop N-Chars from the host);
- presents an **AXI4 slave** register file to the fpgacapZero EJTAG-AXI bridge so
  the host drives and observes everything over JTAG.

The SpaceWire transmit pins are looped back to the receive pins:

- `LOOPBACK_INTERNAL = 1` (default): `spw_do -> spw_di`, `spw_so -> spw_si`
  inside the FPGA.
- `LOOPBACK_INTERNAL = 0`: routed to single-ended (LVCMOS33, **not** LVDS) Pmod
  **JA**; fit two straight jumpers `JA1->JA7` (Dout->Din) and `JA4->JA10`
  (Sout->Sin). Data and Strobe sit in separate columns to limit crosstalk, and
  the inputs have pulldowns so a removed/absent jumper reads a clean disconnect.

fpgacapZero debug cores give three host verification surfaces: the EJTAG-AXI
bridge (USER4) for register/data access, two ELAs (USER1) capturing the
SpaceWire D/S lines and the received N-Char byte, and two EIOs (USER1) mirroring
link/self-check status.

## Status LEDs

| LED | Meaning |
| --- | --- |
| `led[0]` | AXI-Lite bring-up sequence completed |
| `led[1]` | SpaceWire link running |
| `led[2]` | self-check done |
| `led[3]` | self-check passed |

All four lit = link up and loopback self-check passed. `btn[0]` resets the design.

## Files

| File | Purpose |
| --- | --- |
| `rtl/spw_arty_a7100t_top.v` / `.vhd` | Top-level (loopback, fcapz cores, LEDs) |
| `rtl/spw_loopback_axi.v` / `.vhd` | Loopback engine (AXI4 slave + AXI-Lite master + AXIS) |
| `arty_a7100t.xdc` | Pin and clock constraints |
| `build.py` | Vivado build launcher (`--hdl verilog|vhdl`) |
| `build_arty.tcl` / `build_arty_vhdl.tcl` | Vivado batch scripts |
| `arty_a7100t.cfg` | OpenOCD config for the onboard USB-JTAG |
| `host_loopback_test.py` | fcapz host verification (`--stress` soak, `--inject`/`--loadfault` faults, `--timecode`, `--eep`) |
| `ela_capture_demo.py` | fcapz ELA waveform capture of the live SpaceWire D/S lines |
| `tb/` | cocotb functional sim (engine + core, internal loopback) |
| `fpgacapZero/` | fpgacapZero debug-core RTL (git submodule) |

## Host register map (AXI4, 32-bit)

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x00` | `EXAMPLE_ID` | RO | ASCII `SPWL` |
| `0x04` | `EXAMPLE_VER` | RO | `0x000100xx`; low byte is an ASCII HDL fingerprint: `V` (0x56) = Verilog build, `H` (0x48) = VHDL build |
| `0x08` | `SCRATCH` | RW | host R/W sanity word |
| `0x0C` | `CTRL` | RW | `[0]` selftest_en (reset 1), `[1]` selftest_start, `[2]` soft_reset, `[3]` selftest_loop (continuous free-running self-check) |
| `0x10` | `STATUS` | RO | `[0]` link_running `[1]` busy `[2]` done `[3]` pass `[4]` tx_ready `[5]` rx_valid `[6]` bringup_done `[11:8]` spw errors |
| `0x14` | `SPW_COREID` | RO | SpaceWire `CORE_ID` read back over AXI-Lite (`SPWR`) |
| `0x18` | `SPW_STATUS` | RO | last raw SpaceWire `STATUS` word |
| `0x1C` | `TXDATA` | WO | data-mover push: `[7:0]` data `[8]` tlast `[9]` tuser(EEP) |
| `0x20` | `RXDATA` | RO | data-mover pop: `[7:0]` data `[8]` tlast `[9]` tuser `[31]` valid |
| `0x24`/`0x28`/`0x2C` | `TXCOUNT`/`RXCOUNT`/`ERRCOUNT` | RO | self-check N-Char counts and PRBS/framing mismatches |
| `0x30` | `PKTCOUNT` | RO | self-check packets received (EOP count) |
| `0x34` | `ERRINJ` | RW | fault injection on the internal loopback line: `[0]` freeze (force `di=si=0`, a disconnect) `[1]` invert `do` (corrupts the Data line, a parity/link error). Clear to `0` then pulse `CTRL` soft_reset to recover |
| `0x38` | `TIMECODE` | RW | SpaceWire TimeCode loopback. Write `[7:0]` = time-code (`[7:6]` control + `[5:0]` time): the engine clears the received-valid then sends it over the link. Read `[5:0]` = last received time, `[7:6]` = control, `[31]` = valid (mirrors the core TIMECODE_RX, refreshed every status poll) |

## Build

The fpgacapZero RTL is a git submodule. On a fresh checkout:

```sh
git submodule update --init examples/arty_a7100t/fpgacapZero
```

Then build a bitstream (Vivado must be on `PATH`, or pass `--vivado`):

```sh
python examples/arty_a7100t/build.py --hdl verilog          # spw_arty_a7100t_top.bit
python examples/arty_a7100t/build.py --hdl vhdl             # spw_arty_a7100t_top_vhdl.bit
python examples/arty_a7100t/build.py --hdl verilog --fast   # spw_arty_a7100t_top_fast.bit
```

### Generic vs fast build

The default build runs the generic RX/TX front ends in a single 100 MHz clock
domain at ~10 Mbit/s (`LINK_TXDIVCNT=9`); the generic RX front end is not meant
for high line rates. The `--fast` build (`RXIMPL=TXIMPL=1`, `USE_MMCM=1`) uses an
MMCM to run `rxclk` (150 MHz) and `txclk` (100 MHz) in their own domains, so the
gray-coded `rxclk -> clk` head-pointer crossing and the `clk <-> txclk` transmit
crossings are real clock-domain crossings on hardware, and it sets
`LINK_TXDIVCNT=0` for a **100 Mbit/s** SpaceWire link (`txclk/(LINK_TXDIVCNT+1)`,
oversampled 3x by the 150 MHz DDR fast RX). The fast build applies
[`constraints/spw_cdc.xdc`](../../constraints/spw_cdc.xdc) (post-synthesis, plus
asynchronous clock groups), so it is also what exercises that constraint file.
Both builds meet timing on `xc7a100tcsg324-1` and pass the same fcapz host
loopback test on the board.

## Simulate (no board)

A cocotb functional sim drives the engine's AXI4 slave exactly like fcapz does
and checks, for both languages: the self-check and host data-mover loopbacks,
continuous (loop) mode, error injection + recovery, TimeCode loopback, EEP
round-trip, and fault-under-load recovery (7 tests):

```sh
python -m pytest examples/arty_a7100t/tb/test_spw_loopback_runner.py            # Verilog (Icarus)
SPW_RUN_VHDL_COCOTB=1 python -m pytest examples/arty_a7100t/tb/test_spw_loopback_runner.py -k vhdl  # VHDL (GHDL)
```

## Verify on hardware (fcapz)

Program the board and run the host check (hw_server backend programs on connect):

```sh
hw_server -d
python examples/arty_a7100t/host_loopback_test.py \
    --bitfile examples/arty_a7100t/spw_arty_a7100t_top.bit
```

### Soak / stress test

`--stress N` puts the self-check into continuous (loop) mode and free-runs
back-to-back PRBS packets at link rate for `N` seconds, polling the counters and
failing if `ERRCOUNT` is ever non-zero or traffic stalls:

```sh
python examples/arty_a7100t/host_loopback_test.py \
    --bitfile examples/arty_a7100t/spw_arty_a7100t_top.bit --stress 180
```

### Error injection and recovery

`--inject` drives the `ERRINJ` register to corrupt the internal loopback line
and confirms the SpaceWire link-error detection and recovery. It freezes the
`di`/`si` lines (a disconnect, which sets the sticky `errdisc` and drops the
link), then inverts the `do` line (a Data-line corruption, which raises a link
error), and after each fault clears `ERRINJ` and pulses soft_reset to bring the
link back up with the sticky error bits cleared:

```sh
python examples/arty_a7100t/host_loopback_test.py \
    --bitfile examples/arty_a7100t/spw_arty_a7100t_top.bit --inject
```

The same sequence is covered in sim by `test_error_injection` in
[`tb/spw_loopback_cocotb.py`](tb/spw_loopback_cocotb.py) for both languages.

### TimeCode, EEP and fault-under-load

Three more `host_loopback_test.py` modes exercise the rest of the SpaceWire
feature set on hardware (each also has a matching cocotb test):

```sh
# SpaceWire TimeCodes: the engine sends 0x95/0x2A/0x3F/0xC1 and checks each
# loops back through the TIMECODE register (control + time fields).
python examples/arty_a7100t/host_loopback_test.py --timecode

# EEP: an error-end-of-packet char round-trips with tuser=1, distinct from a
# normal EOP (tuser=0), through the host data-mover.
python examples/arty_a7100t/host_loopback_test.py --eep

# Fault under load: corrupt the line while back-to-back PRBS packets are
# flowing, confirm the link error is detected, then confirm clean operation
# resumes after recovery (the bring-up core-reset flush realigns the self-check).
python examples/arty_a7100t/host_loopback_test.py --loadfault
```

### ELA waveform capture

ELA0 (USER1, instance 0) samples the SpaceWire `do/so/di/si` pins plus status in
the system clock domain. This brings the link up, runs the self-check, captures a
window, renders the four Data/Strobe signals as an ASCII waveform, checks they
toggle and that the internal loopback holds (`do==di`, `so==si`), and writes a VCD:

```sh
python examples/arty_a7100t/ela_capture_demo.py \
    --bitfile examples/arty_a7100t/spw_arty_a7100t_top.bit
```

Use the generic build for a clear waveform (at 100 MHz sampling each 10 Mbit/s bit
is ~10 samples wide). Example output shows the SpaceWire Data-Strobe encoding
(`do` and `so` never change on the same bit):

```text
   spw_do: |####__________##########______________________________##########################|
   spw_so: |##################################__________####################__________######|
```

Or drive the cores directly with the `fcapz` CLI, e.g. read the example ID and
the SpaceWire CORE_ID:

```sh
fcapz --backend hw_server --port 3121 --tap xc7a100t \
    --program examples/arty_a7100t/spw_arty_a7100t_top.bit \
    axi-read 0x00            # -> 0x5350574C "SPWL"
fcapz --backend hw_server --port 3121 --tap xc7a100t axi-read 0x14   # -> 0x53505752 "SPWR"
```

## FPGA resource usage and timing

Whole design (SpaceWire core + loopback engine + fpgacapZero debug cores: 2 ELA,
2 EIO, EJTAG-AXI bridge) on `xc7a100tcsg324-1` (Artix-7), Vivado 2025.2, default
implementation strategy, Verilog build. Post-route, all timing constraints met.

| Build | Clocks | LUTs | Registers | BRAM | BUFG | MMCM | Setup WNS | Link rate |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| generic | clk 100 MHz | 4000 (6.3%) | 4699 (3.7%) | 4 | 3 | 0 | +1.848 ns | ~10 Mbit/s |
| fast | clk 100, rxclk 150, txclk 100 MHz | 4268 (6.7%) | 5060 (4.0%) | 4 | 6 | 1 | +1.927 ns | 100 Mbit/s |

The fast build adds the MMCM (1) and extra clock buffers for the separate
`rxclk`/`txclk` domains and the oversampling fast RX/TX front ends. IOB usage is
11 in both. The VHDL builds target the same device/clocks with comparable numbers
(fast VHDL setup WNS +2.055 ns). SpaceWire run bit rate is `txclk/(LINK_TXDIVCNT+1)`
(generic `LINK_TXDIVCNT=9` -> ~10 Mbit/s; fast `LINK_TXDIVCNT=0` -> 100 Mbit/s).

## Author and License

Author: Leonardo Capossio - bard0 design - hello@bard0.com.
License: LGPL-2.1-or-later (example), fpgacapZero submodule is Apache-2.0.
