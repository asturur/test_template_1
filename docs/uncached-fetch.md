# Uncached instruction-fetch latency investigation

Evidence from a separate 78 MHz-timebase cold firmware run with the 1 KiB
instruction-only DDR ROM buffer. The long hardware-service-boot-12b simulator
uses its original frozen executable and is not changed by this work.

The ROM delay at6150..6178 performs eight iterations: each has one increment,
six NOPs, one compare and one conditional branch. Counter initialization and
return add two instructions. Outer63e0..63f0 supplies8, calls that helper,
increments the outer counter, compares and branches. Total79 instructions per
outer iteration, repeated100000 times by the measured caller.

Warm-loop measurement before this change:

| Counter per outer iteration | Value |
| --- | ---: |
| Total clocks | 1515 |
| Retired instructions | 79 |
| Completed instruction fetches | 99 |
| Phone-bus response-wait clocks | 693 |
| CPU code_stall clocks (overlapping) | 1386 |
| Raw backing requests | 99 |
| ROM-cache lookup clocks (overlapping) | 297 |
| Physical DDR reads / backend clocks | 0 / 0 |

A normal sequential sample: CORE_ACK166215 -> BUS_REQ166221 -> BUS_ACK166228
-> CORE_ACK166230. Six clocks precede the next bus request,seven service it,
two return completion. The99 completions cost99*15=1485 clocks, with30 further
control-flow clocks. Extra fetches are observed; do not attribute all20 to a
specific branch/predictor defect without individual cancellation analysis.
No warm DDR misses means wider lines/capacity cannot remove this warm latency.
They may improve other workloads and cold fills; the requested64/128/256-bit
and1/2/4KiB matrix subsequently completed 50M per case; all nine retain
1317-clock warm iterations. See [DDR ROM cache](ddr-rom-cache.md) for the full
comparison and the small cold-start differences.

`arm920_cache_access` previously entered LOOKUP_WAIT then LOOKUP even for
uncached reads. It now goes directly to the registered BYPASS state when the
write buffer is empty, otherwise WAIT_DRAIN. The drain exit also bypasses tag
lookup for uncached reads. Cached reads,writes,maintenance,permission/fault
qualification and bus request registers retain their contracts. Both instruction
and data uncached reads use this common path; tests therefore cover data ordering,
FIQ flash ordering,SWP and precise aborts as well as instruction behavior.

After:1317 clocks,79 retirements,99 fetch completions,693 bus wait clocks,
1188 code_stall clocks,297 ROM lookup clocks,zero DDR reads/backend clocks.
CORE_ACK150664 -> BUS_REQ150668 -> BUS_ACK150675 -> CORE_ACK150677:
4+7+2=13 clocks;99*13+30=1317. Exactly198 clocks removed (2 per fetch).
13.07% fewer clocks than the ROM-buffer-only case;23.12% fewer than the original
1713-clock DDR-only case. The100000-iteration body is projected131.7M cycles;
that projection is not a measured complete logo boot.

The ROM buffer's guard permits miss dispatch after one settled lookup edge;
synchronous tag/data readiness still determines hits. Its measured warm lookup
cost remains3 clocks, so no warm-loop gain is attributed to this guard change.

Evidence: scratch/uncached-fetch/measurement.json and
build/sim/runs/early-boot-uncached-fast-1m/. The independent1M cold run has12
known early fetch errors and zero data faults. Targeted reset/reload,CPU and
real-SDRAM boot checks are recorded in docs/status.md. No hardware build.

Nortido comparison (local reference revision1be08b9): rtl/ngage_flash.sv is a
small array/ID/CFI command-mode FSM; ngage_soc.sv sends its FPGA array reads to
SDRAM. Separately hps/mon/pamap.c maps guest ROM pages read-only to host
PL_ROM_BASE(39000000)+file offset; flash writes are forwarded for handling.
Thus its native ARM execution need not take our soft-CPU/flash/DDR handshake
for every instruction. This is useful architectural context, not a cycle-timing
reference or justification for copying its simplified command semantics.


## Resident hit handshake (2026-11-09)

The 64-bit/1KiB instruction-only backing buffer remains selected. A dedicated
70-clock observation window in one warm iteration resolves the earlier
seven-clock bus wait; the DDR backend is idle throughout this window.

