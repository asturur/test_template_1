# ngage2 versus accepted5C: original-workload comparison

17 November2026. **The donor wins five of six kernels at equal clock;5C wins
full-frame fill.** The six-case geometric throughput ratio is **1.8752× at0:0**
and **1.5495× at2:9**, relative to5C. These are fixed-work CPU/cache results,
not official SPMark points, FPGA frequency, board FPS or whole-phone speed.
Original Thumb JPEG, measured separately, is **2.327× /2.303×** faster.

## Absolute results

Ratio =5C cycles /ngage2 cycles: above1 favors ngage2. All rows PASS original
byte/output/math/Unicorn checks, seven paired windows (two warmups/five scored),
two identical repeats and deliberately wrong expected-output rejection. Every
scored ordinary-retirement PC sequence in the six ARM kernels matches between
CPUs, including wrapper instructions. Medians below retain the original window.

| Workload; identical work | Profile |5C cycles |ngage2 cycles |Donor throughput ratio |
| --- | --- | ---: | ---: | ---: |
| matrix4;16 matrices |0:0 |47,887 |23,675 |2.0227× |
| matrix4 |2:9 |47,887 |35,925 |1.3330× |
| transpose4;32 transposes |0:0 |3,591 |1,910 |1.8801× |
| transpose4 |2:9 |3,591 |3,484 |1.0307× |
| triangle_edges;16 setups |0:0 |23,918 |12,634 |1.8931× |
| triangle_edges |2:9 |23,918 |13,844 |1.7277× |
| fill16_frame;36,608 pixels |0:0 |71,259 |105,069 |0.6782×;5C wins |
| fill16_frame |2:9 |201,302 |275,892 |0.7296×;5C wins |
| fill16_tail;1,023 pixels |0:0 |2,078 |707 |2.9392× |
| fill16_tail |2:9 |2,078 |760 |2.7342× |
| fill8_tail;2,051 bytes |0:0 |2,172 |717 |3.0293× |
| fill8_tail |2:9 |2,172 |743 |2.9233× |

All donor scored windows are constant.5C scored ranges: frame2:9
201,300–201,302; fill16_tail2,078–2,086 in both profiles; fill8_tail2,171–2,172
in both. Other5C six-case rows are constant. Full raw windows, cycles/useful
operation, output hashes and exact-PC sequence hashes are in the
[machine-readable receipt](evidence/ngage2-vs-5c-20261117.json).

## Frozen scope and inputs

5C is commit`78d53d4c129e761d979794c38398aa72ecf87f87`, frozen using Git object
reads without checkout/index/ref changes. All46 compiled CPU/cache translation
units match that commit and the previously qualified
`product-candidate-final-02` sources. The snapshot also preserves includes.
The accepted matrix47,887/transpose3,591/JPEG84,353 values reproduce. Missing
exact5C triangle/fill controls were collected here. Other chat's5D is excluded.

Donor is read-only checkout`/Users/andreabogazzi/develop/ngage2`, revision
`23541bb5519972eccd38eb6a4912472a50b5b6fc`. Its selected CPU files were clean.
`files.qip` selects`rtl/cpu/arm925t_gen.v`; its`arm925t` top instantiates
`zap_top.g_arm9.u_arm9_core`, an actual`arm9v2_core`, and its own cache/MMU.
We compiled that generated QIP input in place with the donor's existing
`sim/stubs/altsyncram.sv` and`altdpram.sv`, through a read-only container mount.
No donor RTL was imported. The generated top, original SV source closure,
QIP and simulation-model hashes are recorded in the donor manifest; selected
compile hashes are repeated in the receipt. Dependencies were rehashed after
execution. The generated netlist's synthesis-selected RAMs use those existing
behavioral primitive models, not replacement caches.

Actual geometry here supersedes the older donor audit's32KiB defaults:

