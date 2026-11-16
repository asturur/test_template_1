# Native installation flash stall — 2026-11-16

SPMark's original SIS reaches **Installation complete** on C: with RBF6f3baa2
(run43785027340, seed43, debugger on, actual78MHz). The private DDR C: directory
contains all11 app payload entries, its help and installation records. This is
not a byte-for-byte payload verification or a successful persistent installation.

After completion the phone stops responding. Across a fresh10s capture its
fetch and bus-ACK counters stay at1028515054/1534042791, while cycle/snapshot
counters advance. Last fetched instruction is50384d5c `LDR r1,[r4,#8]`, just after
`STRH #0xb0` in the original flash erase-suspend routine. This is a fetched
context, not a precise retired-PC or proof of the faulting operation.

The save manager is idle with217 sectors pending and `flash_quiescent=false`.
Queue, C:/PMM error and CPU first-fault/panic flags remain clear. Fresh stable
DDR/file comparisons disagree for C:; PMM agrees. Reboot was withheld to retain
the stopped state. This establishes a real stalled phone/unsaved image, not
that autosave caused the stall. The underlying flash/cache/router cause is open.

Read-only native filesystem directory listing succeeds on a private C: copy.
Every file open returns-26, also after a private open-mode0 control. No source,
card or live phone bytes were changed by these controls. Do not infer a corrupt
card, payload byte correctness or a native JPEG result from this reader failure.

The next CPU build43797500563 contains block-transfer patch0070, but no additional
wait-state visibility. Its40-minute check is due at03:59:33UTC. A separate
minimal passive diagnostic extension fills existing reserved DDR words245..251:
router state/ownership/handshakes, C: controller state/backing address, code-NOR
state/backing address and the requested line address. It adds no controller
state, queue, counter, snapshot memory or transaction. Debugger-off production
leaves these wires unused. No functional memory change is justified yet.

Qualification: snapshot/text writer with scalar/physical DDR and collision-poison
RAM, reader marker/legacy/torn-record controls, disabled-debugger loader and
integrated flash reset/program/erase/drain tests pass. Hardware gate pending.

[Exact observations and limits](evidence/installation-flash-stall-20261116.json).

## Confirmed circular wait and correction

A new actual-CPU Verilator reproducer confirms a transaction-level deadlock.
After an accepted30 erase command, the C: controller is IDLE with erase_pending
set. The command model advances only on a later status poll or B0 suspend.
`user_idle` intentionally includes !erase_pending for reset-drain correctness.
The refill router also used this stronger predicate, blocking unrelated RAM/ROM
lines. A cold instruction or struct-data load then prevents the CPU from issuing
the progress command. The board stopping fetch50384d60 is itself32-byte aligned,
consistent with the same blocked next-line fetch; hardware proof is still pending.

Refill admission now uses `user_ready` (backing interface IDLE, reset inactive),
while reset release still uses the unchanged stronger `user_idle`. An actively
executing NOR backing operation still prevents a fresh line admission. Existing
DDR ownership/arbitration serializes a subsequently accepted command and ROM
line; no new physical NOR bank/timing behavior is claimed. The functional change
removes one erase-pending condition, adds no storage/stage and retains78MHz with
104MHz as timing objective.

The maintained regression runs8 complete64KiB erases through the actual CPU,
MMU/cache, C: NOR/router, D1/D2 and DDR arbiter: four suspend/four polling paths,
four buffered/four unbuffered mappings, cold I/D refills and native status/data
checks. Production passes in3,086,012clocks with132,214 competing diagnostic reads
and32 physical backing writes. Its generated old-gate control must fail with
DEFERRED_ERASE_REFILL_DEADLOCK, not a generic timeout; it does. Existing warm/cold
reset, accepted program/erase drain and stale-response collision tests pass.
An earlier frozen pre-fix real-CPU test also remained blocked through8Mclocks.

This fixes the reproduced hardware-flow bug. It is not yet a board installation,
autosave durability or native JPEG pass. The standalone forced-port prototype
hit the same admission wait, but the real-CPU regression is the maintained
acceptance evidence. No firmware/RAM patch or slower fallback was introduced.
[Regression](../tests/phone/flash_refill_suspend/README.md).

## Payload verification and native-state recovery

A separate writable **private copy** resolves the reader's-26 failures. Original
file-server code makes5 C: writes, then all95 file opens succeed. All12 SPMark
payloads match the original SIS sizes/SHA256, including TEST.JPG, SPMark.app,
3dtest.dll and libGLES_CM.dll. This establishes complete installed payloads in
the captured resident image. The source snapshot remains74c37648…ed8f817; the
private emulator result44ec5479…5ca7c is analysis-only and must not be deployed.

When the fix build43800659356 is ready, recover the exact native4MiB C: snapshot
to boot0.vhd only after unloading the stalled core and verifying Main has closed
the image. Verify hashes and sync before starting the new RBF. PMM already
matches its file. This salvages native installer writes the stalled old core
could not flush; it is not a firmware patch or an offline filesystem repair.
Then validate actual native housekeeping, UI progress and queued save drain on
the new HDL before reporting successful persistence or JPEG completion.

The private filesystem changes all128 sectors at C: offset40000..4ffff and one
sector at2d0a00. Its garbage-collection erase is therefore exactly the sector
address seen in the stopped phone's last bus record02440000. This independently
connects the native file-server housekeeping to the reproduced erase/refill wait;
it still does not replace hardware verification of the new HDL.

The superseded CPU-only build43797500563 passes all constrained timing checks:
setup+0.197ns, hold+0.174ns, recovery+2.379ns, removal+0.878ns, pulse+0.641ns.
38,809/41,910ALMs(93%),45,220registers,503M10Ks,42DSPs; all16SDRAM DQ pin input/
output/OE registers pack. Artifacts/build-info exact commitcd858fd/seed43/debugOn
verified. It was not deployed because its NOR admission still contains the bug.

Additional changed-boundary test: `--reset-overlap` cancels an accepted cold RAM
line while the erase command is deferred. The accepted mutation drains before
CPU restart, which then completes the eight-erase test in3,470,671clocks with
148,660diagnostic reads/36backing writes. No stale line response or data failure.

Concurrent sector case: `--bulk-competition` replaces diagnostic scalar reads
with backpressured64beat C: snapshots through the production D3 DDR adapter.
All4,084 snapshots check every data beat/last flag against independent backing
bytes; CPU completes8 erases in1,049,519clocks/32writes. This covers DDR-side
snapshot arbitration, not HPS file writes or ordered dirty-queue persistence.