| Observation at a clock edge | Original cycle | Shortened cycle | Meaning |
| --- | ---: | ---: | --- |
| BUS_REQ | 150655 | 137852 | Registered CPU bridge request is visible |
| owner / flash_start | 150656 | 137853 | Memory owner captured; flash accepts request |
| backing acceptance | 150657 | 137854 | Flash has registered mapped backing address; arbiter forwards acceptance |
| lookup | 150658–150660 | 137855 | Synchronous tag/data and matching address become usable |
| raw response | 150661 | 137856 | Registered cache response routed to flash owner |
| BUS_ACK | 150662 | 137857 | Registered flash decode/descramble response is visible |

These are implementation handoffs, not a measured 33MHz flash-device wait.
The bus interval decomposes into one owner clock, one flash launch clock,
three lookup clocks and two response clocks. DDR arbitration is combinational
on request acceptance; it adds no extra idle clock in this sample.

Originally the wrapper first captured the address, only then presented it to
BRAM; the imported cache additionally waited for a previous-cycle hit history.
The wrapper now presents the incoming address to synchronous tag/data RAMs on
the acceptance edge, then holds its captured address through completion.
`HELD_ADDRESS=1` opts into using the captured address/valid/index/tag checks
without the redundant `hit_l` requirement; default streaming behavior retains
that requirement. The wrapper still registers its response. There is no direct
combinational path from raw BRAM data through flash descrambling to the CPU.
An invalid or non-fetch request does not launch this early lookup. Writes still
invalidate instruction lines; data/file reads still bypass the cache.

Verified warm counters: 1119 clocks/79 retirements/99 fetch completions,
495 bus-wait clocks,990 CPU code_stall clocks,99 lookup clocks and zero DDR reads.
The sequential chain is CORE_ACK137859 -> BUS_REQ137863 -> BUS_ACK137868 ->
CORE_ACK137870: 4+5+2=11 clocks, versus 4+7+2=13. Thus 198 clocks removed per
outer iteration,15.03% fewer than1317; the first delay body projects111.9M
cycles instead of131.7M. This is a projection,not a measured complete boot.

The separate run `hit-pipeline-fast-50m` completed its full50M endpoint in
525.22 seconds,retiring3526752instructions. Delay index44561/100000 compares
with37852 in the previous64/1KiB50M baseline. Zero data faults; the12early
fetch-fault records exactly match the instrumented baseline. Both50M checkpoint
files are retained. The first delay is still in progress; no full logo boot is
claimed. Cold startup used1225DDRcommands versus1208 previously,so don't claim
complete bus-sequence identity. The full firstdelay entry moved147802→135417. Inputs are the identical service-loader-derived
firmware and C: snapshot,normal powerup,erased PMM,78MHz phone timebase,modeled
DDR/SDRAM. Baseline detailed trace is `hit-pipeline-before-1m`, which reproduces
1317-clock iterations. Full prior50M baseline is `rom-matrix-64-1024-50m`.
Evidence and comparison script live in `scratch/instruction-hit-latency/`.
All nine cache configurations pass unit tests with one-clock resident hits,
immediate post-accept producer pin changes,tight alternating/conflicting tags,
masked reload,reset at each stage and stale-burst draining. LegacyDDR/arbiter,
flashreset/coldreset/program/erase,memoryowner,codeflash andtopelaboration pass;
source preflight176files/9QIPs passes. `comparison.json` verifies identical
inputs,only the two cache files/testbench changed,no new fetch faults,paired
checkpoints and the unchanged original12B manifest hash. No hardware build or
post-fit timing claim. The added BRAM input-address mux needs future timing
verification. Original12B simulation is untouched.


## CPU issue and return handoffs (2026-11-09)

`cpu-hit-stages-before-1m` traces the full request/completion chain after the
one-clock ROM buffer change. It reproduces1119-clock warm iterations.
A sequential example is:

| Edge | Observation |
| --- | --- |
|137857|Phone BUS_ACK with flash response|
|137858|UPP bridge registered response; merger routes master ACK|
|137859|Cache registered response/CORE_ACK; CPU consumes instruction|
|137860|CPU's next registered address is offered and accepted by cache|
|137861|Owned BYPASS request is offered to I/D merger|
|137862|Merger's registered packet is visible; UPP captures a second copy|
|137863|Phone BUS_REQ becomes visible|

