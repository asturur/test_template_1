# Steps5B/5C — accepted result,17 November2026

**Both changes are accepted on sole master. No deployment was performed.**
5B improves measured timing;5C improves checked fixed-work throughput.

| Offline workload | Redesign start | 5A / 5B | Accepted5C | Reduction vs start |
| --- | ---: | ---: | ---: | ---: |
| Original matrix |52,275 |50,033 |**47,887** |8.3941% |
| Original transpose |5,328 |3,591 |**3,591** |32.6014% |
| Original Thumb JPEG |89,610 |84,353 |**84,353** |5.8665% |
| Drained64 ARM stores | — |71 |**71** |unchanged |

Both synthetic profiles0:0/2:9, scored windows, two repeats, original outputs
and negative controls pass.5C saves2146 matrix cycles (4.2892%) over5A/5B.
All1024 SMULL owners preserve exact products, paired writes and first-consumer
data; one redundant zero-addend hold is skipped. Busy6144→5120 is the measured
local change, not removal of all6144 clocks. [5C schedule/qualification](cpu-product-bypass.md).

Accepted sources: known working5A merge`6ac7a9d`; fitted5B commit
`419471d5cf85d2ca9d4cf6ff68a9652a1253ffd1`, bundle
`f3f199d1f9aa1eb0d995057d40be897c66caf399fc9378a41fdb9af255243181`;
5C bundle`ddacc3a42e90b9683e113c3ddb4f60a70a57742ffb70793f1566a06ec740ec6b`
with patch0076. Its60 compiled CPU RTL inputs match standard production paths.
Pristine upstream+patch replay passes. Historical non-RTL snapshot helpers do
not alter that compiled-RTL proof. [Adoption/1024-pair evidence](evidence/cpu-product-bypass-20261117.json).

The single seed42/debug-on master5B fit generated its verified78MHz RBF.
Hot setup−1.970→**−1.258ns at78**,−5.175→**−4.463ns at104**;
ALMs41147→**40828**, placed40981→40814, registers45095→45279,
M10Ks502/DSPs41 unchanged. CPU TNS−304.683→−28.437ns;203 late-owner
negative endpoints disappear. Packing remains4188/4191 LABs, three free.
Retain5B: zero cycle cost, fewer ALMs and materially better setup/TNS outweigh
one fewer free LAB. [Fit report and direct RBF](cpu-owner-split-fit.md).

Timing remains unclosed. The worst family is private probe selection → tag/way
matching → collision/coverage → adapter feedback (13.679ns,12levels). Retiming
that local owner boundary is the next physical action; no exceptions should
hide it.5C has no physical fit and is not in the collected5B RBF. No second
fit, fit-only ref or phone command was issued.

Ranked next broader throughput work:

1. General paired multiply result/operand delivery: high-half restart still
   accounts for2048 busy clocks; three helper consumer heads show3072 hold
   observations. Trace their shared critical interval: these are not additive
   savings. Preserve registered DSP products and paired fault/flag ownership.
2. General frontend target/fetch-to-operand replenishment:14765 matrix clocks
   remain in the empty bucket. Scope a measured handoff before adding queues
   or predictors; that bucket is not an avoidable-cycle budget.

Master consolidation/retirement finished before5B. All integration/snapshot
history remains reachable, fit tags remain provenance, and unrelated working
edits/assets/caches/runs/checkpoints were preserved. [Receipt](master-consolidation.md).
Andrea personally reports the newly built core runs on MiSTer but perceived
performance remains short of the goal. No numeric board score was supplied;
this observation neither measures these offline gains nor closes timing.
