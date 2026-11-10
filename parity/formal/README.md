# Formal VHDL/Verilog parity evidence

These manifests are intended for the `translate-hdl` skill parity runner:

```sh
python /path/to/translate-hdl/scripts/parity.py \
  parity/formal/syncdff_parity.yml --only MAN,L0,L1,L2 --strict

python /path/to/translate-hdl/scripts/parity.py \
  parity/formal/spwrecvfront_generic_parity.yml --only MAN,L0,L1,L2 --strict

python /path/to/translate-hdl/scripts/parity.py \
  parity/formal/spwlink_parity.yml --only MAN,L1,L2 --expect bounded
```

Run them from the repository root in an environment with `python3`, `pyyaml`,
`ghdl`, `iverilog`, and `yosys` on `PATH`. The WSL environment on this machine
has that combined toolchain.

## Current formal verdict

| Manifest | Layer 0 | Layer 1 | Layer 2 | Notes |
| --- | --- | --- | --- | --- |
| `syncdff_parity.yml` | PASS | PASS | PASS | Unbounded `equiv_induct` proof. |
| `spwrecvfront_generic_parity.yml` | PASS | PASS | PASS | Unbounded `equiv_induct` proof. |
| `spwlink_parity.yml` | Not run | PASS | BOUNDED | VHDL record ports are adapted by `spwlink_flat.vhd`; no counterexample through 128 cycles from reset, but 7 `$equiv` cells do not inductively close with plain Yosys. |

`spwlink` is therefore strong bounded evidence, not a full unbounded proof. A
full closure path is to use a stronger SEC engine such as `eqy`/SymbiYosys or to
align the remaining internal state mapping so plain `equiv_induct` can close.
`eqy` and `sby` were not available in the local WSL toolchain used here.

## Fast (dual-clock) front ends

`spwrecvfront_fast` and `spwxmit_fast` have two clock domains, which the
manifest runner above does not handle. They have their own runner:

```sh
python3 scripts/formal_parity_fast.py            # all targets
python3 scripts/formal_parity_fast.py rx2 tx     # a subset
```

It needs `ghdl` (with `--synth`), `yosys` and `yosys-abc` on `PATH`, and runs
in CI (`formal-fast-frontends` job in `.github/workflows/verilog.yml`). For
each target the VHDL is synthesized with GHDL, and both designs are placed in a
miter (`parity/formal/fast/miter_rx.sv`, `miter_tx.sv`) that drives them with
the same inputs and asserts equal outputs. Both clocks are free formal inputs
(Yosys `clk2fflogic`): independent clocks with any phase and frequency ratio.
The miter is reduced with ABC signal correspondence (`scorr`) and proved with
ABC PDR, which gives an unbounded proof. `spwxmit_fast` record ports go through
`parity/formal/fast/spwxmit_fast_flat.vhd`.

| Target | Configuration | Power-up state | Verdict |
| --- | --- | --- | --- |
| `rx1`..`rx4` | `spwrecvfront_fast`, rxchunk 1, 2, 3, 4 | registers arbitrary and independent in each design; both buffer RAMs zero | PASS, unbounded |
| `tx` | `spwxmit_fast` | every register of both designs zero | PASS, unbounded |
| (diagnostic) | `spwxmit_fast` | registers arbitrary and independent | not proved: PDR did not converge in 25 min; BMC found no counterexample in 32 formal steps (20 min), only about a dozen clock cycles after reset, so weak evidence |

Run time for all five targets with `--jobs 4`: 7.5 min on a 16-thread
Windows 11 machine (WSL, GHDL 4.1.0, Yosys 0.33) that was also running other
jobs, 2026-11-10. Each proof was checked for vacuity with Verilog mutants,
which all fail: a split receive data bit (frame 28) and a wrong buffer tail
pointer (frame 29) in `spwrecvfront_fast`, a wrong parity bit (frame 24) and a
wrong EOP code (frame 101) in `spwxmit_fast`.

Unlike the manifests above, these miters do constrain the inputs:

- **Reset.** Once reset is asserted (`rxen` low for the receiver, `rst` high
  for the transmitter), it stays asserted until both clocks have had 4 rising
  edges; both designs also start in reset. `spwlink` meets this: it drives
  `rxen` low only in ErrorReset, for `reset_time` = sysfreq x 6.4 us `clk`
  cycles. Without the rule there are counterexamples that need a reset pulse
  shorter than a clock period, or a clock that stops while in reset; see below.
- **Compared outputs.** Outputs are compared from the end of the first reset.
  `inbits` is compared only while `inbvalid` is high, since it carries no
  data otherwise.
- **RAM contents.** The receiver buffer RAM has no reset, so both RAMs start
  from the same contents (zero).
- **Transmitter power-up.** `spwxmit_fast` has `txclk` registers that no reset
  clears (`b_txflip`, `b_token`, `c_bits`, `e_shift`, `txclkcy`, `txclkdone`).
  The proof starts both designs from the same all-zero state. With independent
  arbitrary power-up values the problem is too large for PDR, so that case
  has only the bounded result in the table.

**Power-up difference found by the receiver proof.** The VHDL `spwrecvfront_fast`
`rxclk`-domain registers have no initial values, while the Verilog initializes
all of them. On the first `rxclk` edge, still in reset, the VHDL can therefore
write one garbage entry into the buffer RAM. That entry appears as received
data only if `rxen` rises again after a pulse shorter than a clock period, or
a clock stops during reset. Neither can happen inside `spwlink` (see the reset
rule above), so this does not affect the core.

## Regression parity covering the remaining translated surface

The standalone translated RTL that is not individually closed by L2 formal is
covered by the existing regression parity suite:

```sh
python3 scripts/lint_hdl.py --verilog
python3 scripts/lint_hdl.py --vhdl
python3 scripts/check_spwlink_parity_manifest.py
python3 scripts/compare_vhdl_verilog_traces.py
python3 scripts/compare_vhdl_verilog_waveforms.py
python3 scripts/synth_resource_compare.py
```

The refreshed WSL run produced:

| Check | Verdict |
| --- | --- |
| Verilog lint plus Yosys structural checks | PASS |
| VHDL lint, elaboration, and synthesis wrapper checks | PASS |
| `spwlink` 23-case stimulus-isomorphic manifest check | PASS |
| deterministic `streamtest_trace_tb` VHDL/Verilog traces | PASS |
| normalized `streamtest_trace_tb` waveforms | PASS for 17 signals from 25 ns to 1.0801 ms |
| generic/fast `spwstream` synthesis resource comparison | PASS command; expected resource deltas reported |

## Scope and assumptions

Translated standalone modules are `syncdff`, `spwram`, `spwlink`, `spwxmit`,
`spwxmit_fast`, `spwrecv`, `spwrecvfront_generic`, `spwrecvfront_fast`,
`spwstream`, and `streamtest`.

The AMBA/LEON3/GRLIB-dependent files are intentionally out of scope:
`spwamba`, `spwambapkg`, and `spwahbmst`.

The formal proofs rely on matching VHDL and Verilog top-level ports after the
explicit flat wrapper for record-port modules, matching reset polarity/kind, and
matching integer parameter values for the proved configurations. The manifest
proofs add no input protocol constraints. The fast front-end proofs use the
reset rule and initial-state choices listed in
[Fast (dual-clock) front ends](#fast-dual-clock-front-ends).
