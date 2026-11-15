# Memory performance comparison baseline

Recovered from saved main-checkout commit `d751692`; measurements and source
identities below remain historical. The companion testbench/scripts target
that older source generation. Do not treat their results or commands as
qualification of current RTL without a separately validated adaptation.
Current CPU/kernel measurements are in [the payload table](spmark-payload-results.md).


Collected on 2026-11-11 for comparison with the replacement core. The old core's
memory implementation is commit `3f5e8ae`; the collection checkout is master at
`7f55e93982219b8ad5315b785e63be4d4532a756`. The active long-run model is
`6af112481fad51dd`, including the later simulator key-input port. Historical
experiments below retain their own source identities and configurations.

The machine-readable catalogue contains 72 metrics and the nine ROM-buffer
configurations. Each metric records its unit, measurement boundary, profile and
source. The candidate-results list is available for the new core's measurements.
[Catalogue](evidence/memory-performance-baseline-2026-11-11.json).

## Clock and counting conventions

Bring-up runs use a 78 MHz phone clock, 26 MHz timers and NOS 64 Hz. The engineering
target is 104 MHz. One clock is 12.821 ns at 78 MHz or 9.615 ns at 104 MHz. Cycle counts
below come from RTL simulation. A fitted timing report establishes the frequency
at which those cycles can run on the FPGA.

Most cache-unit tables call the acceptance edge 0 and observe registered outputs
immediately after later rising edges. A caller which samples those outputs on
its next rising edge adds one clock. For example, a visible four-clock D-cache
response is sampled on clock 5. Throughput and dependent-load issue spacing are
recorded separately from response latency.

The new isolated TLB fixture presents inputs after a falling edge and counts all
rising edges through settled readiness, including the capture edge. A three-edge
lookup becomes ready two full periods after capture, and a synchronous caller
can sample it on the following edge. Preserve this convention when comparing.

## TLB lookup and page-table walks

Measured on 2026-11-11 using the current production `arm920_tlb` and its 64-entry
bank. The fixture reuses the registered descriptor-bus model from the existing
TLB attributes test. The same module implements both I and D sides.

| Operation | Rising edges through readiness | Descriptor reads |
| --- | ---: | ---: |
| Existing checked 1 KiB permission-token hit |0|0|
| Main-table hit after moving to another 1 KiB permission quarter |3|0|
| Main-table hit after returning to previous quarter |3|0|
| Main-table hit after privilege-context change |3|0|
| Cold section translation |7|1|
| Cold small-page translation |10|2|
| Small-page translation of another missing page |10|2|
| MMU-disabled identity translation |0|0|

A token hit is combinational qualification using previously registered state.
The full CPU/cache access still has its own request and response stages. The
main bank compares all 64 entries in parallel. Its RTL exposes its payload on
the second sampling edge, then the controller publishes permission/translation
on the third. There is no 64-clock sequential scan.

The 7/10-edge walk results include this fixture's registered request/ACK model.
Physical SDRAM table-read latency and I/D arbitration can increase the total.
All bus operations and fault checks passed in the measurement fixture.

[Raw output](evidence/memory-performance-baseline/tlb-latency.log),
[fixture](evidence/memory-performance-baseline/tlb_latency_tb.sv),
[runner](evidence/memory-performance-baseline/run-tlb.sh),
[TLB implementation contract](arm920-tlb.md).

## ARM L1 cache and CPU timing

| Measurement | Baseline value | Context |
| --- | ---: | --- |
| Resident D-cache read, visible response |4 clocks|Directed cache fixture, acceptance edge 0|
| Resident D-cache read, caller sampling |5 clocks|Native CPU/cache fixture, zero external transfers|
| Write-back store hit, visible response |5 clocks|Directed cache fixture|
| Uncached read, visible response |3 clocks|Immediate-bus cache-unit fixture|
| Clean 32-byte miss, visible response |23 clocks|Immediate bus, historical slice 2 cache fixture|
| Warm dependent-load issue-to-issue gap |20 clocks|Historical slice 2 CPU timing fixture|
| Warm dependent ADD interval |1 clock|Repeated cached ALU workload|
| Minimum measured branch gap |14 clocks|Directed timing fixture|

The dependent-load 20 clocks break down into 11 from issue to cache acceptance,
5 to sampled cache response, 1 to owned completion, and 3 to dependent issue.
The preceding implementation measured 19 clocks, with4 for sampled cache service.
Before the completion stage, the documented load-use gap was 18 clocks. These
are separate integration stages with distinct source records.

