# SPMark Calendar: C: word reads during a deferred erase

## Hardware observation, 2026-11-16

The user runs original SPMark installed on C:, on00fbbea/seed43 (78MHz,
DDR debugger enabled), following a delayed CPU start that booted normally.
The Calendar Test screen stops with its progress bar near the start.
All117 sampled PCs in a30-second capture are503a7368, in original EUser.dll
memory-copy code. The first bus fault is a full-word read at02750fc0 from
503a7340, whose instruction is `LDMDB r1!,{r3-r10}`. Diagnostic reason3 is NOR
response error. ACKs remain123085636 while error count grows418834321→562646821.
Generation stays0. The fetched PC is not a retirement trace; the earlier chat
phrase “exception handler” was imprecise: these sampled addresses are EUser's
copy routine. No user-thread panic category/reason has been captured.

C: reports a deferred, already-polled erase; idle backing state, no outstanding
DDR mutation. Queue254 remains pending, no queue/overflow/C/PMM error. Flash is
not quiescent, so normal background save cannot start. This establishes a real
bus-fault loop, not merely a slow Calendar operation or proof autosave caused it.
The selected erase sector is not exposed by the current snapshot: do not infer
it from the last backing address or claim the fault lies inside/outside it.

A stable read-only local DDR C: snapshot was captured with two identical reads:
SHA256 a6ad30d39bf7d00cfae4366620cf54e62f23334ff8031a313332e24ca14d44e3.
No reboot, live patch, card replacement or save command was issued for this
investigation. Raw observations live under build/diagnostics/calendar-hang-20261116;
screens under build/sim/screens/calendar-hang-20261116.

## Reproduced model error and correction

ngage_cflash rejected every non-halfword read whenever any erase was pending.
The early ordinary-array fast path excluded erase_pending globally, then the
command-width check returned an error before either array/status read handling.
The old controller reproduces independent failures at020000 beside an active
010000 erase, and at010000 for a full-word status read. These are actual NOR
response errors matching the hardware width/state combination, independent of
which selected sector the board currently has.

Read admission now decodes the selected64KiB/top16KiB sector with6-bit and2-bit
equality tests. Other addresses retain normal array byte/word reads. Selected
sector status reads support every CPU byte lane: the existing one-busy-transaction
shortcut returns paired0008 x16 status, then finishes the accepted erase before
returning masked erased data. Halfword busy/completion values are unchanged.
This is a transaction-level extension of the existing synthetic NOR model, not
pin-cycle or physical erase-time verification. Commands/programming remain
halfword-only; autoselect and invalid-width writes retain their rejection.
No new state, counter, RAM, queue, pipeline stage or clock change is introduced.
The short equality decode avoids full-width address comparators for104MHz work.

## Verification and remaining gates

Unit test passes all15 nonempty lane selections, both64KiB/top16KiB geometry,
adjacent top sectors, the same sector in the other bank, unchanged autoselect
width rejection, program data/dirty events, and reset after accepted mutations.
The real CPU/MMU/cache/NOR/D1/D2/DDR-arbiter test adds byte/word reads outside a
deferred erase and the native eight-register descending block read after its
first busy poll. Both buffered and unbuffered cases pass:3087314cycles,
132272competing diagnostic accesses,32backing writes. Existing default remains
3086012/132214/32. All three integrated warm/cold/program/erase reset tests pass.
Production D3 raw-save integration passes with actual three-slot hps_io,
independent C:/PMM flush/reload and mutation overlap:12reads/6writes.

A new FPGA build and native Calendar/JPEG repeats are still required. This is
not a board Calendar pass. Preserve the current unsaved native C: snapshot
through any deliberate recovery; do not substitute an offline repaired image.
The unrelated automatic-start failure remains separate and unresolved.
