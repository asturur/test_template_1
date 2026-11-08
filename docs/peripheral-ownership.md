# Peripheral ownership and local RAM commands

This records the behavioral UPP model, not verified Nokia pin-level hardware.
All decoding uses the existing captured UPP bus in internal-CPU mode. Child
response priority, configuration, snooped effects and LCD DMA exclusion remain
in their existing modules. No new clock or timing exception is introduced.

## Regional RAM ownership

| Storage window | Local exclusions | Preserved behavior |
| --- | --- | --- |
| `0c03xxxx` upload | None | Keypad configuration gates access; legal GPIO byte lanes |
| `0c10xxxx` NOS/shared | MDI claim | MDI owns `01f4`, `01f8`, `03e8`, `03ec` |
| `0c150xxx` GPIO/SIM | SIMIF, NOS, GPIO loopback claims | Original `000..5ff` and `800..8ff` windows; `420/424` excluded in range decode for CBUS |
| `0c06ffxx` auxiliary upload | None | Existing auxiliary index, independent of upload/NOS/GPIO storage |
| `0c14xxxx` auxiliary windows | MDI claim | Existing `f0xx`, and first32 bytes of `2/8/a/b/c` pages; MDI at `b004` |
| `0c12xxxx` auxiliary windows | Boot claim | ICU-adjacent `0c00..0c1f`; `0034` remains a boot latch |
| `0c004xxx` NOS4K | Boot scratch claim | 45 latches at `4748..47f8`; remaining words use BRAM, including `47fc` |
| `0c000xxx` ASIC stub | Read-only | Existing `47704770` return; writes fault |
| `0dxxxxxx` sparse | Trace claim | Trace pages never allocate sparse entries |

ICU, timers, extra ICU/config registers and trace sinks do not overlap the
regional RAM windows above. Their claims therefore do not qualify RAM writes.
Upload RAM's write enable is now solely clearing or
`local_access && we && valid_lanes && cfg_keypad && upload_hit`; no boot/scratch
claim or aggregate GPIO selection feeds it. Each other RAM receives its own
regional qualifier. Aggregate GPIO selection is used only for the keypad
access overlay, not fed back into those write enables.

Dedicated read-response priority is unchanged. SIMIF's unclaimed GPIO injection
snoop at `0c150008` still observes the write while GPIO stores it. SIMIF claim
at `0c150800` and `0c1500b8` still depends on operation/lanes. Keypad read overlays
and GPIO quirks are unchanged. NOS4K retains its original unrestricted byte masks;
GPIO RAM retains its existing accepted lane combinations. Warm reset preserves
RAM, cold initialization clears it. BRAM reads retain their one-edge readiness;
this change adds no stage and does not alter acknowledgement/error decisions.

`tests/phone/regional_ownership/run.sh` compares regional selection with the
previous global exclusion using actual connected child claims across all words
in eight relevant64KiB windows, then checks operation/lane/config combinations
at the real overlaps. Board/SIM/DMA tests exercise the effects and overlays.

## Sparse-register transaction pipeline

The sparse model remains a temporary behavioral CAM with full32-bit addresses,
64 default entries and a byte-enabled payload BRAM. Supported tested capacities
are1,2,3,5,64. Lowest-index matching/allocation is unchanged; padding leaves never
match or allocate. A write hit succeeds when full. A write miss when full faults
and changes nothing. A read miss returns zero. New allocations zero unselected
bytes, including the existing zero-mask allocation behavior; hits merge only
selected bytes. Parent read masks are unchanged.

| Stage | Registered work / externally visible behavior |
| --- | --- |
| IDLE → COMPARE | Capture selected address, write/read, payload and lanes |
| COMPARE → SELECT | Register parallel matches and available slots |
| SELECT → READ | Register chosen slot, hit and overflow result |
| READ → RESULT | Payload BRAM samples the registered slot; ready becomes true |
| RESULT → DONE | On commit, publish tag/valid/payload together and retain the terminal result |

