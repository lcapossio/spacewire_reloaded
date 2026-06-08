# HDL Translation Parity Skill Scope

This repo exposed the workflow a reusable skill should encode: translate an HDL
RTL block between languages, then prove the result with isomorphic test benches
and automated waveform/equivalence checks instead of relying on syntax and
smoke tests.

## Skill Goal

Create a Codex skill, tentatively named `hdl-translate-parity`, for requests
such as:

* "translate this VHDL core to Verilog 2001"
* "translate this Verilog module to VHDL"
* "port this HDL while preserving behavior"
* "add VHDL/Verilog parity checks"
* "compare GHDL and Icarus waveforms"
* "prove this translated RTL is equivalent to the original"

The skill should be language-pair agnostic. Its core model is:

* `golden`: the trusted source implementation.
* `candidate`: the translated implementation.
* `contract`: clocks, resets, parameters/generics, interfaces, stimulus
  scenarios, expected observables, signal maps, waveform timing relationships,
  functional coverage model, and accepted simulator differences.

VHDL-to-Verilog and Verilog-to-VHDL are special cases of this model. Other HDL
pairs can be supported when there are simulators and waveform exports for both
sides.

## Methodology

### 1. Freeze the Golden Behavior

Before translating, run and record the original regression suite. If the golden
does not already have tests, create a small contract-first test set before
touching RTL.

The skill should produce a `parity/manifest.yml` or equivalent with:

* source files and top units for golden and candidate.
* parameter/generic configurations.
* clock names, periods, phases, and reset behavior.
* public interface signals and bus grouping.
* expected stop condition and maximum simulation time.
* waveform signal map: golden path -> candidate path.
* waveform relationship map: timing constraints between mapped signals.
* functional coverage map: shared coverpoints, crosses, bins, and exclusions.
* tolerated normalization rules: initial delta window, X/U handling, ignored
  generated names, stop-time trimming, and sampled-vs-transition comparison.

### 2. Translate in Behavioral Slices

Translate in this order:

1. leaf combinational helpers and simple registers.
2. RAM/FIFO/synchronizer primitives.
3. datapath modules.
4. control/state machines.
5. wrappers/top-level integration.
6. original test benches or new isomorphic parity benches.

After each slice, add or update a parity check. Never translate the whole design
and only test at the end.

### 3. Build Isomorphic Test Benches

The skill should treat the testbench as a first-class artifact, not an
afterthought. An isomorphic bench pair must have the same logical behavior even
if written in different HDL syntax.

Required properties:

* same clock/reset schedule.
* same parameter/generic matrix.
* same stimulus events at the same logical cycles.
* same external protocol transactions.
* same injected errors and corner cases.
* same pass/fail assertions.
* same observable trace points.
* same stop condition.
* same cycle-level timing relationships for protocol-visible behavior.
* same functional coverage model and coverage goals.

Preferred pattern: write a language-neutral scenario file and generate or drive
both benches from it. Good scenario formats are YAML, JSONL, or CSV event
streams, for example:

```yaml
clocks:
  clk: {period_ns: 50}
reset:
  rst: {active: 1, assert_cycles: 8}
steps:
  - at_cycle: 8
    set: {rst: 0, linkstart: 1}
  - wait_until: {signal: running, value: 1, timeout_cycles: 20000}
  - trace: RUN
  - repeat_cycles: 10000
  - trace: DIV1
```

The generated VHDL and Verilog benches may differ syntactically, but their
scenario driver must be the same. When generation is not practical, manually
translated benches must include a checklist proving each scenario step maps
one-to-one.

### 4. Use Layered Equivalence Gates

The skill should add gates from cheap to strong:

1. syntax/lint for both languages.
2. golden original regression.
3. candidate regression.
4. trace equivalence: normalized text milestones and counters.
5. public waveform equivalence: every top-level input/output/status signal.
6. mapped internal waveform equivalence: state registers, FIFOs, counters, and
   protocol edges that should correspond.
7. functional coverage equivalence: both sides hit the same declared bins.
8. synthesis comparison: representative configs with resource-class tolerances.
9. formal miter checks when the language/tool pair allows it.

