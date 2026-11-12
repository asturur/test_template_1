# Autosave and manual flush investigation

The user promoted both save blockers alongside DDR diagnostics. This was a
bounded, single-chat pass: no new long boot, remote save/reset, CI monitoring,
clock change or access to the other chat's simulations/checkpoints.

## Confirmed bug and fix

A save-sector error in `ngage_raw_save_manager.FLUSH_WAIT` cleared `restored`.
`Template.sv` gates CPU reset with `!save_mounted`, so a failed write-back held
the phone permanently in reset although its restored DDR image was still valid.
Both manual flush and autosave share this path. A focused regression fails on
the old code when requiring the mounted-memory/CPU-release gate to survive a
host timeout. This is a confirmed error-handling bug, **not proof that a timeout
caused the user's particular hardware stop**.

A failed write-back now preserves the resident mount gate, retains the failed
dirty generation, reports sticky per-device Error, clears SAVING/BUSY and stops
further persistence requests. A subsequent manual click does not latch SAVING
or retry an uncertain transfer. The phone may continue reading/writing its
resident DDR image; these later changes have no persistence guarantee after
failure. Cold reload is still needed to reinitialize persistence. No automatic
retry, rollback or successful-save claim was added.

Restore failure, malformed/short reads, unsafe image replacement and internal
queue faults keep their existing boot-blocking policy. An image replacement
after failed persistence still revokes the resident mount gate. Timeouts remain
unchanged:1 second per HPS wait phase in the78 MHz production build. The fix
adds no storage, no CPU pipeline stage and no normal-save transaction cycles.

## Host protocol finding

Read-only inspection of the local Main reference
`/Users/andreabogazzi/develop/zap-frontend/Main_MiSTer/user_io.cpp`, generic
`op == 2` path, shows this order:

1. Fetch the sector from FPGA using UIO_SECTOR_WR.
2. DisableIO, dropping the FPGA SD ACK.
3. Seek/write the image through FileWriteAdv (writable images open O_SYNC).
4. Return to polling and service the next FPGA request.

A slow file write can therefore delay the **next** request's ACK, even though
the preceding FPGA transfer finished normally. Tests previously modeled an
immediately available host after ACK fall. The new actual-hps_io regression
inserts a long post-ACK host delay and checks both manual and automatic saves:
partial host persistence is allowed, resident DDR is retained, the phone release
gate survives the error, and no retry follows it. A late already-selected host
transaction can finish after the FPGA timeout; its sector remains uncertain.
The installed Main binary's exact source identity and real SD latency were not
verified in this pass. This is a source-grounded possible trigger, not a measured
board timeout. Do not simply extend the deadline to conceal it.

ACK fall means Main fetched the data, **not that its file write finished**.
The stock interface supplies no physical-media write-success/durability reply.
The existing Saved indicator cannot promise that final storage write survived
power loss. Main can also encounter a file error after the FPGA ACK has ended.

Donor `ngage2`542300b uses the same request/ACK-high/ACK-low sequence, ordered
first-dirty sectors and re-dirty retention. Its write waits have no deadline;
it avoids this timeout-triggered reset but can remain saving indefinitely if
Main stops serving it. Its100 ms quiet/2 s max age and CS1-only QD policy do not
justify changing our NEM-4 C:+PMM geometry or removing failure reporting.

## Manual SAVING=1: what is and is not established

Manual flush first latches `flush_pending`, then waits for flash quiescence.
SAVING includes that pending request, so it can be1 before any DDR/HPS transfer
starts. A new test holds quiescence low, verifies no unsafe disk/DDR request or
host timeout, then releases it and checks exact saved bytes and a completed drain.
Other normal tests cover re-dirty while active and manual requests during an
automatic batch. These pass; no general manual-drain deadlock was reproduced.

The real user's prolonged wait remains unresolved. It could be before admission,
in DDR snapshot transport, at the HPS request/ACK, or a long/continuously dirty
queue. Partial changed sectors are not proof of drain. This pass does not replace
that uncertainty with a guessed fix.

To distinguish these cases, the existing DDR snapshot's reserved DWORD242 now
contains a passive packed save-state word;243 contains current file LBA. No new
registers, counters or RAM were added for this observation. The SSH reader emits
`save_progress` with named flags. Format is documented in `ddr-diagnostics.md`.
With a new RBF, capture DDR JSONL before and during one save action. Check the
manager state, pending/quiescent, DDR request/ready/done, HPS request/ACK, slot,
LBA, queue flags and per-device error. Quarter-second observations may miss
short phases but should show a sustained wait. Exact queue depth, completed
sector count and a latched timeout-phase reason are not implemented.

## Checks

* Existing baseline actual-HPS ordered autosave/manual suite and D1+D2(8 KiB)+D3
  real NOR/arbiters/HPS suite pass.
* The new host-timeout CPU-release assertion fails on the old manager.
* Patched ordered and scalar HPS suites pass, including delayed Main write-back,
  sticky slot error, retained DDR, manual/automatic error isolation and no retry.
* Production D1+D2+D3 NOR program/erase, immutable firmware, concurrent mutation,
  independent C:/PMM reload and diagnostic-slot isolation pass after the fix.
* Manual pending/quiescence drain and unchanged sector timeout/stuck-ACK tests pass.
* Extended DDR save-progress payload/reader tests pass with physical DDR adapter,
  Intel BRAM and collision-poison RAM. Production top structural elaboration,
  source graph and formatting pass. No fitted timing/area claim.

The auto/late-host fixture uses scalar modeled DDR; the separate production
D1+D2+D3 NOR fixture covers manual save and concurrent mutation. Continuous CPU
line-refill traffic combined with autosave is not newly qualified here.

Remaining board gate: load the new RBF and capture a normal and failing save with
DDR diagnostics. Saving successfully on the actual SD card remains unverified.