| Maintenance, visible post-edge completion | Clocks |
| --- | ---: |
| Clean by MVA |12|
| Indexed invalidate |5|
| Invalidate all 512 cache entries |1538|

The unit values above come from the cache-lookup stage comparison. Its source
and boundary definitions should accompany new core results. Later aggregate
firmware-refill measurements appear below. [Cache timing contract](cache-lookup-stage-contract.md),
[operand/completion history](cpu-operand-stage-contract.md).

## Scalar SDRAM route experiment

Measured by `tests/phone/direct_sdram/run-bench.sh` using its native ARM program,
modeled memory waits and instruction/data contention. Each 32-byte fill used
eight independent 32-bit reads in this experiment.

| Accepted request through caller-sampled response | Peripheral route | Direct SDRAM route |
| --- | ---: | ---: |
| Clean 32-byte D-cache miss, median 65 cases |159|143|
| Clean miss minimum / maximum |159 /167|143 /151|
| One dirty-victim miss example |108|90|
| Resident D-cache read |5|5|

The dirty example overlaps writeback and instruction traffic. Only two buffered
write beats complete during its measured interval. The clean example contains
85 instruction-port-active clocks, versus 9 in the dirty example. Accordingly these
rows compare the same program under two routes. They do not establish an
isolated dirty-versus-clean SDRAM penalty.

The source evidence preserves the exact program/fixture hashes and modeled
backend activity. [Direct route experiment](direct-sdram-path.md),
[raw numbers](evidence/performance-subset-2026-11-09.json).

## Full-line refill experiment

Both 50M runs replay the same audited4,700,000,002-cycle source state through
4,750,000,002. The scalar model is `5a5a4f90dd9ece26`; the line model is
`5271ec5bedfe81c5`. Both use the fast phone backing-memory harness.

| Metric over50M clocks | Scalar requests | Full-line transport |
| --- | ---: | ---: |
| Mean instruction refill clocks |137.3713|22.8734|
| I refill occupancy / starts |19,976,258 /145,418|5,097,305 /222,849|
| Mean data refill clocks |136.8379|39.9184|
| D refill occupancy / starts |4,523,315 /33,056|1,514,863 /37,949|
| DDR read commands |722,967|252,294|
| Returned64-bit beats |722,967|981,072|
| Trace micro-op observations |4,119,132|5,824,305|
| Code-stall clocks |36,234,874|28,939,276|
| Data-stall clocks |18,352,378|20,336,174|

Refill means divide coordinator refill-state clocks by refill starts. They
include the sampled workload, contention and target memories. The I/D averages
are therefore not isolated physical DDR/SDRAM latencies. Both endpoints show
zero new faults. Stall flags overlap. Trace counts represent micro-ops.

A32-byte ROM line uses one DDR command carrying four64-bit beats. The fast
harness configures three clocks to its first DDR response and one clock between
following beats. These configured response delays need to be reproduced for
an equal simulated comparison. Board DDR round-trip latency was not measured.
[Line-refill evidence](evidence/line-refill-2026-11-10.json).

## Physical SDRAM controller measurements

The production interfaces cover the same16MiB through two physical8MiB banks.
A32-byte line uses two native BL8 READ commands, each128 bits. Short reads use
one READ followed by burst termination, returning two16-bit halfwords.

| Original Micron-model test | Before short termination | After |
| --- | ---: | ---: |
| Physical halfwords per normal32-bit read |8|2|
| Halfwords across113 ordinary reads |904|226|
| Mixed600-READ workload, clocks |8920|8173|
| Mixed workload, halfwords |4800|3000|

The mixed workload has short/long requests, concurrent physical-bank clients
and refresh. It uses identical stimuli in both arms at 78/104 MHz. The shortened
version reduces workload clocks by 8.37%. Ordinary-read request-to-ACK counts
sum 1456 over 113 reads, mean 12.885 clocks, including adapter/arbitration and
row/refresh effects. The earlier sum is 1447, demonstrating that first-response
latency did not improve along with the bandwidth saving.

One logged104 MHz read has controller BA_ACK107694 ns and BA_RDY107733 ns, roughly
four clocks apart after timestamp rounding. This narrow interval begins after
controller admission. The full CPU access has additional stages.
[Short-read evidence](evidence/sdram-short-reads-2026-11-10.json),
[retained physical-test log](evidence/memory-performance-baseline/sdram-short104.log).

## Uncached ROM instruction fetch

The 64-bit/1 KiB backing ROM buffer is separate from the ARM L1 I-cache.

