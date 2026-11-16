## Production adoption — 2026-11-16

User authorizes promote, push, build and MiSTer deployment. Patch0072 is now in
production RTL.92actual CPU architecture runs and44IRQ/FIQ boundary runs pass;
118predictor controls pass. Both complete production benchmark suites reproduce
the isolated result exactly: six-kernel raw counters unchanged, JPEG +9.4036%,
index132.6505. All compiled RTL files byte-match both frozen benchmark sources.
83pristine upstream hashes and37reconstructed lexical streams pass. Actual78MHz,
104MHz objective; four added hint bits, no new RAM/stage. Physical area/timing
and native deployment remain pending; historical prototype notes follow.

# Next JPEG CPU target: recognize Thumb POP/BX returns

All work after the user's local-only direction runs on the Mac/offline existing
Verilator image. No subsequent MiSTer input, reset, reload, capture or memory
access is used. Production RTL remains ecd018d. The prototype is an isolated
source substitution in the benchmark freezer, not enabled by the Quartus QIP.

## What the current local workload does

The hash-qualified original ROM bitmap/error-diffusion code finishes correctly.
It does not hang in the extracted workload. This harness does not run the full
Symbian application, decoder server or JPEG encoder, so it cannot identify the
current full-phone wait or a new edition's deadline/callback ordering. The older
observed input-decode timeout remains historical evidence, not a new diagnosis.

The current8x8 JPEG case takes98,072cycles. One measured warm window contains
28,970data-wait clocks,22,993empty-operand clocks and13,834load-dependency clocks.
There are no external reads/writes in its scored warm windows. Counts are stall
occupancy, not additive causal loss:3,633empty clocks overlap retirement. Cache
waits remain large, but frontend attribution gives a smaller concrete change
before redesigning cache or CPU request parallelism.

The refined observer matches every original raw counter/profile exactly.
Accepted ALU outcomes in one scored window include585`POP {r0..r7}; BX same reg`
returns: all585require late correction.192other indirect BX operations and64
ordinary BX-LR operations also need correction;19other branch outcomes redirect.
The predictor recognizes BX LR/MOV PC LR/load-to-PC but misses the low-register
POP/BX shape emitted throughout these original Thumb helpers. Missing pops also
leave its existing circular return stack poorly synchronized.

## Isolated measured experiment

Remember the last accepted single low-register Thumb POP in4bits (valid plus
three-bit register). A following matching BX may use the existing return stack.
Any intervening accepted instruction, reset, older flush or ARM mode prevents
that hint. Bubbles and stalls preserve the accepted owner. ALU still verifies
the actual loaded branch target and state; no POP load or architectural check
is removed. Predictor guesses remain guesses. This does not implement complete
speculative-RAS rollback or change the existing stack's depth/overflow policy.

| Original-code case | Current cycles | Prototype cycles | Throughput gain |
| --- | ---: | ---: | ---: |
|8x8 JPEG, mode10|98,072|89,610|9.44%|
|8x8 random, mode10|98,088|89,626|9.44%|
|8x8 random, mode8|96,623|88,518|9.16%|
|16x8 JPEG, mode10|193,536|176,626|9.57%|

All8case/profile groups pass2exact repeats,7checked windows and4bad-output
controls with original instructions, object/error-buffer/pixel/guard oracles.
Both synthetic wait profiles give the same medians. Some first scored mode10
windows need extra training/fetch work: ranges are89,610..89,655or89,673 for the
first case, not an assertion every measured window equals its warm median.
JPEG's original100 index would advance121.2488→132.6505 (+9.4036%); this is an
experimental local kernel index, not an official SPMark score or whole-phone gain.

In the first scored window, empty operand clocks fall22,993→15,900 and ALU
clear cycles860→340. Recognized POP/BX late corrections fall585→65. Early decode
clear cycles increase1,100→1,675: the benefit is earlier target availability,
not fewer total clears. Data-wait clocks are essentially unchanged. The prototype
starts fetching the caller earlier while the load/older instructions complete.
The first scored prototype window has89,655cycles, so do not compare its whole
occupancy profile to the89,610median as if they were the same observation.

Existing22return classifications pass. An extended118-classification fixture
covers all8low-register pairs, mismatched BX operands, intervening instructions,
writeback/ALU clears and Thumb/ARM switching. It is still not full architectural,
interrupt, data-abort or physical timing qualification. Actual added ALM cost,
routed78MHz/104MHz timing and native performance are unmeasured. No added RAM,
DSP or pipeline stage;4declared hint-state bits.

The recommended next implementation is this return recognition, after promoting
the new controls and completing CPU/IRQ/abort qualification. Next after it:
reprofile remaining cache-hit/store waits with this frontend bottleneck reduced.
Do not assume larger caches, more DSP multiplication or PSR changes accelerate
this converter: its current multiply occupancy is zero.

Reproducer/isolated source are in scratch/jpeg-next-profile-20261116; accepted
raw runs in build/sim/jpeg-payload/{frontend-attribution-v3,pop-bx-return-full}-20261116.
Only zap_predecode_main.sv differs between compiled variants. The first observer
used a wrong instance name and failed before CPU execution; v2 then overcounted
predecode candidates held by mem_fetch_stall. V3 gates that acceptance and passes
all original counters. Neither fixture error is evidence of an RTL defect.
[Measured evidence](evidence/jpeg-next-profile-20261116.json),
[reviewable experimental patch](evidence/pop-bx-return-prototype-20261116.patch).
