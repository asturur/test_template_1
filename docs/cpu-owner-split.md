# Step5B — private CPU/cache owner selection

Control is published5A **6ac7a9d**, retaining its working bitstream and reports.
Its fitted hot WNS is−1.970ns at78MHz and−5.175ns at104MHz. The203 late-ready negative
hot78 endpoints originate at fitted late_p1_ready. Address selection depends
on final completion_next, which includes exact late-data readiness; that
selection fans through resident matching/cache req_ready into SWP acquisition
and board CPU exclusion. Simplifying only the tag mux would leave that cone.

The bounded candidate preselects address/direction/format/privilege/destination
with registered completion_valid. A completed P2 cannot issue again; final
completion_offer, with all previous readiness/fault/kill/reset checks, alone
admits P1. SWP tag remains P2: a true handoff requires both tags zero. The
private direction reaches cache req_write before final rd/wr qualification,
removing the strobe dependency from resident eligibility/req_ready too.
A parameter keeps all other adapter clients on their existing selected class.
Four RTL files change, with no added state and no timing exceptions.

Idle consumer audit:

- Top-level ONLY_CORE bus consumers qualify CYC/STB. The normal data cache
  qualifies rd/wr with the unchanged completion offer.
- TLB lookup/walk capture requires rd||wr and retains checked permission/
  context ownership. Idle address changes do not start walks or expose faults.
- Adapter pending translation clears on no demand/completion; held live demand
  still uses its same address/data/mask/context. Every offered packet is checked
  against5A's original completion_next selection.
- Cache private address matching/readiness may observe the preselection.
  Demand/refill/write/buffer admission requires req_valid&&req_ready. Fast
  completion requires qualified rd. Probe P1 and fallback P2 read valids retain
  their original qualification; idle bus fields cannot publish probe bytes.
- MMIO/bus merger sees only accepted cache/TLB transactions. SWP lock/tag,
  failed-read abort handling, write-buffer order and old DMA drain remain owned.
  Existing instruction-cache/other adapter clients keep PRIVATE_OWNER=0.

Checked original workloads retain **matrix50033, transpose3591, JPEG84353**
in both0:0 and2:9 profiles. The drained64-store stream remains71 clocks.
Focused fault/late-data/device/held ownership and ARM/Thumb/FCSE/prefetch
checks pass. Sixteen exact-source SWP/completion cases (eight guests×two delays), eight
ARM/Thumb/FCSE/fetch diagnostics, randomized completion hold/cancel/reset and
accepted-DMA drain under CPU lock pass. One matched physical fit follows.

The initial core-only preselection already preserved cycles, but gated wr
still fed resident eligibility/req_ready. The final four-file split addresses
that remaining structural dependency. A misplaced parameter in an early
binding failed compilation; corrected before final measurement. Early relocated
core test paths selected production instead of candidate; those runs are not
candidate qualification. The final runner explicitly freezes every module.
Local storage exhaustion interrupted later test builds; only this experiment's
rebuildable compiler files were removed. Docker retained deleted-file handles
until its stalled application was restarted; no unrelated container was running.
Executables, source hashes and evidence remain. No deployment/phone commands.

## Physical result and retained source

The single master run44001480657 passed compile/source audit/78+104 analysis/
SDRAM pin registers and uploaded its RBF; only timing acceptance failed.
Hot setup improves−1.970→−1.258ns at78 and−5.175→−4.463ns at104; ALMs
41147→40828 with zero cycle cost. Retain5B. The worst path moves from late
CPU owner selection to private probe tag/way/collision/coverage feedback.
Packing remains tight (three empty LABs). [Full fit report](cpu-owner-split-fit.md).
