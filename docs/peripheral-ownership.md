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
