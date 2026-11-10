# Ordered C: and PMM saving

The D3 bulk persistence configuration also selects the S3 dirty queue. In
that build, **Background save** starts Off. Turning it On allows a pass after
one second without a committed dirty event or five seconds with work pending.
Both raw images must be mounted, the firmware bundle must be verified, and
the flash path must be quiescent. A pending warm reset or overlay operation
holds off new automatic passes.

A pass saves up to 16 sectors. A warm reset can run between passes. The
existing manual Save action drains both devices, including new generations
queued during the save. A manual request received during an automatic pass
stays pending until that pass finishes. The timers make work eligible to save
and depend on the storage path being ready to service it.

## Ordering and failures

Each committed DDR dirty event identifies a 512-byte sector. One FIFO keeps
the first outstanding dirty order across C: and PMM. A second mark to a waiting
sector coalesces into its existing entry. A mark after dequeue queues a new
generation at the tail, including a mark during the snapshot or host transfer.
The snapshot captures the sector contents when the DDR sector grant is held.
Coalescing can include later writes in an earlier snapshot, so an interrupted
image can differ from an exact prefix of the guest's flash writes.

The FIFO holds all 8,320 sectors plus one separately held active entry. Two
one-bit RAMs track enqueue and dequeue generations for each sector, with
forwarding for simultaneous updates. The arrays contain 141,440 logical bits
before memory block rounding. Cold reset initializes the generation RAMs.

A failed transfer stops saving and retains the active generation. An unsafe
media replacement or invalid queue event also stops the save path. Pending
DDR contents stay resident until a cold reset. Queue faults never switch to
unordered scanning. Slot 3 diagnostic exports carry C: and PMM error bits in
the optional save extension. `tools/ngage_diagnostics.py` decodes them as
`save_errors`; older captures report `null` for the extension.

## Verification

The queue tests cover 606 offers against a randomized order reference, full
capacity, pointer wrap, overflow, re-dirty while active and failed ACK
retention. The real `hps_io` simulation checks both the scalar baseline and
ordered saving, including quiet and max-age scheduling, reset between passes,
manual save and per-device errors. The bulk NOR and full-size tests check
C:/PMM reload through the ordered path. The diagnostic integration test checks
the decoded PMM error through the slot 3 disk export.

Controlled interruption and remount with the original firmware filesystem,
installed MiSTer Main durability, and fitted FPGA resource and timing checks
remain open. Test inputs and results are recorded in
[`background-save-2026-11-11.json`](evidence/background-save-2026-11-11.json).