| Configuration |5C |ngage2 selected top |
| --- | --- | --- |
| I/D capacity |16/16KiB |16/8KiB |
| Associativity/line |64ways,32bytes |2ways LRU,16bytes |
| TLB |Separate64-entry associative mixed-page TLBs |Separate64-entry direct section buffers; small-page256sets×2ways, other page-size buffers |
| Identity |Existing ARM920 compatibility identity |TI ARM925T CP15`54029252`/cache type`05109149` |

Both CPUs have MMU/I$/D$ enabled at every actual begin boundary, checked in
RTL. Identical guest page tables use AP3/domain0 client, cacheable/bufferable
sections (`...c0e`) for wrapper, payload, firmware and RAM; mailbox is uncached
(`...c02`). Virtual RAM`80000000` maps physical`0a000000`. TTBR is`0a01c000`.
Payload is the same preferred E32 image, data/stack/layout/arguments/warmup
unchanged. GLES division calls the normally linked original EUSER1514 at
`503a2f6c`, with checked original ROM/IAT/export identities. Every triangle
window executes6,656 GLES plus1,872 original firmware helper instructions.
There is no host division, rendering stub, replacement timed work or extraction.

## Backing-memory contract

Installed`jotego/simulator:arm64`, image
`sha256:df6f55924d5fab96083d01332e45cd734f22277c4dd3b34f55a09cd8dbc3eb8d`,
Verilator5.050; all containers use networking disabled and no image pull.

Both use one serialized backend and the **existing asymmetric fixture contract**:
scalar reads and all writes carry32bits per acknowledged word, with the selected
I/D extra wait charged to each word (0wait permits one word/clock;9wait requires
ten offered clocks). Read refills carry16bits/clock after a single transaction
startup delay.5C receives sixteen halfwords per32-byte line; donor's four32-bit
wrap-4 read beats aggregate pairs of halfwords per16-byte line. Donor first
word ACK is initial wait+3 clocks after initial offered edge, matching5C's
registered delivery of its first two halfwords; later read words require two
clocks. Burst writebacks use the scalar32 per-word wait, including every beat:
burst framing never discounts write latency or changes write bandwidth.
Instruction/code regions use I waits, RAM uses D waits. This preserves the
accepted5C responder rather than silently charging its existing posted writes
as a new physical16-bit bus. It is a synthetic contract, not SDRAM timing.

Native bus framing,16/32-byte refill lengths, critical-word ordering, cache
geometry, buffering, TLB conflicts and internal register boundaries remain
real differences; exact transaction-for-transaction equivalence is impossible.
No CPU/cache configuration was changed to manufacture equivalence. Initial
smokes and`donor05` used an unmatched burst-write rule and are superseded by
`donor06`; their numbers are excluded. Read-fill and write bandwidth must not
be inferred from a single combined beat count.

## Measured memory traffic

These are representative scored window2 physical32-bit read/write words,
including scalar table walks and read-refill words. Cache-resident operations
are absent from this table. Donor native read-line count is separate; every
complete donor read line is four words/eight halfwords. Full raw counters for
all windows remain in the receipt.

| Workload/profile |5C external reads/writes |Donor external reads/writes |Donor read lines |
| --- | ---: | ---: | ---: |
| matrix0:0 |0/0 |2,872/1,280 |694 |
| matrix2:9 |0/0 |2,870/1,280 |694 |
| transpose0:0 |0/0 |196/0 |1 |
| transpose2:9 |0/0 |197/0 |1 |
| triangle0:0 |0/0 |161/0 |0 |
| triangle2:9 |0/0 |158/0 |0 |
| frame0:0 |0/18,305 |18,315/17,280 |4,577 |
| frame2:9 |0/18,295 |18,315/17,280 |4,577 |
| fill16_tail0:0 and2:9 |0/0 |6/0 |0 |
| fill8_tail0:0 and2:9 |0/0 |3/0 |0 |

**Warm zero-external-traffic cases:**5C matrix, transpose, triangle and both
small fills. Donor small fills and triangle have warm cache data but still
perform section-table walks; donor transpose also fetches a data literal line.
Thus no donor row in the unchanged six-case layout is strictly zero-external.
Full frame exceeds both D-cache capacities and is a fill/writeback-sensitive
case, rather than evidence for warm execution throughput.

