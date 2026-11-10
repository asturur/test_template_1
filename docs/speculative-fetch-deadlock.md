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