With stable fields from idle, ready appears after four rising edges; a write
commits on the following edge when commit is high. The previous write was
immediate and read took one edge. Only selected non-trace0d transactions wait.
Other RAM read readiness, dedicated devices, LCD/DMA and SIM overlays retain
their original contracts. Full/error is qualified by ready, so diagnostic and
CPU fault response describe the same captured failing request.

**Lookup is independent of commit.** External testbenches may wait for ready
before granting authorization; the internal CPU may hold authorization throughout
the lookup. RESULT waits as long as necessary without changing storage. Each
accepted write occurs once. DONE keeps ready/data/error stable for an identical
held request and never restarts it, even if commit toggles. Read-result data is
held across a same-slot write, avoiding dependence on mixed-port collision output.

Request withdrawal cancels unfinished work. A changed address, operation, lane
mask or write payload invalidates the old result immediately and restarts lookup
through an idle bubble. Identical consecutive transactions require a sampled
request-low gap. Warm reset cancels pending work while retaining entries and
payload. Cold reset clears validity. A request held across either reset is
quarantined until withdrawal or changed identity, preventing a canceled write
from silently restarting. Reset at an already committed transaction preserves
that transaction on warm reset; cold reset invalidates it.

The only production instance is `ngage_upp_peripherals.d_regs`. Trace claims
exclude its req, readiness and full error altogether, including malformed trace
accesses. The UPP's captured bus boundary and CPU abort suppression are unchanged.
Registered tag/payload values are independent of live response logic. Mutation
requires its registered result and local ready/commit handshake; the existing
UPP bus-access error suppression remains intact.

Tests retain full-address, masks, capacity and low-slot scoreboarding while
using explicit ready handshakes. They add sustained authorization, withheld
commit, stable held results, exact write counts, immediate dependent reads,
replacement/cancellation at each occupied stage, warm retention and cold reset.
The board adapter additionally checks that a canceled sparse request cannot
stall upload RAM, and full CAM state cannot affect trace-sink timing/errors.

## LCD board-command pipeline (2026-11-08)

When LCD_ENABLE is set, validated UPP packets enter a one-entry board stage.
DMA valid/address/data/full-frame cross the same edge, preserving original
CPU/DMA order and allowing a header and DMA pixel from the same source edge.
Input-side direct-data/DMA collision suppression is unchanged. The live sink
consumes every clock, so normal throughput remains one accepted command per
clock; a synthetic consumer hold tests the local ready contract. Only an LCD
write would wait if that sink were held. Reads retain transport readback timing.
DMA completion to ICU is delayed one clock to match pixel publication. Display-
disabled fixtures keep the prior immediate transport/IRQ contract. Reset drops
pending CPU/DMA records while resetting panel/transport state together.

The initial712c811 CPU-only hold behind raw DMA could reorder streams and is
superseded. `tests/phone/lcd_queue/run.sh` tests consumer backpressure, local
validation/reset, and differential panel state/pixels against the unqueued
stream. This is transaction-level verification, not physical panel timing.

## Registered local responses and ICU latch RAM (2026-11-08)

Internal-CPU mode now snapshots the separate local data/error cones and one-hot
priority owner at the accepted local-access edge. The CPU return combines these
registered values with a masked OR, rather than placing the complete live
SIM/boot/timer/GPIO/keypad priority mux before the bridge response register.
Only the GPIO/NOS/loopback family traverses the keypad overlay. The existing
UPP request register retains address, operation, lanes and payload until the
response terminates; ownership is retained even if the device's live claim
changes after acceptance. Diagnostics keep unconditional payload sampling;
the existing delayed event qualifiers select completed responses and matching
faults with the still-held request context.