The two return edges isolate peripheral/decode/error selection from the CPU
completion/stall path. Both are retained. The first issue edges preserve the
CPU PC and translated/cache request ownership plus registered I/D arbitration.
The final bridge request capture merely copies the merger's already registered
packet. There is no intervening translation/address-generation/arbitration
logic to justify a second payload register for this particular producer.

Internal CPU UPP therefore selects `REGISTERED_MASTER=1`. Its address,data,
mask,write flag and instruction/data owner come directly from ZAP merger FFs.
The merger remains registered. The board's disjoint memory-owner register,
cache request register and both response registers remain. Downstream request
control uses registered merger CYC/STB plus local bridge state/reset; it never
uses an unregistered CPU next address or live TLB/cache match result.
This removes one empty request stage without merging those long logic cones.
Source register placement/fanout changes;104MHz timing still needs a futurefit.
No timing exception or multicycle constraint was added.

The specialized source contract is explicit: hold the packet until completion;
on the registered-response consumption edge,retire it by withdrawing STB or
replacing it with a new transaction. Simulation asserts field stability while
outstanding. The bridge suppresses requests throughout RESPONSE and preserves
its low-request gap. With that source contract,a held offer through RESPONSE
is not replayed as a duplicate write.
A zero-wait downstream can terminate on the first presented request edge;
{data,error,completion} still cross the response register,with ERR over ACK.
Reset gates request/response and CYC withdrawal cancels an unfinished beat.
Default `REGISTERED_MASTER=0` retains the original capture behavior for generic
masters. No interface is silently changed to assume an unregistered producer.

`upp_bus_bridge/run.sh` tests both modes with200waited read/write/error beats,
exact-once effects,held response data,cancellation/reset. Specialized mode also
checks first-edge ACK,simultaneous ACK/ERR,and continuous source owner handoff.
Flash program/erase/reset/memoryowner,DDR arbitration/cache,sourcegraph andtop
elaboration pass. Actual ARM/board IRQ/FIQ,fault,SIMIF,LCDDMA and SDRAM-wait
fixture passes. Its old peripheral bus_access lint warning also exists in the
instrumented baseline; no new UPP combinational-loop warning appeared.

Separate `cpu-hit-registered-master-50m` completed50000000cycles from reset in
544.604s with the same inputs,64-bit/1KiB and78MHz timebase. Warm trace:
CORE_ACK126707 → BUS_REQ126710 → BUS_ACK126715 → CORE_ACK126717,thus3+5+2 instead
of4+5+2. Measured warm iteration1020clocks,79retirements,99fetches,495buswait,
891code_stall,99lookup,zeroDDRreads. That is8.847% fewer loop clocks than1119.
The100000-iteration body projects102M cycles; its completion is not yet observed.

At50M:3869284retiredinstructions,index48897/100000 versus44561 previously,
zero data faults and exactlythe same12known earlyfetchfault records. NoLCDpixels
yet; no full-logo claim. Entry into firstdelay moved135417→124470. ColdDDRcommands
1231versus1225 reflect changed execution timing; no wholebus-sequenceidentity
claim. Paired50M.cpu/.host retained. `scratch/cpu-fetch-handshake/comparison.json`
checks finalendpoint,nointerruption,inputhashidentity,onlyUPPchangedbetween the
instrumentedbaseline/newrun,allwarmcounters,pairedcheckpoints,ARM/boardPASS and
unchanged12Bmanifesthash. Original12B run continues untouched beyond1Bcycles.

The three remaining issue edges each carry work: CPU nextPC/request admission,
ownedcachebusoffer,registeredI/Dmerger. Two return edges retain peripheral and
CPUcompletion isolation. Further reduction requires a deliberate owned-prefetch
or overlapping-request design,or fit-guided retiming. Do not remove those
registers merely to improve this uncached-loop benchmark. Nohardwarebuild.


Subsequent SDRAM separation: [direct SDRAM path](direct-sdram-path.md) now routes
CPU physicalRAM around the peripheral bridge/sharedowner. The ROM-hit4→3issue/
2return analysis above remains valid for flash and MMIO; its1020-clock loop is
unchanged. RAM uses its own registered controller response followed by cache
completion,without the generic peripheral response-copy register. Nativecache
miss measurements and the distinction between5-clock ARM D-cache hits and the
one-clock1KiBROMbuffer lookup are documented there.