Full raw waveform identity is usually not a realistic default because different
languages and simulators expose different hierarchy, delta cycles, enum names,
record fields, and generated blocks. The skill should instead require
**contract-complete waveform identity**: all signals listed in the manifest must
match after normalization. For a careful translation, that list should include
all public ports and enough internal state to catch meaningful semantic drift.

### 5. Normalize Waveforms Deliberately

The waveform comparator should:

* parse VCD/FST/LXT2 where available.
* normalize timescales to picoseconds or femtoseconds.
* trim the initial delta/reset window only when declared in the manifest.
* trim to the common active stop time.
* map signal names by manifest, not by string guess.
* normalize VHDL `U`, `W`, `-` and Verilog `x/z` according to explicit policy.
* support exact transition comparison and sampled-at-clock-edge comparison.
* report the first mismatch with time, signal, golden value, candidate value,
  and nearby history.
* preserve failing waveforms as CI artifacts.

The default should be exact transition comparison for stable public signals.
Clocked sampled comparison is acceptable for signals affected by simulator
delta-cycle scheduling, but it must be declared in the manifest.

### 6. Check Waveform Timing Relationships

Value equivalence is not enough for HDL translation. The contract must also
state which timing relationships are part of the design behavior.

The skill should support relationship checks such as:

* `same_cycle`: two mapped signals must change on the same clock edge.
* `latency`: an event on signal A must cause an event on signal B after exactly
  N cycles or within an explicit `[min, max]` cycle window.
* `stable_while`: a bus must remain stable while a valid/ready/enable signal is
  asserted.
* `pulse_width`: a pulse must last exactly or at least N cycles.
* `event_order`: event A must occur before event B, with optional cycle bounds.
* `mutual_exclusion`: two enables/errors/states must not be high together.
* `clock_crossing`: source-domain event and destination-domain observation may
  differ by an allowed synchronizer latency window.
* `reset_release`: outputs must reach declared values within N cycles after
  reset deassertion.

Example manifest fragment:

```yaml
relationships:
  - name: tx_accept_latency
    clock: clk
    trigger: {signal: txwrite, edge: rise}
    response: {signal: txrdy, value: 0}
    latency_cycles: [0, 1]
  - name: rxdata_stable
    clock: clk
    stable: rxdata
    while: {signal: rxvalid, value: 1}
  - name: disconnect_to_error
    clock: clk
    trigger: {signal: loopback, edge: fall}
    response: {signal: errdisc, edge: rise}
    latency_cycles: [1, 64]
```

Timing relationship checks should run on the golden waveform first. If the
golden does not satisfy the proposed relationship, the relationship is wrong or
underspecified. Only after the golden passes should the candidate be compared
against the same relationship contract.

### 7. Match Functional Coverage

Functional coverage must be part of the parity contract. Passing the same tests
is weaker than proving both implementations exercised the same meaningful
behavior.

The skill should require a shared coverage model for translated surfaces:

* states visited.
* state transitions covered.
* packet/control symbol types observed.
* protocol errors injected and detected.
* FIFO empty/near-full/full boundaries.
* reset, disable, reconnect, timeout, and recovery scenarios.
* parameter/generic configurations.
* clock-domain and CDC latency classes.
* representative cross coverage, such as `rx_impl x rxchunk x tx_impl`.

Preferred pattern: define coverage bins in the manifest and collect coverage
from normalized trace/waveform events rather than relying on simulator-specific
coverage databases. This keeps the method portable across VHDL, Verilog,
SystemVerilog, and other HDL simulators.

Example manifest fragment:

```yaml
coverage:
  coverpoints:
    - name: link_state
      source: running
      bins:
        stopped: 0
        running: 1
    - name: tx_divider
      source: txdivcnt
      bins: [1, 2, 3, 39, 96]
    - name: rxchunk
      config: RXCHUNK
      bins: [1, 2, 3, 4]
  crosses:
    - name: implementation_matrix
      points: [RXIMPL, RXCHUNK, TXIMPL]
```

The coverage check should report three results:

1. golden coverage: the source implementation hits the required bins.
2. candidate coverage: the translated implementation hits the required bins.
3. parity coverage: the hit-bin sets match, except for declared exclusions.

