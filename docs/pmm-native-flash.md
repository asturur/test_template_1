# Native PMM flash commands — 2026-11-13

## Implemented defect

The production code-flash controller rejected commands used by the unchanged
NOS flash drivers. Intel erase starts with20/D0 and selects status with70.
AMD erase uses AA/55/80, AA/55/30; the AMD programmer ends with20. Before this
change, the actual Intel routine fails on its first20, and a separate actual
AMD program-only control fails on its final20 after programming the data.
These are reproducible controller errors, not inferred from a pending IPC.

`ngage_codeflash.sv` now accepts these command sequences. Only the writable
64KiB PMM window can be erased, one of its four16KiB sectors at a time. Intel
confirmation must address the selected sector. Firmware and adjacent sectors
are preserved. The original AMD program tail is consumed without leaving a
false erase pending. Program data still obeys NOR1->0 semantics.

Erase reuses the existing DDR write path:4096 full-word writes, with one dirty
event after each completed512-byte sector. An accepted operation drains across
phone reset; unconfirmed setup cancels. The confirmation response is held until
backing writes finish. This is a documented transaction-level shortcut, not a
claim of physical busy/suspend timing. Suspend/resume paths remain unmodeled.

## Original-firmware verification

The CPU fixture copies8192 unchanged bytes at NOS5167E000..5167FFFF. It checks
both the retained native DLL SHA and every byte against the decoded original
service containers, backing SHA88fd596a... and physical offset27E000. No driver
helper stubs, firmware edits or invented successful replies are used. The
fixture supplies chip0 base0 and delay calibration104 in otherwise zeroed RAM.

| Native function | Entry | Exercised operation |
| --- | --- | --- |
| Intel erase |5167EF28|20/D0, original status poll and array restoration|
| Status poll |5167F020|ready/error interpretation and FF restoration|
| AMD erase |5167F1C4|original setup, delay routine, erase and verification|
| AMD program |5167F094|one halfword, native polling and trailing20|

`sh tests/phone/native_pmm_erase/run.sh` passes on actual ZAP and production
controller at memory waits0/3:58,983/105,167 clocks. Both16KiB sectors erase,
the subsequent halfword programs correctly, neighboring contents remain intact,
64 erase dirty events plus one program event occur, and no command stays busy.
These are cycle counts, not FPGA timing closure or a full phone boot test.

Directed Verilog-2001 tests cover both families, all four sectors, low/high
lanes, missing/mismatched confirms, immutable-ROM protection, unique dirty
sectors, reset during accepted erase and reset before confirmation. Existing
identification/program/NOR tests pass. Integration through the actual shared
DDR arbiter/adapter and dirty tracker confirms an accepted PMM erase completes
after phone reset, with4096 writes and32 dirty events. Warm/cold/program/C-erase
reset regressions and1940-transaction DDR-cache regression pass.

The old flash-reset fixture timed out on untouched HEAD as well: it enabled
DMA routes without DMA/MMC stimulus, allowing Xs into CPU arbitration. Its
flash-only instantiations now explicitly disable DMA_LOCAL/GENERAL_DMA. An
initial cache-line hypothesis was disproved; original test addresses are kept.

## Resource and qualification limits

No new memory, queue, backend port or ordinary read/program pipeline stage.
Source state grows by11 bits before synthesis pruning: three extra command
bits per logical die, plus two selected-sector bits. Erase increments only the
existing address register's12 word-offset bits. Actual ALM/FF count and STA
need Quartus. Operating PLL stays78MHz;104MHz remains the design objective.

This fixes native flash operations. It does **not** establish that erase or the
AMD program tail caused the initial missing PMM50/1. That record's provisioning
and the exact native lookup branch remain a separate investigation. No PMM data,
SIM state, startup test result or deadline is fabricated. No hardware full-boot
success is claimed until a new RBF is tested. The board remains on the approved
six-profile C workaround, original firmware/PMM and Background save Off.

Evidence: [pmm-native-flash-2026-11-13.json](evidence/pmm-native-flash-2026-11-13.json).
Small reproducers/logs are under scratch/pmm-native-write-20261113; generated
CPU fixture outputs are under build/sim/unit-native-pmm-erase.
