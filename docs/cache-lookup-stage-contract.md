# Cache lookup ownership: slice2 contract

2026-11-09. Initial baseline is the restored patch0048 CPU (`57bf13d` revert commit,
RTL equal to `71b8940` before the cache change). Patch0049's forwarding experiment
remains rejected and archived. This slice changes cache request/address ownership;
it does not redesign the write buffer, translation engine, SDRAM or CPU forwarding.

## Accepted owner and bank address

The first L0 fit42527340861 (`6adaf61`) passes owner→tags+1.328ns,
lookup pipeline+1.829 and response+1.129, but leaves request→owner−1.140:
writeback PC→stream hit→admission qualification→wide address capture. The
following admission refinement preserves all pipeline edges and public handshakes.

`arm920_cache_access` samples three candidate records independently of admission:

- `lookup_demand_mva` and `lookup_demand_segment_select` sample the live demand
  address on every registered-IDLE edge, then hold throughout a busy operation.
- `lookup_maint_mva` and `lookup_maint_segment_select` do the same for maintenance.
- `lookup_ahead_mva` and `lookup_ahead_segment_select` sample the resident-only
  lookahead address every clock. Changes while busy cannot acquire ownership.

Only narrow `lookup_owner_valid`, one-hot `lookup_owner_kind` and
`lookup_owner_epoch` depend on accepted maintenance/demand or an eligible idle
lookahead offer. Priority remains maintenance, demand, then lookahead. The exact
`req_valid && req_ready` and maintenance handshake is unchanged. A post-register
masked OR selects `lookup_owner_mva` and its coherent eight-bit segment select
from the three records; these names are now combinational aliases, not FFs.
No live hit/ACK/request-valid decision controls any wide address capture. That
control still reaches the narrow grant and FSM; its timing must remain visible.

Demand `mva` and `saved_maint_address` reuse the corresponding snapshots, replacing
their former separate storage. Total address storage therefore remains three
32-bit words. Segment snapshots add16bits and the one-hot kind adds1bit before
synthesis optimization; routed resource use remains unmeasured. No metadata array
or cache line is duplicated. Tag RAM and victim addressing use the selected
registered binary segment; per-way valid/dirty reads use its registered one-hot
segment. The64-way compare and balanced selection remain unchanged.

Idle unaccepted snapshots have no architectural effect. Background write-buffer
drain uses its own FIFO address/data; its hazard query still uses accepted physical
`pa`, which is unchanged. Refill and maintenance start only in their owned states
and preserve their internal records. A read response captures its selected word
before returning to IDLE. Thus none of these consumers can use an invalid idle
virtual-address snapshot. A logical-owner scoreboard and held-bus assertions check
accepted ownership, busy hold, rejected offers and pending background drain.

A serialized owner holds its address and kind through lookup, store, write-buffer
wait, drain, dirty replacement, refill, retry and maintenance. Live offer inputs
may change immediately after acceptance. `LOOKUP_CAPTURE` adds one initial edge
only when cache-enable and C are both set. `MAINT_CAPTURE` does so only for MVA
maintenance. Uncached/buffer-only requests and indexed/all maintenance retain
their old entry timing. The owner remains fixed across refill; existing post-fill
read/compare drain stages suffice without recapturing L0. A held write buffer
or bus request still obeys its original ownership/acknowledgment contract.

Assertions check owner presence/kind during every busy state, MVA stability,
one-hot/address consistency, and the address consumed at cached/MVA decisions.
Standalone bank/tag callers now provide a coherent `lookup_segment_select`;
their original two-edge tag interface remains unchanged.

## Resident lookahead, cancellation and response association

L0 is also the registered lookahead PC; there is no fifth lookup stage. Its
address/epoch token travels alongside the existing RAM-read, compare and line-read
edges. `fast_read_*`, `fast_compare_*` and `fast_result_*` retain that identity.
The compare token must match `bank.lookup_address`, and the result must match
the active epoch before it can enter either of the existing two stream lines.

| Edge | Lookup action |
| --- | --- |
|0|Accept L0 address/kind/segment/epoch|
|1|Tag RAM and valid/dirty snapshot; read token|
|2|Registered match/way information; compare token|
|3|Line RAM result; result token becomes visible|
|4|Insert that result into a stream slot; a serialized read response is visible|
|5|Caller samples serialized response|

The I wrapper supplies `i_address + 16` independently of current ACK. Four ARM
words give the added owner edge its required lead; Thumb requests advance more
slowly. Lookahead remains resident-only: it never changes the serialized FSM,
allocates a line, starts a refill or emits a bus read. A wrong-path/page-crossing
resident read is harmless. Actual fast completion still requires the exact
requested address, current TLB permission/fault qualification, cache-enable and C.

Accepted demand, maintenance, invalidate, lock, reset or disabled fast lookup
kills every speculative token and both stream-valid bits. Demand reads can seed
their own returned line after older tokens have died. A one-bit epoch accompanies
all tokens/results/stream entries; every epoch change also clears all valid tokens,
so no old token survives a wrap. Re-enabling fast lookup must traverse all four
edges again. The I wrapper disables fast lookup on MMU/cache-enable, CPSR-mode,
S/R, TTBR or DACR change, or TLB invalidation. FCSE identity remains in the full
MVA key; permission is never borrowed from a speculative read. Existing CP15
prefetch/restore and translation ownership are unchanged.