Coverage mismatches must fail CI unless explicitly waived in the manifest with a
reason. Candidate-only coverage is useful but should not be used to claim
translation parity.

### 8. Separate Translation Quality From Extra Coverage

Extra candidate-only tests are useful, but they must not be counted as language
parity. The skill should label every bench:

* `isomorphic`: same scenario and comparable waveform contract.
* `golden-only`: original regression only.
* `candidate-only`: extra coverage, useful but not parity.
* `non-isomorphic`: currently not allowed to support equivalence claims.

### 9. Refuse Overclaiming

The final report must say exactly what is proven:

* which configurations passed.
* which benches are isomorphic.
* which signals were waveform-compared.
* which timing relationships were checked.
* which functional coverage bins/crosses were hit by both sides.
* whether internals were compared or only ports.
* which tests are extra one-language coverage.
* what remains before claiming full translation equivalence.

## Required Workflow

1. Identify the translatable RTL boundary and the golden/candidate pair.
2. Create or update the parity manifest.
3. Exclude vendor, bus-fabric, debug, and project-specific integration files
   unless the user explicitly asks to include them.
4. Translate leaf modules first, then controllers/wrappers, preserving reset
   semantics, clock domains, parameter ranges, and public interfaces.
5. Add isomorphic parity benches for every translated behavioral surface.
6. Add CI gates in layered order: syntax, regressions, trace comparison,
   waveform value comparison, waveform relationship checking, synthesis
   comparison, functional coverage parity, and formal checks where possible.
7. State clearly which benches are exact parity benches and which are extra
   one-language coverage.

## Bundled Scripts

The skill should include reusable scripts rather than rewriting these each time:

* `compare_traces.py`: run paired benches and compare normalized `TRACE` lines.
* `compare_waveforms.py`: parse VCD/FST from configured simulators, normalize
  timescale, map signal names from the manifest, and compare declared signals
  over a common active window.
* `check_waveform_relationships.py`: evaluate temporal relationships over one
  or both waveforms, including cycle latency, pulse width, stability, ordering,
  mutual exclusion, and CDC windows.
* `check_functional_coverage.py`: collect manifest-defined coverpoints/crosses
  from traces or waveforms and compare golden/candidate hit-bin sets.
* `synth_resource_compare.py`: emit VHDL-derived Verilog with GHDL, synthesize
  both implementations with Yosys, and compare resource classes within declared
  tolerances.
* `run_manifest.py`: execute all manifest-declared regressions and write a
  machine-readable result summary.
* `generate_tb.py`: generate language-specific bench skeletons from a neutral
  scenario file when the project allows it.
* `bench_manifest.py` or a YAML schema validator: declare source lists, tops,
  waveform signal maps, expected exclusions, and simulator commands.

## References

Include short references for:

* HDL translation gotchas: delta cycles, enum encoding, record/struct
  flattening, resolved vs unresolved signals, blocking vs nonblocking
  assignment, integer ranges, signedness, async resets, RAM inference, generate
  blocks, and generated clocks.
* Waveform comparison limits: initial delta mismatches, simulator stop-time
  differences, hierarchy/name normalization, sampled-vs-transition comparison,
  and when raw internal waveform identity is unrealistic.
* Portable functional coverage: manifest-defined coverpoints from waveforms and
  traces, coverage waivers, and differences from SystemVerilog-native coverage.
* CI templates for GHDL, NVC, Icarus Verilog, Verilator, Yosys, SymbiYosys, and
  optional commercial simulator hooks.
* Manifest schema examples for VHDL-to-Verilog, Verilog-to-VHDL, and same-HDL
  refactors.

## Current Repo Gap

This repository now has exact normalized waveform comparison for the matched
`streamtest_trace_tb` observables. It does not yet prove every signal in every
bench is waveform-identical. `spwlink_tb_all` now mirrors the VHDL bench's
23-case implementation/configuration sweep, but it remains a lightweight
self-loopback Verilog bench rather than a line-for-line translation of the full
VHDL link stimulus/monitor. True all-bench waveform identity requires making
each translated bench stimulus-isomorphic first, then adding a waveform manifest
for each matched pair.
