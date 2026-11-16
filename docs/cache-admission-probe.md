# Consume the admission-edge cache pre-read — 2026-11-16

An ordinary checked resident read can use the synchronous RAM-B result that
finishes on its demand-admission edge. Previously the controller entered
LOOKUP_CAPTURE and then READ_LINE even when that exact read had already
completed. The change removes one wait for this case. Other short-hit waits
and the larger multi-request pipeline remain separate work.

## Ownership and timing

The existing resident-line facts identify the accepted line and selected way.
The existing probe owner names the actual RAM-B address sampled on the edge.
A new one-bit `admitted_probe_owner` captures a match only when all of these
conditions hold:

- The demand is accepted, is an ordinary cacheable read, and has passed the
  adapter's actual translation, permission and alignment checks.
- The selected resident fact is current and present.
- The existing probe issues on this edge with a free RAM-B port, valid owner,
  no revocation and no same-slot RAM-A write collision.
- The probe's full line address and selected way match the accepted demand.

After the edge, the new bit and the captured request own the existing BRAM
output. The reply selects its word with captured MVA, regardless of the next
P1 probe address. No live address/way comparison feeds the response path. The
existing CPU completion register still captures the data and fault context.
The controller returns to IDLE on the consumer edge, producing one response.

The credit defaults to zero each clock and reset clears it. Maintenance/reset
response gating remains. An offer of maintenance after demand admission cannot
steal the accepted request; the adapter serializes its actual acceptance.
Stores retain LOOKUP_CAPTURE because their fresh dirty/tag snapshot is needed.
SWP, uncached reads, misses and unsupported classes keep their old boundaries.
The DATA_PROBE=0 paths have a constant-false credit; no I-cache shortcut is
introduced. Existing collision invalidation and forwarding remain authoritative.

There is one new metadata flip-flop and a comparison feeding it. There is no
new RAM, copied line, memory port, stage, outstanding-request slot or CPU-wide
advance path. Actual PLL remains78MHz;104MHz is the timing objective. Fitted
area and routed timing require the FPGA build; simulation cannot prove them.
The custom ARM920 cache changes; imported ZAP sources/patch0069 are unchanged.

## Evidence and measurements

A read-only witness on the accepted predecessor counts 2,973 indexed reads in
the first scored JPEG block. All have a matching admission-edge probe. Every
original guest counter matches the uninstrumented accepted result. There are
also3,015 indexed stores, which this change does not accelerate.

| Original bitmap work | Before cycles | After cycles | Throughput gain |
| --- | ---: | ---: | ---: |
|8×8 JPEG pixels, mode10|111449|108853|2.3849%|
|8×8 random pixels, mode10|111465|108869|2.3845%|
|8×8 random pixels, mode8|110320|107724|2.4099%|
|16×8 JPEG pixels, mode10|219849|214749|2.3749%|

Both synthetic I:D profiles0:0/2:9 repeat exactly. The four-case geometric gain
is2.3885%; its own original baseline100 index becomes109.1267. In the first
case, data-completion waits fall41008→38035 and READ_LINE clocks5180→2207.
Load dependency remains13161; empty operand clocks rise21245→21574. The2,973
removed data waits yield2,596 fewer total clocks because other work/stalls
overlap. Warm measured windows still issue no backing requests. Original
retirement count22508, response count11366 and redirect count1936 are unchanged.

The full original six-kernel index becomes **230.0365/193.4779**, relative to
the original baseline100, a0.6551%/0.6550% gain over the predecessor. Matrix
54730→54442; transpose5465→5337; triangle27201→26915; full-frame fill
71264/201307→71263/201306; fill16-tail stays2564; fill8-tail2628→2629. The
one-clock tail regression is retained in the score. These are fixed-work RTL
results, not official SPMark points, donor-relative speed or a native JPEG
deadline pass. Physical boot/JPEG qualification remains pending.

## Qualification and reproduction

- 92 CPU architectural runs and44IRQ/FIQ/SWP boundary runs: widths, mixed
  ARM/Thumb, permissions, alignment, faults, WFI, MMU and ordered maintenance.
- 10 existing cache/buffer unit groups, including DATA_PROBE=0 and packed dirty
  writeback equivalence. A poisoned mixed-port RAM variant also passes336
  requests,8 concurrent A/B clocks and122 blocked collisions.
- The new admission fixture checks256 short reads, three mismatches, every
  segment/word/mask, exactly one cache response even after the CPU drops its
  request, changed next address, fresh bytes, maintenance, denied accesses,
  translation waits, SWP, uncached reads and reset.
- Five exercised negative variants are rejected: disabled shortcut, missing
  full-line match, missing way match, live next-address word selection, and
  duplicate response. The first is a latency check, not proof the predecessor
  was architecturally wrong.
- Full six-kernel12case/profile groups, two exact repeats and six bad-output
  controls. JPEG8groups/two repeats,8unprofiled full-counter matches, original
  instruction counts and eight bad object/pixel controls.

Initial negative-test fixtures were insufficient: a different way concealed
the missing line guard, the next-address check ran before combinational
settling, and a response counter ignored pulses after request removal. Each
fixture was strengthened; the final positive test and all five broken variants
are rerun. Failed exploratory logs remain under scratch, not accepted evidence.
No production RTL change was made in response to these test-fixture gaps.

```sh
sh tests/cpu/cache_admit_probe/sim.sh
python3 tests/cpu/spmark_payload/run.py --name NEW-payload \
  --baseline build/sim/spmark-payload/admitted-probe-20261116/result.json
```

Raw evidence: `scratch/cache-hit-waits-20261116/`,
`build/sim/admitted-probe-cpu-20261116/`,
`build/sim/admitted-probe-units-20261116/`,
`build/sim/admitted-probe-poison-20261116/`,
`build/sim/spmark-payload/admitted-probe-20261116/` and
`build/sim/jpeg-payload/admitted-probe-20261116/`.
The maintained test is documented in
[its README](../tests/cpu/cache_admit_probe/README.md).
[Compact qualification and hashes](evidence/cache-admission-probe-20261116.json).
