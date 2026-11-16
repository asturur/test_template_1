# Boot abort observer

Prepare with `python3 tools/prepare_boot_abort_observer.py --out build/diagnostics/UNIQUE`.
Default mode logs only low-vector terminal aborts; high-address native handoffs
remain transparent. `--first-abort` deliberately breaks on the first abort,
including normally recoverable faults. It is an observation breakpoint, not a
native boot or production firmware replacement.

The generated remote script is read-only unless `--apply` is explicit. Applying
requires exact stock ROM, all expected old words, fresh physical Hold with saved
Run Off/save Off, advancing snapshots, no execution history and completed media
restore. It verifies every written word and the full resulting image, rolls back
on failure, and is removed by reload. Do not bypass these gates.

Run `python3 tests/tools/boot_abort_observer/check.py OUTPUT_DIRECTORY` to check
192 Unicorn cases: modes, MMU state, LR, flags, SPSR, SP/LR preservation, normal
handoffs or intentional first-fault breaks and exact three diagnostic writes.
Unicorn on this Mac requires executable-memory permissions. The code occupies
96 verified-zero bytes outside the firmware checksum range; no stack or block
transfer is used. Successful testing does not authorize applying it to a warm
phone. See docs/block-transfer-sequencing.md for the fault it identified and
proof that the original image was restored.
