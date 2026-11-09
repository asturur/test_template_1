# Dedicated CPU SDRAM route

Implementation checkpoint: 2026-11-09. The CPU's SDRAM traffic bypasses the
peripheral bridge. This is FPGA routing inside the modeled UPP, not a claim
about Nokia's internal electrical bus. Clocks remain unchanged: current bring-up
78MHz, intended timing target104MHz. Firmware, caches, ROM buffer64-bit/1KiB,
LCD DMA behavior and SDRAM controller protocol are unchanged.

```text
ARM MMU / I+D caches / page-table walkers
                |
      registered ZAP I/D merger
                |
       physical address selection
          /                  \
  SDRAM0a000000..0affffff      flash / peripheral / invalid address
          |                  |
   existing CPU/LCD arbiter   existing UPP registered-response bridge
          |                  |
   existing SDRAM adapter    existing flash / peripheral ownership and decode
          |
   JTFRAME controller → physical SDRAM
```

The fast route covers all CPU physical RAM requests: cached fills/writebacks,
uncached loads/stores, SWP and page-table reads. A virtual address alone cannot
select it; translation/permissions and cache/write-buffer ordering precede the
registered merger. Cacheable flash misses remain on the flash route. The
merger arbitrates instructions/data/walk traffic as before.

## Registers and ownership

| Stage | Direct SDRAM behavior |
| --- | --- |
| Cache request owner, hazards, dirty/write-buffer ordering | Retained |
| Registered ZAP I/D merger | Retained; supplies the held packet |
| UPP peripheral request/response bridge | Bypassed for RAM |
| Shared board memory_owner | Bypassed; RAM bit explicitly zero in direct mode |
| CPU/LCD grant and accepted packet | Retained |
| SDRAM adapter/controller request and response registers | Retained |
| Cache completion register | Retained |

The simple eight-bit physical range decode drives the existing SDRAM arbiter
admission. `cpu_accept` exposes its existing FREE/choose_cpu grant; it adds no
stage or new arbitration policy. UPP captures one `ram_pending` token on the
same edge that the arbiter captures the packet. No separate address/owner wait
precedes admission. The arbiter owns the accepted payload through completion.

After acceptance, UPP drops its offer and waits for the registered SDRAM
response. That response reaches the CPU cache completion register without
passing through the peripheral response register or shared peripheral ACK/data
selection. The controller's pin-level outputs are not fed directly to the CPU.
RAM is explicitly excluded from the peripheral memory-owner bit and return mux,
so this isolation does not depend on synthesis proving an unreachable address.

A withdrawn, unaccepted request does not issue. An accepted request drains;
CYC withdrawal suppresses its completion, and neither another RAM request nor
a slow request may consume that old response. Reset clears CPU routing ownership;
the existing phone-reset SDRAM discard/drain protocol handles physical work that
has already started. CPU lock remains connected to the existing arbiter across
both SWP halves. DMA remains noncoherent with CPU write-back cache; firmware
cache maintenance is not fabricated.

Diagnostics are observers. Admission drives a single event FF; raw packet
fields are sampled independently and then held through a separate observation
stage. This avoids putting a wide diagnostic clock-enable fanout on the grant
path. RAM diagnostics retain the accepted packet, including its address/data/
lanes/code tag; slow faults retain their own tuple. Diagnostic muxes do not feed
CPU completion or memory admission.

Implementation is in `ngage_cpu_memory_route` within `rtl/ngage_upp.v`, carried
through explicit UPP/board/mister ports. `ngage_mister.DIRECT_SDRAM=1` is the
production default. `DIRECT_SDRAM=0` retains the previous route for A/B and
focused legacy ownership tests. No new imported sources or QIP dependencies.

## Measurement and validation

`tests/phone/direct_sdram/run-bench.sh` runs both modes against identical native
ARM programs, cache configuration and fixed backing-memory waits. It enables
MMU/D-cache and deterministic round-robin replacement, checks65 clean32-byte
misses, a dirty eviction, a warm hit, uncached byte accesses/SWP, and LCD DMA
visibility before/after cleaning. Dirty data must reach the uncached physical
alias. The program is a directed fixture, not a patch to stock phone firmware.

Final corrected measurements with exact current RTL:

| Operation (request-accept edge to sampled response) | Legacy | Direct |
| --- | ---: | ---: |
| Clean32-byte miss, median65 cases |159|143|
| Dirty-victim miss in this program |108|90|
| Serialized resident D-cache read |5|5|

Clean improvement is16clocks (two per32-bit read, eight reads per line). The
dirty result includes buffered writeback and competing instruction requests;
only two writeback beats retire inside that measured interval. It is not an
isolated controller latency or proof that all dirty words drained by response.
The subsequent uncached alias read checks physical visibility. Warm hits stay
inside the CPU/cache path and are unchanged. No line-burst/prefetch change.

The inherited LCD-cache fixture lacked the0x0c1 page-table section containing
DMA/IRQ registers. Its failure used `$finish`, which could still print PASS in
the same simulation timeslot. Corrected mappings and fatal failures are now in
both that fixture and the new benchmark. Historical PASS strings alone are not
coherence evidence. The corrected fixture passes without FAIL messages.

