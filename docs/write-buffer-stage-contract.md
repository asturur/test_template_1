# Write-buffer reservation and local commit

2026-11-09. Baseline62c3707 restores the original cache L0/Quartus guards from
6adaf61 and rejects the admission snapshot experiment. This slice changes only
`arm920_write_buffer` and its tests; cache lookup, CPU, translation, bus merger,
SDRAM and peripheral protocols remain unchanged.

## Physical target

In fit42542334870 the worst sampled buffer path is−1.536ns: merger state→ACK
qualification→word index/final-beat decision→merge_single→new_group (fanout432)→
wide data enable. A tail-selected length/address also feeds merge. The change
separates narrow reservation from bulk payload writes; no timing exception or
clock change is introduced. The fit remains necessary to evaluate both stages.

## Acceptance reserves real capacity

The public handshake is still `push_valid && push_ready`. Four address groups,
each at most four consecutive words, remain the entire admitted capacity. A
pending record is already one of those reserved words/groups, not a fifth group.
`count`, `lengths`, address/first-line and last-line metadata update at acceptance.
Thus `entries`, `empty`, `full` and `query_line_pending` include uncommitted words
immediately after acceptance. A CP15 drain, aliasing refill or table walk cannot
pass through a reservation/commit gap.

`tail_slot`, `tail_length` and `tail_next_address` summarize the latest reserved
group, including pending data. Merge compares that registered summary, not a
selected per-slot metadata array. A single adjacent word can extend a group of
less than four words. A group retiring on this same edge cannot receive a merge.
A full buffer can accept a new group when its head retires, or extend its distinct
last group when eligible. Count changes once from `{new_group,group_done}`.
The tail summary is meaningful only when count is nonzero; a new group replaces
it after empty. The old per-slot next-address array is removed.

## One-clock local commit, pipelined every clock

`pending_data` and `pending_byte_enable` sample inputs unconditionally. Live
admission/ACK/merge does not control their wide register enables. Acceptance
captures `pending_slot`, `pending_length`, `pending_merge`, `pending_valid` and
sixteen `pending_word_enable` bits. Each enable belongs to one physical slot and
word. On the next edge local byte lanes write only that word from the previous
captured payload. Disabled byte data retains the old interface semantics: all
bits of the word are stored, with the byte mask determining bus side effects.

`committed_lengths[slot]` advances on that commit. The head is externally issuable
only when `word_index < committed_lengths[head]`. Retirement instead compares
against reserved `lengths[head]`; therefore a reserved but uncommitted final word
prevents group retirement. This distinction also preserves a held bus beat while
a later word is appended. Existing error priority is unchanged: error defeats
ACK, retains the beat, and requires clear/retry before another offer.

At edge N a new reservation can coincide with the previous packet's commit:

- Same-group append: commit advances the committed prefix; reservation extends
  the reserved suffix. The previous data remains selected until its ACK.
- Full head retirement plus slot reuse: the old group must already be committed
  to retire. The reused slot resets committed length to zero; new payload commits
  at N+1. A pending commit cannot target this retired slot, because its reserved
  word would have prevented retirement.
- Reset: count, indices, committed lengths and pending enables clear together.
  An old pending packet cannot reappear when the slot is reused.

Simulation-only generations verify pending-slot identity, and assertions check
tail-summary agreement and committed≤reserved length. They are enclosed by both
SYNTHESIS and Quartus translate_off/on guards. No generation decision is inserted
into hardware. No wide data promotion, delayed ready or extra capacity is used.

## Measured local latency and validation

The same directed tests and independent logical FIFO/byte/hazard model run against
frozen old and new buffer sources without replacing production files. The model
uses logical groups and per-word release clocks; it does not use physical slots,
tail summaries, pending masks or the DUT's ready/valid to decide its own state.

| Operation | Baseline | Candidate |
| --- | ---: | ---: |
|Acceptance→payload issuable (post-edge)|0|1|
|Sustained reservation interval|1|1|
|Four one-word pushes: first acceptance→last ACK|4|5|
|Eight one-word pushes: first acceptance→last ACK|8|9|

Pipelining adds one startup clock to these bursts, not four/eight enqueue bubbles.
CPU/cache buffered-store acknowledgment still denotes durable reservation. Actual
CPU, cache and fresh-boot timing must be measured separately from this local bound.

The randomized oracle passes12,021clocks:1347 new groups,328 merges,496 line
crossings,160 address wraps and1989 errors. It exercises24 pending words killed by reset,
1038 full retire/replacements,1021 simultaneous ACK/error cases and4 head-group
merge/ACK races. Directed checks cover immediate hazard/nonempty before commit,
reset then immediate reuse, held beats, one-per-clock appends and four/eight-word
streams. The cache access fixture passes384 resident stream requests and24
cancellation cases with unchanged isolated lookup latencies. Full regression is
172PASS+1expected legacy XFAIL,152 CPU cases including44 SWP interrupt-edge/wait
cases. Five mixed wait settings retain every reported phase/metric/counter, warmed
ADD1/load-use20/branch14 and totals243457/333957/408273/634683/1095735. All21,118
mixed architectural effects are identical. Fixed mix1729858→1729866 (+8) is from
cache_drain+4 at each wait; legacy135782/234446 is unchanged. Fresh5M real-SDRAM
matches all848 events/timestamps,121writes and12 known fetch faults with no data
faults. Phone/source/provenance/lint/elaboration and33timing-query mock checks pass.
Final RTL hashes match the frozen candidate. Detailed absolute counts are in
`scratch/timing-closure/write-buffer-reservation/validation-summary.json`.

The512-store write-through FIQ fixture (`fiq_flash_sequence`) changes260172→
260305clocks at0wait (+133,+0.05112%) and360910→361421 at3wait (+511,+0.14159%).
The handler executes128 iterations of four halfword stores. This exposes the
extra issuable clock on serialized stores; the setup-heavy total percentage is
not a claim of zero body cost. Buffered CPU completion still denotes reservation,
but bus drain and instruction-fetch ordering can expose the later bus issue.
The frozen-reference/current comparison matches all22,339 ordered architectural
effects and issue/retirement counts at each wait for this changed IRQ fixture.

## Next physical measurement

Five bounded buffer groups extend the existing cache/CPU reports: request→narrow
reservation, input→payload capture, pending→local commit, reservation feedback,
and buffer→bus owner. The renamed tail/pending/committed registers are explicit
report endpoints. Metadata reservation and head selection remain possible critical
paths; only bulk data/enables are behind the local commit edge. Fanout, resource
use, synthesis factoring and placement remain unmeasured. No104MHz closure claim.
ARM import provenance is unchanged:49 active patches through0050. The original
cache L0 and its independent admission timing issue remain separate work.
