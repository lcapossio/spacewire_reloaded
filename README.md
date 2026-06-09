# SpaceWire Reloaded

Author: Leonardo Capossio - bard0 design - hello@bard0.com - 2026

SpaceWire Reloaded is a planned LGPL continuation and cleanup of the SpaceWire Light core by Joris van Rantwijk. The project goal is to keep the useful SpaceWire encoder/decoder architecture while replacing the GRLIB-dependent AMBA integration with an LGPL-compatible AMBA/AXI implementation owned by this repository.

The original SpaceWire Light source tree has been imported as a baseline. The imported source has not been modified as part of the initial import.

## Index

- [Project Goals](#project-goals)
- [License Direction](#license-direction)
- [Original Project README](#original-project-readme)
- [Imported Baseline](#imported-baseline)
- [Planned Features](#planned-features)
- [AMBA/AXI Porting Plan](#ambaaxi-porting-plan)
- [Current AXI Work](#current-axi-work)
- [How to Use and Test](#how-to-use-and-test)
- [FPGA Resource Usage and Timing](#fpga-resource-usage-and-timing)
- [Author and License](#author-and-license)

## Project Goals

- Preserve a small, portable SpaceWire link core suitable for FPGA designs.
- Keep the full core, including bus interfaces, under an LGPL-compatible license.
- Remove dependency on GPL-only GRLIB AMBA wrapper code.
- Provide clean, vendor-neutral RTL wrappers for architecture-specific resources such as FIFOs and RAMs.
- Build an OS-agnostic Python-based flow for linting, simulation, regression, and FPGA builds.
- Add CI with GitHub Actions once the source tree and regression entry points exist.

## License Direction

The intended license for this repository is LGPL. The AMBA/AXI implementation will be written for this project instead of importing GPL GRLIB-dependent source. Any imported upstream files must be reviewed before inclusion so that license provenance remains clear.

This repository includes the upstream GPL and LGPL license texts. License provenance must remain explicit as the GRLIB-dependent AMBA code is replaced by new LGPL-compatible implementation work.

## Original Project README

The original SpaceWire Light README is preserved as [README.spacewire_light.md](README.spacewire_light.md). It documents the upstream project history, original architecture, licensing notes, GRLIB-dependent AMBA interface, and prior Verilog translation work.

This top-level README is intentionally new and describes the SpaceWire Reloaded project direction.

## Imported Baseline

The current tree includes the upstream SpaceWire Light RTL, benches, simulations, documentation, synthesis examples, software support files, scripts, parity material, CI workflows, and GPL/LGPL license texts.

The imported GRLIB-dependent implementation files and LEON3/SPWAMBA support examples have been removed from this repository. Historical references remain in the preserved upstream README so the reason for the replacement work is still visible.

Important imported areas:

- `rtl/vhdl`: original VHDL RTL after removal of the GRLIB-dependent AMBA files.
- `rtl/verilog`: Verilog 2001 translation of the standalone non-GRLIB core.
- `bench`: VHDL and Verilog test benches.
- `sim`: simulation setups.
- `syn`: synthesis example projects.
- `sw`: software and driver examples.
- `doc`: manual and architecture documentation.
- `scripts`: Python helper scripts.
- `parity`: translation and parity verification material.

The planned replacement AMBA/AXI implementation must be LGPL-compatible and must not import GPL GRLIB source.

## Planned Features

- SpaceWire encoder/decoder core.
- FIFO-style streaming application interface.
- LGPL AMBA AHB/APB integration layer.
- LGPL AXI4-Lite register interface.
- Optional AXI4 or AXI4-Stream data movement interface, to be selected after the architecture is documented.
- Register map with register 0 as a core identifier and the next register as a version register.
- Portable wrappers for RAM, FIFO, reset, and clock-domain crossing primitives.
- Lint, simulation, and regression targets runnable from a clean checkout.

## AMBA/AXI Porting Plan

1. Document the standalone SpaceWire Light interfaces and the removed GRLIB-dependent AMBA behavior from preserved upstream documentation and history.
2. Define a bus-neutral internal control/data interface for the SpaceWire core.
3. Implement LGPL bus wrappers around that internal interface:
   - AHB/APB wrapper for AMBA-style systems.
   - AXI4-Lite wrapper for control and status.
   - AXI data path option after DMA requirements are settled.
4. Build self-checking simulations for register access, DMA/data movement, interrupt behavior, reset behavior, and error paths.
5. Add lint and regression targets before FPGA build flows.
6. Add FPGA build examples only after simulation coverage is in place.

## Current AXI Work

The first LGPL AXI replacement slice is in progress:

- `rtl/vhdl/spw_axi_lite_regs.vhd`: AXI4-Lite control/status register block.
- `rtl/vhdl/spw_axis_tx.vhd`: AXI-Stream to SpaceWire N-Char TX bridge.
- `rtl/vhdl/spw_axis_rx.vhd`: SpaceWire N-Char RX to AXI-Stream bridge.
- `rtl/vhdl/spw_axi_top.vhd`: VHDL top-level wrapper around `spwstream`.
- `rtl/verilog/spw_axi_lite_regs.v`: Verilog AXI4-Lite register block.
- `rtl/verilog/spw_axis_tx.v`: Verilog AXI-Stream TX bridge.
- `rtl/verilog/spw_axis_rx.v`: Verilog AXI-Stream RX bridge.
- `rtl/verilog/spw_axi_top.v`: Verilog top-level wrapper used by the local cocotb/Icarus integration regression.

The AXI-Stream data path is currently an N-Char stream:

- `tdata[7:0]` carries a data byte, EOP code, or EEP code.
- `tlast` is asserted on EOP/EEP control characters.
- `tuser[0]` is meaningful only when `tlast` is asserted: `0` selects EOP, and `1` selects EEP.

This preserves SpaceWire's explicit EOP/EEP characters and avoids hiding them inside the previous data byte.

## How to Use and Test

The imported baseline includes RTL, benches, scripts, and CI workflows. SpaceWire Reloaded adds a Python build entry point for lint and cocotb regressions.

Clean-checkout flow:

```sh
python build.py lint
python build.py test
python build.py test --hdl vhdl
python build.py test --runner wsl
python build.py vivado --dry-run
```

Install the Python regression dependencies with:

```sh
python -m pip install -r requirements-dev.txt
```

`python build.py test` uses cocotb with `cocotbext-axi`. The test runner supports:

- `--runner auto`: default; prefers WSL on Windows when a WSL distribution is visible, otherwise uses the local environment.
- `--runner wsl`: run cocotb from WSL with `python3`.
- `--runner local`: run cocotb from the current Python environment.
- `--hdl verilog`: default; run the Verilog cocotb regressions with Icarus Verilog.
- `--hdl vhdl`: run the VHDL AXI leaf/register cocotb regressions with GHDL and cocotb VPI.
- `--hdl all`: run both Verilog and VHDL cocotb regressions.

The current Verilog regression runs the shared cocotb tests against the Verilog AXI modules with Icarus Verilog. VHDL cocotb currently covers the AXI-Lite register block and AXI-Stream TX/RX leaf bridges with GHDL; the full VHDL top-level loopback still needs either a VHDL loopback wrapper or a mixed-language simulator flow. AXI-Lite tests use `AxiLiteMaster` for register reads, writes, byte strobes, randomized status/control access, reset recovery, independent AW/W ordering, and channel backpressure. AXI-Stream tests use `AxiStreamSource` and `AxiStreamSink` with pause generators for ready/valid backpressure. The top-level AXI regression loops the SpaceWire physical TX/RX pins back through the real `spwstream` core and covers EOP, EEP, empty packets, multiple back-to-back packets, packet-boundary stalls, reset during streaming, link disconnect/reconnect, and TimeCode transfer through AXI-Lite.

The cocotb suite also includes simulation-time AXI protocol checkers. AXI-Lite channels are checked for ready/valid payload stability under backpressure. AXI-Stream channels are checked for resolved `TVALID`/`TREADY`, resolved active payloads, stable payload while stalled, bounded stall and packet length, DUT-output `TVALID` clearing during reset, and the SpaceWire N-Char terminal-beat contract: `TLAST` marks EOP/EEP, terminal `TDATA` must be `0` or `1`, and terminal `TUSER[0]` must match the EEP code. These are protocol invariant checks during regression, not a replacement for a future formal proof flow.

VHDL cocotb execution requires a simulator/install combination with a working GHDL cocotb VPI interface. The local runner asks `ghdl` for its VPI library directory so Windows installs with split `bin` and `lib` DLL directories can load cocotb's GHDL VPI module. The GitHub Actions cocotb workflow installs GHDL, Icarus Verilog, and `requirements-dev.txt`, then runs both `--hdl verilog` and `--hdl vhdl`.

## FPGA Resource Usage and Timing

No new SpaceWire Reloaded FPGA implementation results are available yet.

Future reports will include:

- FPGA vendor, family, exact part, and speed grade.
- Tool name and version.
- Constraint summary.
- Target clock frequencies.
- LUT, register, RAM, DSP, and clocking resource usage.
- Maximum achieved frequency.
- Test conditions used to produce each number.

## Author and License

Author: Leonardo Capossio - bard0 design - hello@bard0.com

Target license: LGPL-compatible licensing for the full core, including AMBA/AXI interfaces.

Original inspiration: SpaceWire Light by Joris van Rantwijk.