`fast_lookup_valid` deliberately does not depend on `req_valid`: the adapter
computes request admission from `!fast_hit`, so such gating would form an ACK
loop. A write offer may observe a resident line before its acceptance edge, but
cannot use a fast read completion; acceptance cancels that old stream immediately.

## Measured latency and throughput

The same cache fixture runs against frozen baseline sources without replacing
production RTL. These counts run from acceptance edge0 to visible response/done
(post-edge observation); the caller samples response one clock later.

| Operation | Baseline | Candidate | Delta |
| --- | ---: | ---: | ---: |
|Clean read miss, immediate bus|22|23|+1|
|Cached read hit|3|4|+1|
|Write-back store hit|4|5|+1|
|Uncached read|3|3|0|
|MVA clean|11|12|+1|
|Indexed invalidate|5|5|0|
|All512-entry invalidate|1538|1538|0|

Stage-specific cancellation quarantine assertions apply to the candidate; shared
functional, latency and streaming stimuli run on both source sets.
No per-line scan penalty or additional post-fill owner edge was introduced.
384 resident ARM/Thumb-sized requests cross16lines at one request per clock,
with zero speculative external transfers.24 tests cancel at each of the four
owner/read/compare/line positions using disable, lock, invalidate, reset, MVA
maintenance or accepted store; no old token reappears, and the next store lookup
returns the new data. The request driver poisons address/PA/data/mask immediately
after acceptance. Existing dirty-eviction/alias/error/maintenance tests remain.

CPU phase tracing distinguishes the mixed issue gap from cache-hit service:

| Warm cached load phase | Baseline clocks | Candidate clocks |
| --- | ---: | ---: |
|Load issue→accepted D-cache request|11|11|
|Acceptance→sampled cache response|4|5|
|Cache response→owned completion|1|1|
|Owned completion→dependent issue|3|3|
|Total issue-to-issue gap|19|20|

These are observed phase boundaries, not a claim that all11 pre-accept clocks are
an irreducible architectural requirement. The cold0wait example changes77→80:
pre-accept18→19 and service55→57, while completion/release stay1+3. Bus arbitration
and instruction-fetch phase affect cold wall time; the isolated clean miss adds
only one internal lookup clock. At3waits the first cold gap stays129, while the
nine warmed gaps increase19→20. Current load-use work should not call19/20 the
cache-hit latency.

Mixed0/3/7/15/31wait totals are243457/333957/408273/634683/1095735,
+52/+54/+51/+51/+51 over baseline. Setup increases2clocks at every wait; cached
body changes1414/1668/2018/2742/4194→1464/1720/2067/2791/4243. Warm dependent
ADD remains1clock; branch minimum stays14. Issue/retirement and accepted-fetch
counts are unchanged. Full regression passes172cases plus1expected legacy XFAIL,
including152 CPU cases and44 SWP interrupt-edge/wait cases. The independent
operand oracle passes56,251clocks. Fresh5M real-SDRAM boot matches all848 events
including timestamps,121 writes and12 known fetch faults (no data faults).
All21,118 ordered architectural effects match byte-for-byte. The fixed four-program/
two-wait mix changes1729724→1729858 (+134,+0.00775%); legacy0/3 remains
135782/234446. Full absolute counts and hashes are in the validation JSON.

## Physical gates and evidence

The next fit must measure request→wide candidate capture, request→narrow
admission control, selected L0→tag/flag reads, lookup/token pipeline and
cache→response separately. The existing24 CPU groups remain; six cache groups
make30. Actual snapshot FFs and the registered kind are report endpoints; the
selected owner aliases must not be mistaken for registers. The post-register
three-way selection uses some of the formerly positive owner→tags budget; that
prior+1.328ns result cannot be inherited by this candidate. Registered one-hot
fanout and mux placement still require routed evidence. CPU forwarding, shifter,
cache transfer/maintenance, write-buffer,
SDRAM and peripheral paths remain independent open timing work. No frequency,
clock relationship or timing exception was changed;104MHz closure is not claimed.

Evidence: `scratch/timing-closure/cache-lookup-owner/`, including source snapshots,
phase-reference/current logs, cache-access differential, frozen-source hashes and
final validation summary. Prior checkpoints and rejected experiment evidence are
preserved. Simulation verifies the stated RTL contract, not a physical phone.

## Admission-refinement validation

Candidate RTL is frozen against `6adaf61`. The expanded directed fixture passes
11,029 logical-owner edges,384 streaming requests and24 cancellation races.
It also changes24 idle candidates while a buffered store waits for ACK, tries8
lock-denied offers, and collides maintenance with a store. The accepted owner,
held bus payload and exact-once store effect remain correct. All isolated cache
latencies in the table above are unchanged. Full regression172PASS+1expected XFAIL
includes152 CPU cases/44 SWP edge×wait cases; every absolute cycle and reported
counter matches the baseline. All five waits, fixed mix1729858, legacy135782/234446,
21,118 effects and848 fresh5M boot events (including timestamps) are identical.
Final hashes match frozen RTL. Comparisons are recorded in status and
`scratch/timing-closure/cache-admission/validation-summary.json`. The Quartus17
synthesis translate_off/on assertion guard remains.
No ARM import changes are needed;49 active patches through0050 still reproduce.