This adds **one clock** to internal-CPU peripheral response latency, on top of
each device's existing ready delay. Device effects occur at the local response
capture edge. A response-pending bit suppresses subsequent authorization,
including CBUS/MDI outside the UPP peripheral module; held responses cannot
repeat read pops, W1C or trace writes. ACK/error does not become a device write
enable. Cancellation before acceptance drops the request; reset discards the
response. Accepted effects are not rolled back. The classic bridge supplies a
request-low gap between beats. External standalone board fixtures retain their
immediate response contract; the differential fixture explicitly enables the
registered path on its second instance. LOCK bypass and the queued LCD CPU/DMA
streams and delayed completion IRQ are unchanged.

ICU-extra's low48, DMA64 and epbus64 programming words now use three explicit
32-bit `ngage_bram` instances (the low bank pads to64 physical words). Small
probe latches and sysc74_seen remain registers. Every reset restarts a parallel
64-edge zero scrub **after reset releases**. Only selected ICU-extra accesses
wait for scrub; global cold init_done still comes from the existing regional RAM
sweep and does not depend on this scrub. Therefore holding core reset until
cold init_done cannot deadlock. Warm reset also zeros every programming latch.
Valid bank reads require a previously sampled matching address; writes clear
read_valid, so an immediate same-address write→read cannot expose the undefined
mixed-port collision result. Whole-word bank restrictions, excluded low-bank
control addresses, probe byte masks and unsupported DMA-start faults remain.
The LCD DMA shadow exclusion now qualifies only extra_regs.commit; the direct
LCD/DMA collision qualifies only LCD acceptance/readiness.

Focused evidence is under `scratch/timing-closure/pass14-peripheral-response/`.
The new registered-versus-immediate fixture covers33 transactions with withheld
authorization and held responses, masks, faults, GPIO/keypad overlays, SIM read
side effects, trace exact-once behavior, sparse lookup, changing live ownership,
and warm reset. ICU tests exercise every accessible bank word, immediate
same-address write/read,80 clocks held in reset and autonomous scrub completion.
Actual HDL CPU board SIM/DMA/LCD/fault/IRQ/FIQ/waited-SDRAM integration passes.
Regional sweep, SIM present/absent, LCD mixed-stream419checks, board wrapper,
132-address inventory, C++ fixtures, monitor/raster, bridge200beats, reset gate,
source graph and formatter pass. Final combined CPU regression passes120 checks
plus1 expected legacy XFAIL. Fresh5M real-SDRAM boot passes with zero data faults;
all121 ordered writes and12 known fetch-fault records match the baseline, with
expected changed timestamps/read repetitions. Evidence and exact stopping point
are in status.md and `scratch/timing-closure/pass14-combined/`. No old checkpoint
was restored.
No fitted timing/resource improvement or physical-phone validation is claimed.

Known baseline failures found during this check: the keypad board test cannot
clear keypad pending at0c150100 after the earlier regional-owner change excluded
NOS from gpio_access (got00201004, expected00001000). The same failure reproduces
with pristine6f34b89 UPP/peripherals/ICU sources copied under the evidence
folder's `baseline/`; it is unchanged here. The obsolete diagnostic runner
PASS prefix was corrected during integration with the readout change.

## External NOR/SDRAM owner (2026-11-08)

The MiSTer phone boundary captures the existing ROM-map's four nonoverlapping
regions (PMM,C:,code NOR,SDRAM) once per held UPP bridge request. Captured memory
ownership selects launch, read data and completion without the global peripheral
claim priority. Address/data/lanes remain the bridge's held transaction record.
The owner clears on reset or a request-low gap. This adds one capture clock to
memory accesses and changes no map ranges, command semantics, masks or SWP lock.
Peripheral windows retain their state-dependent local owners. A request outside
both the memory regions and all selected peripherals raises a decode fault.

`tests/phone/memory_owner/run.sh` checks14 region endpoints, an unknown address,
held requests/returns and request gaps. It deliberately poisons unrelated live
peripheral claims after capture to verify independence. NOR ready/return records
are isolated in that fixture; the reused flash reset suite verifies real accepted
DDR responses, code/C:/PMM drain, programming, erase and dirty tracking. Actual
CPU-board and real-SDRAM boot evidence is recorded in status.md.