Some table-walk counts differ by1–3 with profile: requests can overlap the
retired end marker and following untimed check. This is an observed window
alignment effect, not a difference in the matched architectural instruction
sequence. The original timing/counter boundaries have not been moved.

### Posted writes after the window

At2:9,5C frame ends with pending writes; all five scored windows acknowledge
18,295 writes inside the original window, then10 more before the existing
write buffer/store reservations first become empty. A separate passive observer
adds no stalls or guest instructions. Exact original window counters reproduce:
first-empty extension105–107clocks, **body+first-empty201,407clocks** for every
scored window. Donor frame has no pending posted/victim writes at that boundary:
extension0, body+first-empty275,892. This separate ratio is0.7300× donor/5C
throughput; it does not replace the original201,302/275,892 median row.

At0:0 neither frame row has pending writes at the end. Other six-case scored
end boundaries have no posted-write reservations. Donor sometimes has a pending
read (matrix, triangle2:9); that is distinct from a pending write. Dirty resident
cache lines remain possible on both cores; first-empty is not a full clean to
backing RAM. The unchanged guest performs its final CP15 clean before checked
mailbox completion. The passive metric runs the normal check code concurrently;
it is not a stop-the-CPU drain experiment.

## Why the results differ

**Matrix: faster helper/call delivery outweighs donor misses.** All1,024 actual
SMULL paired R2/R3 writes match independently generated signed products from
the identical A/B input words and original unrolled row/column/k load order. At0:0, across all1,024
calls, BL retirement→helper SUB retirement has median6clocks5C versus1donor
(ranges4–11 versus1–5); helper BX→next caller instruction has median7 versus1
(ranges7–18 versus1–8). Helper SUB→SMULL retirement is median7 versus2
(donor1–9). SMULL retirement→first MOV consumer is median1 on both; this last
number alone does not measure multiplier latency.5C already has an effective
local product bypass. These are elapsed retirement intervals, not additive
recoverable budgets or timing-closure evidence.

Donor matrix also performs real refills/dirty evictions: the A/B/output buffers
are4KiB apart and collide in the8KiB two-way D-cache's256sets (VA bits11:4).
Scored traces show1,280 dirty external write words and2,776 refill read words.
5C's64-way16KiB cache retains this working set. With real waits, donor advantage
falls2.02×→1.33×. We did not relayout buffers to hide that conflict.

**Transpose:5C's first pair is already better; donor replenishes sooner.** The
first original pair at`10002644/648/64c/650` retires at relative
`0,1,2,3` on5C, versus`0,3,5,6` on donor (all32 calls). From the second STR to
next LDR:4clocks5C,1donor. First LDR→BX across the whole function is median43
versus32clocks; BX→caller`000000cc` is19 versus2. The donor wins overall at
0:0, although it loses that particular already-optimized first load/store pair.

Its2:9 near-tie is explained by **section TLB conflict**, not cold matrix data:
192/193 scalar reads are page-table descriptors at`0a01c000`, `0a01c400` and
`0a01e000`. Donor section index is VA[25:20]; wrapper section0, payload100 and
RAM800 alias index0 despite the much larger two-way *small-page* TLBs. The
identical guest uses sections.5C's associative TLB avoids these walks. Triangle
and small-fill scalar reads show the same distinction.

**Triangle:** identical original geometry and division execute substantially
more densely on donor (8,657 total ordinary retirements on both). Donor still
wins1.73× at2:9 despite158 scalar descriptor reads. This is a combined
execution/branch/cache/MMU result; this benchmark does not isolate one divider
or one frontend change as its exclusive cause.

**Small fills:** original eight post-indexed`STR r1,[r0],#4` instructions expose
the loop-carried base update. In the first scored fill16 loop, retirement offsets
are`0,3,6,9,12,15,18,24` on5C and`0,1,2,3,4,5,6,7` on donor; fill8 shows the
same pattern. Following SUBS/branch offsets are25/27 versus8/9. The donor
sustains that dependent store stream efficiently. The earlier71-cycle synthetic
plain-store result does not promise one clock for these post-indexed original
instructions. Full output guards/unaligned/halfword/odd tails pass.

