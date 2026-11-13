# Runtime save-queue fault holds the CPU in reset

The installed4dc6396/seed43 RBF passes the previous early RAM-fault region, then
stops because a dirty-queue integrity fault revokes the restored-media gate.
The HDL correction keeps completed DDR restores available while persistence
fails with an error. The trigger inside the FPGA queue remains unresolved.
This is a tested reset-containment fix, not a successful phone boot or save.

## Exact build and board evidence

Run [43404825368](https://github.com/asturur/test_template_1/actions/runs/43404825368)
produced the installed RBF, SHA256
`de59b53f5712e9ea2a459a30668b8eae93d74bbddc7566341a4ebdc1472ffdb7`.
ROM and C:/PMM hashes match the original firmware and restored known-good pair.
No firmware/RAM patch, overlay, PMM injection or media write was applied.
Background save was Off. The second boot was explicitly started without Flush;
it repeats the first failure, excluding the earlier uncertain OSD navigation
as a necessary trigger. User has now saved CPU Run for subsequent reloads.

The completed fitter report confirms all16 SDRAM DQ input, output-data and
output-enable registers pack in I/O cells. Core setup/hold are +0.360/+0.250ns;
HDMI +0.523/+0.205ns. All reported timing-summary checks have positive slack
and zero TNS. Fit needs37,179/41,910 ALMs,43,376 registers and506/553 M10Ks.
These results do not establish104MHz closure or close external-I/O constraint
gaps. No CI monitoring was performed; completed artifacts were inspected.

Two original-ROM boots have no sticky data fault and reach kernel text
`TRtcQueue::Add: 2`. Both then enter the same failure:

| Boot | Frozen CPU cycles | Last recorded PC | Last address / data |
| --- | ---: | --- | --- |
|1, earlier uncertain OSD navigation|1,107,763,540|5167EC1E|007F0000 / F0F0F0F0|
|2, clean Run without Flush|1,107,768,713|5167EC1E|007F0000 / F0F0F0F0|

Live fetch PC becomes0, cycles stop, reset generation increases1->2. The save
manager is Failed, mounted=false, tracker_fault/error/pending=true, both slots
report Error, and no host or DDR save request remains active. Panic valid mask
and first sticky data-fault fields are zero. Twelve historical instruction
probe errors are distinct from a recorded data abort. CPU cycles correspond
to about14.2s of unheld78MHz operation; this is not elapsed wall boot time.
The previous UART drain point has not yet been qualified on this RBF.

## Confirmed policy bug and correction

`ngage_raw_save_manager` previously cleared both `restored` bits on
`tracker_fault`. `mounted` is their AND, and Template includes `!save_mounted`
in CPU reset. A queue problem thus reset an otherwise resident phone even
with automatic saving disabled. This dependency is visible directly in RTL
and reproduced by the actual three-slot HPS integration test.

Keep completed restores on that error path, matching existing write-back
failure behavior. The manager still enters Failed, clears Saved/SAVING/BUSY,
reports both slot errors, cancels bulk work and issues no new save requests.
Later guest writes can remain in DDR, with no persistence guarantee. A new
Flush or enabling autosave cannot retry. Cold reload is required to recover
persistence. Incomplete restores remain unreleased; simultaneous or later
unsafe media replacement still revokes CPU release.

No data path, PLL, queue capacity or normal save transaction was changed.
The containment adds no registers. The observation below adds two sticky
cause bits, no RAM, duplicate counter or CPU/bus cycle. Fitted cost/timing of
this change still requires a new build;104MHz remains the design objective.

## Queue trigger still unproven

The queue can fault for an invalid sector mark or overflow. Existing telemetry
cannot distinguish them. Its pending flag is already true before the first
CPU instruction, which deserves examination but does not prove corruption.
C: marks are bounded0..8191; PMM marks8192..8319 by their source expressions.
No arbitrary sector filter or unordered fallback was added.

Production-depth simulation initializes all8,320 metadata entries, queues all
8,320 unique sectors with saving disabled, coalesces44,960 repeated marks and
drains in order without fault. Both behavioral BRAM and the existing Intel
altsyncram model pass. This does not reproduce or clear the FPGA-only problem.

DDR snapshot word244 now carries the existing queue count/status plus first
sticky overflow/invalid-sector cause. It has marker0x51, so old snapshots
remain readable and old readers ignore the extension. See
[the format](ddr-diagnostics.md#save-progress-extension). Snapshot version,
addresses, seals and record sizes are unchanged. Next board capture must
check initial count and the first failure cause before selecting another fix.
No boot patch or manual Hold preparation is needed; saved Run is suitable.

## Verification and next gate

- An isolated copy restoring the old unconditional reset behavior fails the
  new integration assertion: queue fault resets the restored phone.
- Ordered actual HPS:38 checks/64 reads/20 writes; injected invalid sector keeps
  DDR and CPU release, reports sticky errors, rejects retries and replacement.
  Existing manual/auto timeout and mutation coverage remains passing.
- Legacy actual HPS:31 checks/49 reads/12 writes.
- Queue:606 randomized offers, generations, wrap, batches, full capacity,
  failed ACK and explicit overflow cause; production-depth behavioral/Intel
  tests pass. Invalid-sector cause/count are checked through actual HPS.
- DDR:1024/8-record rings, physical transport, loader ownership, poison/Intel
  RAM, emitted extension decode and old zero-extension snapshots pass.
- Production top elaboration and Quartus source graph pass. No long simulation
  or other thread's simulation/checkpoints were touched.

Next: build/install this change, capture automatic original-ROM boot, confirm
the CPU remains released after any save fault, and inspect the queue cause/count.
Full Symbian boot, native D550/SIM readiness and working persistence remain gates.

Compact identities and samples: [evidence](evidence/save-queue-fault-2026-11-13.json).
Raw captures/reports and reproducers stay under
`scratch/board-debug-4dc6396-20261113/` and
`scratch/save-queue-fault-20261113/`.