| Historical stage | Warm loop clocks | Fetch issue / bus service / CPU return |
| --- | ---: | --- |
| DDR-only original |1713|See original trace|
| ROM buffer |1515|6 +7 +2|
| Uncached CPU lookup shortcut |1317|4 +7 +2|
| Resident-hit handshake |1119|4 +5 +2|
| Registered-master bridge |1020|3 +5 +2|

Each loop iteration has79 retirements and 99accepted instruction fetches. Buffered
warm cases make zero external DDR reads. The final fetch chain is 10 clocks, and
99 fetches plus30 control-flow clocks yield1020. The outer ROM-buffer's own resident
lookup changed3→1 clock. A one-clock buffer lookup still traverses the surrounding
CPU/flash handshake. [Fetch measurement details](uncached-fetch.md).

The retained nine-way64/128/256-bit ×1/2/4 KiB matrix predates the later hit/bridge
changes. Every case has1317warm-loop clocks. At50M,64-bit/1 KiB issues1208DDR reads
and 1208 beats;256-bit/4 KiB issues610 reads and 1339 beats. Its cold delay entry improves
147802→143566 clocks. Full nine-case rows are in the catalogue and source table.
[Matrix conditions and results](ddr-rom-cache.md).

## MMU and filesystem integration

These are whole one-byte firmware/kernel scan calls. They include hundreds of
cache accesses and filesystem operations.

| Matched50M scan experiment | Completed reads | Median clocks/read |
| --- | ---: | ---: |
| Old lookup ownership |2626|16165|
| MMU ownership/handshake fix |3748|11430|
|64-entry I/D TLBs |4484|9512|

The first pair begins at 2,000,000,000; the64-entry pair begins at the audited
quiescent2,000,000,027. Corresponding model identities and input hashes are in
the catalogue. The 64-entry run performs1,225,255D and 769,505I main lookups with
33D and 24I actual page-table walks. Source models use78 MHz,26 MHz timers,NOS64,
64-bit/1 KiB ROM buffer and the direct SDRAM route.

Before the ownership fix, resident-translation walk intervals occupy36.21% of
complete-read time in a separate2M sample. This is a historical bug attribution.
A walk's occupied time can overlap other work. [Scan/translation details](mmcstore-scan.md).

## Write-buffer startup and throughput

| Local fixture operation | Before reservation pipeline | After |
| --- | ---: | ---: |
| Acceptance to payload issuable |0|1|
| Sustained reservation interval |1|1|
| Four one-word pushes, first acceptance to last ACK |4|5|
| Eight one-word pushes, first acceptance to last ACK |8|9|

The sink responds immediately in this fixture. CPU store acknowledgements and
store-to-load dependency latency require their own integration measurement.
[Buffer contract and evidence](write-buffer-stage-contract.md).

## Repeating the comparison on the new core

1. Record branch/commit, clock parameters, cache/TLB geometry, backend delays,
   refresh policy, ROM-buffer settings and input hashes for each result.
2. Use matching start/end events. Record response-visible latency, consumer
   sampling latency, acceptance interval and dependent-use spacing separately.
3. Measure TLB token hit, main-table hit, cold section and cold page with the
   same descriptor-bus model. Repeat with the physical controller to expose
   descriptor-fetch transport costs. Include permission/context changes.
4. Repeat scalar hits/misses, dirty eviction, maintenance and a 32-byte streamed
   refill. Keep the program, cacheability, warm-up and I/D contention consistent.
5. For firmware comparisons, prefer matching cold inputs or explicitly audited
   checkpoint imports. Retain full image identities and normal startup behavior.
   Compare instructions/bytes/work completed as well as elapsed clocks.
6. Save new values with the same metric ID plus the new profile. Label
   unavailable matches explicitly. Leave unrelated historical profiles intact.

The isolated old-TLB measurement can be repeated from this checkout with the
existing simulator image. The command writes its executable under build/sim.

```sh
docker run --rm --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
  docs/evidence/memory-performance-baseline/run-tlb.sh
```

Other existing measurement entrypoints are
`tests/phone/direct_sdram/run-bench.sh`,
`tests/phone/line_refill/run.sh`,
`tests/phone/sdram/run-short-reads.sh`, and
`tests/phone/hardware_boot/run-logo.py --line-refill --refill-stats`.
Inspect each runner's tool/runtime requirements. The physical SDRAM tests also
require the local original Micron reference model. Exact firmware replay requires
the profile's saved executable and inputs.

Outstanding comparison gaps are board DDR latency and an isolated physical
SDRAM L1 clean/dirty miss measurement with the latest line transport. The new
core's measurements are pending.