**Full-frame fill reverses the result:** donor's faster execution is outweighed
by write allocation and dirty eviction of a73,216-byte range through8KiB D$.
Its scored trace reads18,304 RAM refill words before overwriting them, plus
seven scalar descriptor words and four code/literal words, and writes17,280
dirty words during the window.5C posts write misses without allocating those
read lines and performs no scored external reads. Donor costs47.4% more clocks
at0:0 and37.1% more at2:9. Remaining dirty cache residency differs, so this is
the original checked CPU/cache window, not equal quantities fully flushed to
RAM. The separate pending-write drain above does not change the conclusion.

## Separate original Thumb JPEG block

Same original firmware error-diffusion block, real8×8 JPEG-derived pixels,
64pixel work, all object/error/source/destination/guard outputs checked. Not
part of the six-case geometric index.

| Profile |5C median (scored range) |Donor median |Throughput ratio |
| --- | ---: | ---: | ---: |
|0:0 |84,353 (84,353–84,399) |36,251 |2.3269× |
|2:9 |84,353 (84,353–84,417) |36,631 |2.3028× |

Both two-repeat runs and wrong-output control pass.5C's last four scored
windows have no external traffic; first scored window has one line/eight scalar
reads. Donor has30 read lines,1 scalar descriptor read and92 write words each
scored window (121read words total), no pending writes.

Unicorn and5C count each Thumb BL pair once; donor completes prefix and suffix
as separate architectural halfwords. Raw donor payload count23,405 versus22,500
is exactly905 extra suffix completions at19 verified original BL sites.
Every donor scored trace PC histogram matches the independent oracle plus
these explicitly decoded suffix PCs/counts; no other extra or missing PCs are
accepted. This resolves an observer-unit mismatch, not a faster replacement
workload. Initial JPEG donor01 is retained as a failed qualification attempt;
only donor02 is included. No CPU-wide CPI comparison uses these raw totals.

Donor W debug taps are not a complete register-file journal: background load
returns also write another port. Naively replaying W destination fields alone
leaves stale source values. Product qualification therefore uses the checked
original input bytes/load order and all actual paired result words, rather
than misidentifying that incomplete observer view as a CPU arithmetic failure.

## Observer qualification and artifacts

The donor observer uses top-level completed W-valid/condition-fail, last-uop,
no-exception signals, with ARM PC−8/Thumb PC−4. Source audit confirms valid is
completion-qualified and suppressed under WB flush; restore beats are not last.
It does not watch speculative fetch or borrow ZAP hierarchy. Actual directed
guests pass: a held uncached marked load (37wait, one completion), a W-redirected
skipped marker pair (zero windows), and a marked translation-faulting LDR with
real data abort/return (zero windows). Original matrix output checks also pass
in those controls. The exact final donor06 executable is qualified.

Maintained benchmark-only helpers: `tests/cpu/ngage2_compare/`.
Main artifacts:

- `build/sim/spmark-payload/ngage2-vs5c-control03/`
- `build/sim/spmark-payload/ngage2-vs5c-donor06/`
- `build/sim/ngage2-observer/donor06-qual01/`
- `build/sim/spmark-payload/ngage2-vs5c-drain-{control,donor}01/`
- `build/sim/jpeg-payload/ngage2-vs5c-jpeg-{control01,donor02}/`

Each contains frozen harness, source/input/tool hashes, exact local guest inputs,
bounded logs and results. Machine receipt contains no firmware/game/image bytes.
A disk-space/I/O failure interrupted early builds; Docker became unresponsive.
The user explicitly authorized its restart; the supported force-stop/start
recovered the same installed image. Only this comparison's compiler
intermediates were removed. No production RTL, shared index, refs, CI, Quartus,
phone, card, mainline status or other run/checkpoint was intentionally changed.
No physical fit or frequency-normalized speed estimate is claimed.