`run-route.sh` verifies range guards, lanes, one admission, unaccepted/accepted
cancellation, draining before another target and reset. Existing bridge modes,
flash reset/owner, SDRAM real-controller refresh/masking/reset, CPU/DMA SWP-lock
arbitration, top elaboration and source graph also apply. Native ARM/board
IRQ/FIQ, precise faults, SIMIF, LCD DMA and SDRAM-wait checks pass.

Final firmware verification completed a fresh50M run in518.566s without
restoring any earlier RTL checkpoint. It retired3869533instructions with
zero datafaults and exactlythe same12known earlyfetchfault records. Delay index
48900/100000 compareswith48897previously; firstdelayentry124470→121266.
ROM warmiteration remains1020clocks,so no sustainedflashloop speedup is claimed.
The paired50Mcheckpoint files and allcurrent compiledsource hashes were checked. Run name `direct-sdram-final2-50m`, source/input/image manifest
and paired terminal checkpoints under `build/sim/runs/`; logs and comparisons
under `scratch/direct-sdram/`. Inputs are the same production-service-loader
exports and C: snapshot used by prior benchmarks, erased PMM and78MHz timebase.
The first50M is mostly a flash-resident delay: it validates early boot but does
not measure sustained cached SDRAM execution or reach the logo. Actual JTFRAME
controller/device-model5M checks at78/104MHz separately cover the physical
memory protocol; they do not establish FPGA placement or104MHz timing closure.

The long `hardware-service-boot-12b` run remains on its frozen executable and
source lineage. For an old frozen restore, use `--use-saved-build` with matching
clock/cache settings and `--legacy-sdram-route` to keep new manifest labels
accurate. Never apply the new route to an old serialized HDL checkpoint.

## Later changes, not implemented here

1. Fold CPU/LCD arbitration's packet capture into the SDRAM adapter's admission
   register only after measuring this route. Keep grant ownership, fairness,
   locked CPU operations, cancellation and reset. A same-bank Jotego read port
   may replace the outer arbitration stage, but not the need to schedule one
   physical memory bus. BA2/BA3 are not aliases of the existing RAM bytes.
2. Measure cache-line transfer overhead separately. The current32-byte refill
   still performs eight32-bit transactions. Do not mix a line-burst redesign
   into the routing change.
3. Separate flash from MMIO before slowing peripheral work. UPP contains the
   ARM and cannot be slowed as a whole. Keep CPU/cache/SDRAM and the ROM buffer
   fast; only a peripheral island may use a slower clock/interface. CEN alone
   does not relax timing analysis: use actual clock-domain handshakes or narrowly
   proven enable-to-enable multicycle paths, never blanket exceptions. Preserve
   IRQ synchronization, exact-once writes, responses, reset and timebases.

104MHz acceptance requires a later fit. Inspect merger→admission (range decode,
CPU/DMA selection), controller response→cache completion, new grant/state
fanout and diagnostic observation stages. No long CPU/TLB/cache-match cone was
joined to peripheral decode; no timing exceptions were added. No hardware build
is authorized as part of this verification.


## Why the remaining miss/hit numbers are high

These are ARM16KiB D-cache measurements,not the separate1KiB instruction-only
DDR ROM buffer. The latter retains a one-clock resident lookup.

The ARM data-cache hit is serialized. Acceptance captures L0 ownership atedge0;
tag RAM/flags read at1,registered tag comparison at2,data RAM read at3,response
visible at4,and caller samples at5. Profiling reports those five sampledclocks:
LOOKUP_CAPTURE,LOOKUP_WAIT,LOOKUP,READ_LINE,then IDLE withresponsevalid. NoSDRAM
operation occurs. Registers protect the104MHz target,but the current controller
does not overlap new demands through them. This is our custom ARM920-shaped
cache wrapped into ZAP,not an unavoidable five-cycle ARM architectural rule.

The miss engine uses eight separately handshaken32-bit requests for each32-byte
line. Dirty replacement also queues victim writes. Each word traverses grant,
SDRAM transaction and completion again; bank/refill/installation states add more
latency. The native fixture still fetches its instructions uncached from flash,
sharing the CPU bus with data. Thus end-to-end miss latency includes unrelated
instruction traffic,not just RAM service.

| Direct-route sample | Total clocks | RAM backend active | Instruction port active |
| --- | ---: | ---: | ---: |
| First clean32-byte miss |143|48|85|
| Dirty-victim32-byte miss |90|60|9|
| Resident serialized hit |5|0|5|

RAM activity includes the modeled memory wait and two victim writes retired
inside the dirty interval; remaining writeback is checked through the subsequent
uncached alias read. Port counters describe activity and may overlap; they are
not chip-command timing measurements. In the90-clock example,30clocks are outside
RAMbackend activity. Different instruction contention explains why this dirty
example is faster than the clean example. Do not generalize dirtymiss=90 or
cleanmiss=143 to every workload or physicalSDRAM.

A substantial redesign should target the customcache/refill and CPU memory
interface first: pipeline hit requests with explicit address/context tokens;
measure both dependent-load latency and independent-hit throughput; overlap
resident lookup with TLB work while preserving permission-qualified completion;
use a whole-line transfer interface instead of eight full external handshakes;
and reduce global CPU load/stall coupling while retaining precise faults and
store ordering. Keep104MHz register stages and use pipelining to overlap work.
A full ZAP replacement is not yet justified by these measurements alone. No such
redesign is implemented or performance target claimed here.
