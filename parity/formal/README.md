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
matching integer parameter values for the proved configurations. No input
protocol constraints were added to make a proof pass.
