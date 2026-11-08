# Cache lookup ownership: slice2 contract

2026-11-08. Baseline is the restored patch0048 CPU (`57bf13d` revert commit,
RTL equal to `71b8940` before the cache change). Patch0049's forwarding experiment
remains rejected and archived. This slice changes cache request/address ownership;
it does not redesign the write buffer, translation engine, SDRAM or CPU forwarding.

## Accepted owner and bank address

`arm920_cache_access` captures L0 before the tag RAM or flag snapshot:
`lookup_owner_valid`, `lookup_owner_kind`, `lookup_owner_mva`,
`lookup_owner_segment_select` and `lookup_owner_epoch`. Arbitration is accepted
maintenance, then accepted demand, then idle resident-only lookahead. The existing
`req_valid && req_ready` and maintenance handshake are unchanged. Demand PA,
write data, byte mask, cache attributes and MVA still capture on that same edge.

Only registered L0 MVA drives `bank.mva`. An eight-bit registered one-hot decode
of the same MVA segment feeds existing per-way valid/dirty snapshot reductions.
Tag RAM and victim addressing use L0's binary segment. No metadata arrays or
cache lines are duplicated. The 64-way compare and balanced selection remain.
This cuts the measured abort/writeback/request-qualification→live bank address
(fanout463)→flag-snapshot route, which reached−1.819ns in fit42520603079.

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

The next fit must measure request→L0 capture, L0→tag/flag reads, lookup/token
pipeline and cache→response separately. The existing24 CPU groups remain; four
cache groups make28. Registered one-hot fanout and mux placement still require
routed evidence. CPU forwarding, shifter, cache transfer/maintenance, write-buffer,
SDRAM and peripheral paths remain independent open timing work. No frequency,
clock relationship or timing exception was changed;104MHz closure is not claimed.

Evidence: `scratch/timing-closure/cache-lookup-owner/`, including source snapshots,
phase-reference/current logs, cache-access differential, frozen-source hashes and
final validation summary. Prior checkpoints and rejected experiment evidence are
preserved. Simulation verifies the stated RTL contract, not a physical phone.
