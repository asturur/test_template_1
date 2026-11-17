# Architectural TLB area experiment

Retain offline for a matched fit; no mapped ALM saving or timing closure claimed.
The actual physical anchor is routed5K44123116917:40,834 ALMs,502 M10Ks and
4,190 occupied LABs. Performance reference is exact qualified5L. Rejected5M is
not overlaid. Production and public history are untouched.

`setup.py` freezes promotedccba54f, applies the existing5L overlay and optionally
replaces the architectural TLB banks plus their mutation/CP15 handshakes.
`rtl/tlb_bank.sv` keeps all64 entries, mixed page classes, overlap semantics,
lockdown/victim/P state and byte-enabled BRAM rows. It compares eight slots per
clock, exits at the first matching row and serializes mutations. The pending
mutation queue requires the connected CP15 busy/drain contract. Context-cancelled
installs commit no tag, payload or overlap invalidation. This is an area change,
not another arithmetic/issue performance mechanism.

Use unique names and **one serial job at a time**, existing offline image only:

```sh
python3 tests/cpu/tlb_area/profile.py --name NEW_CONTROL
python3 tests/cpu/tlb_area/profile.py --candidate --name NEW_CANDIDATE
python3 tests/cpu/tlb_area/profile.py --jpeg --name NEW_JPEG_CONTROL
python3 tests/cpu/tlb_area/profile.py --candidate --jpeg --name NEW_JPEG_CANDIDATE
python3 tests/cpu/tlb_area/units.py --name NEW_UNITS
python3 tests/cpu/tlb_area/equivalence.py --name NEW_EQUIVALENCE
python3 tests/cpu/tlb_area/bench.py --name NEW_SPAN --only span --only stream --only multiline
python3 tests/cpu/tlb_area/diagnostics.py NEW_DIAGNOSTICS --build build/sim/tlb-area/NEW_SPAN
python3 tests/cpu/tlb_area/core_checks.py --build build/sim/tlb-area/NEW_SPAN --name NEW_CORE
python3 tests/cpu/tlb_area/safety.py --build build/sim/tlb-area/NEW_SPAN
```

The main profiles retain original code/hash/oracle/retirement/repeat/negative
checks. `tlb_observe.vh` counts whole-run/scored searches and mutations, observed
I/D blocking union and registered hit rows; `observe.vh` is the separate original
span/stream observer. No benchmark PC affects hardware eligibility.

`units.py` runs the five maintained unit suites, adding an explicit bank drain
to the standalone64-entry fixture. Controller fixtures naturally wait on busy.
`equivalence.py` compares against originalccba54f table RTL with poisoned mixed
port reads, all64 slots, overlaps in both directions, preservation/lockdown,
queued mutations and cancelled installs. Two equal867-query runs record
2–9-edge lookup and mutation-drain distributions. The unchanged oracle must
reject a deliberately truncated eight-entry candidate.

The actual CPU diagnostics use a frozen-source executable. The core peer is
separate because FIQ/SWP/ordering/prefetch cases require its stimuli. Ordering
checks keep their overlap assertion: data waits15/31 and instruction waits63/127
keep a buffered write pending through the longer bank miss.0/3 waits still run
as ordinary diagnostics; they are not falsely counted as overlap coverage.

Final fixed-name audit inputs:

- Original frequency: `build/sim/spmark-payload/area-frequency-5l-01` and
  `build/sim/jpeg-payload/area-frequency-jpeg-01`.
- Corrected control rows: `area-rows-5l-02` (matrix/triangle) and
  `build/sim/jpeg-payload/area-rows-jpeg-02`.
- Final performance: `build/sim/spmark-payload/area-banked-5l-02`,
  `build/sim/jpeg-payload/area-banked-jpeg-02`, and
  `build/sim/tlb-area/area-banked-span-02`.
- Final units/equivalence: `build/sim/tlb-area/banked-units-05` and
  `banked-equivalence-03`.
- Actual CPU: `area-control-diagnostics-01`, `area-banked-diagnostics-03`,
  `area-banked-core-04`; safety is in the final span directory.

`python3 tests/cpu/tlb_area/analyze.py` audits those names, the exact60-source/
51-compiler-input closures, original scored work, corrected frequency, direct
fitter rows and all checks. It writes `docs/evidence/tlb-area-20261117.json`.
Source/storage/M10K estimates remain explicitly separate from physical results.
Completed compiler trees and original private derived inputs are disposable;
compressed logs, manifests, synthetic fixtures and receipts remain.

History worth avoiding: initial row histograms sampled the old selector after
its hit vector cleared (all row7); the corrected registered sampler is required.
An initial delayed fill lost the conservative local-mapping discard and failed
the dual-slot unit. Strict Verilog-2001 required moving a forward declaration;
final source bytes were requalified after that nonfunctional fix. Earlier failed
harness attempts had no FIQ source or no real write/walk overlap; they are not
qualified results. No assertion was waived and no donor CPU/phone run occurred.

[Full resource/latency comparison and matched-fit plan](../../../docs/tlb-area.md).
