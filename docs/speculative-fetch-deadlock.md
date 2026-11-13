# Abandoned instruction fetch deadlock

At the reduced run's4B checkpoint, fetch repeats virtual50300B06 / physical
00800B00 and bus errors grow. The CPU already resolved the correct BX return:
writeback shelve=1, pending PC503EF43F. Its old speculative cacheable refill
retries every bus error, holding code_stall forever. The pending return cannot
apply. Cached return instructions match the original firmware; this is not
proof of a corrupted return or bad firmware load.

The instruction cache now receives the CPU's existing registered pending-redirect
flag. A failed refill belonging to that discarded instruction fetch completes
without installing a cache line. Existing instr_valid suppression while shelved
prevents accepting its data; the correct queued redirect proceeds. Explicit CP15
prefetch and the data cache do not use this discard path. Successful fills and
live cached-error retries are unchanged. ARM DDI0151C3.8 does not support an
architectural external abort for ordinary cached reads; this fix adds none.
The control path starts at a registered flag and ends in a registered response.
Quartus timing and hardware behavior still need verification.

The focused tests/cpu/icache_discard regression fails with the old retry policy
and passes with the fix. It verifies repeated live-error retries, completion only
after discard, and a fresh eight-beat read rather than installing failed data.
Cache access, buffered integration and demand-completion tests pass. The full CPU
suite stops after38 PASS lines at fiq_store_return with D1. That same failure is
reproduced with the original retry policy; the complete suite is not passing.

Corrected full HDL recovers an explicitly migrated copy of4B, then runs50M clocks
with only one additional bus error, no data faults and new SharedDataServer /
DosServer processes. The screen remains Nokia: full UI is not yet established.
This is a diagnostic restore, not a cold-boot or physical-board validation.

The migration preserves17844 named fields, initializes the newly observable
I-refill-error flag, and drops six obsolete RAM NBA temporaries. Source snapshots
are preserved. A clean pre-fault1000-cycle continuation matches CPU and host
byte for byte after identical schema conversion. The auditable converter and
hashes are under scratch/startup-fault-audit/. Arbitrary old/new HDL restores
remain prohibited. Standard new observer builds save100M pairs and retain all
billion-cycle checkpoints.

See [evidence](evidence/speculative-fetch-deadlock-2026-11-10.json),
[scan measurements](mmcstore-scan.md), and [status](status.md).

## Fresh integration run: two isolated fetch faults, 2026-11-12

The fresh integration model `8b92e8641d9c7365` logged two instruction-side
bus errors at physical `00800B00`, between LCD events at2,345,217,131 and
2,348,860,125 cycles (recover unsigned32 chronology from signed LCD fields).
Its total bus-error count rose12->14 and stayed14 through the requested4.8B
status. Data errors remain0 and firmware execution continued. This differs
from the old permanent retry storm, but does not alone prove these fetches
were architecturally discarded or establish their exact branch origin.

The frozen model retains the registered shelve/discard path and the
failed-refill no-install completion. No ROM mapping should be invented to
make00800B00 readable merely to suppress the diagnostic.

A separate exact-HDL diagnostic replay is launched from the existing2B pair,
capped at2.349B or10,000 clocks after the first new bus error. It records recent
trace/control history, queued redirect, instruction validity, I-cache refill
error/done/response, CP15 FSR/FAR and post-error instruction trace observations.
It uses the frozen model archive, not current workspace RTL. Zero-cycle restore
smoke passed at2B (12 bus errors,0 data errors, FSR/FAR0). Results are pending;
read `scratch/fetch-00800b00-20261112/{manifest.json,replay.log,result.json}`
when requested. The separate container is `ngage-fetch-00800b00-20261112`.
Its saved first-error pair is forensic: host scanout is intentionally not
advanced. Original checkpoints, firmware, C: and the main run are untouched.
There is no ongoing polling or automatic claim of completion.

### Fresh replay completed: discard recovery confirmed

Exact-model replay captured first error at2,346,633,768. The first failed
refill completes at+2 while no redirect is pending, so the live-read policy
retries. By2,346,633,786 the failed retry coincides with shelve=1 and queued
return503EF43F. At2,346,633,787 the cache emits response/IDLE through discard;
shelve clears next clock. BX trace appears at2,346,633,789; the fetch bus
switches to the correct Thumb address503EF43E at2,346,633,791. No failed line
needs to be mapped to ROM to make progress.

Replay automatically stopped10,000 clocks after the first error with count14,
zero data errors, FSR/FAR0, shelve0 and792 later trace observations. Thus this
occurrence is the previously fixed speculative-fetch case and recovery works;
it is not the current UI blocker. No HDL or firmware change was made. This
bounded simulation result does not prove every speculative/interrupt interaction
or physical hardware. [Measured sequence](evidence/fetch-discard-replay-2026-11-12.json).
