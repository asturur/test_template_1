# RF fix board qualification and next ADSP assertion

Read docs/rf-native-media.md and docs/evidence/rf-board-qualification-2026-11-13.json.
Installed artifact43514093456/646ac68/seed44 SHA2399bb9e... matches the card RBF.
No production HDL, timing, PLL or disk image changes in this session.

Retained evidence:
- running.jsonl: unchanged qualified RF observer, receiver F1A1/body20A10103,
  then kernel panic FILE: FI/00010001; no final RF-result qualification.
- assert/running.jsonl: RF observer plus native assertion-import observer;
  460 snapshots/no gaps/reset/panic/fault; original result1E=00, ADSP36=01.
- clean-control.jsonl: original full ROM/no observers,560 snapshots; panic
  recurs. Cannot dismiss it as RF-observer interference.
- assert/minimal-running.jsonl: ONLY native assertion hook, RF/exit/SIM/DOS
  probes omitted. Captures St_product.c/DF2, expression
  pResp_adsp->message_id == ST_ADSP_RUN_RESP, LR516A629B. Native resultRF00,
  ADSP03/pending. Actual unexpected ID not read; older5902 is only a lead.
  475 valid snapshots/no reader gaps retained; SSH timeout lost final tail.
  SSH reauthenticated with already-approved credentials for normal cleanup.

The successful receiver delivery takes171225 clocks/~2.195ms including probes;
this is not full test duration. Original timeout argument500 and native status
logic remain. The positive result qualifies RF, not reliable overall boot.
Native ADSP and SIM readiness remain unresolved; display Insert SIM.

summarize.py decodes bounded records with producer-cycle/sequence mapping and
validates result indices against the original native registry. Its source is
tracked; raw captures and generated artifacts remain ignored locally.

assert/trace.S is observation-only ARM code at mapped NOS padding51716D00.
It replaces only the ARM branch in Thumb assertion import516C74E8, tailcalls
original514A2804 unchanged, and preserves original args/registers/flags/SP.
It does NOT intercept every direct ARM call to the assertion routine. Direct
kernel MMIO/NOS-global reads are appropriate to this NOS context, not arbitrary
user-mode wrappers. Strings are bounded160bytes within known ROM range;
results are24bytes from native80024388, never host stale SDRAM.

Qualification:
  arm-none-eabi-gcc -c -march=armv4t assert/trace.S ...
  arm-none-eabi-ld -Ttext=0x51716d00 --entry=assert_entry ...
  arm-none-eabi-objcopy -O binary ...
Run assert/test.py in the existing offline jotego/simulator:arm64 image with
PYTHONPATH=/work/scratch/profile-records-20261113/linux-unicorn/site.
Fixtures check bounded/invalid pointers, unchanged results, regs/flags/SP/native
ARM tail and stack/debug-only writes. Set banked CPSR mode BEFORE setting SP;
the first fixture got this order wrong and failed before board installation.

To regenerate minimal installer, first build/reuse the qualified RF probe from
scratch/rf-timeout-20261113; copy its prepared/observer.py to this directory's
observer.py. Then run assert/prepare_minimal.py from repository root. It retains
original ROM/per-word/fresh-Hold/restore/save-Off/snapshot guards, drops all RF
hooks, computes original raw branch plus payload and diagnostic checksum words,
and retains the original checksum check. It never connects or applies itself.
No application before unit qualification and original fresh-Hold checks.

Use mister-control skill for all board commands and guarded saved settings.
Restore original automatic Run/save-Off; reload removes all diagnostic hooks.
Verify full original88fd... and unchanged C4a75.../PMM7118... afterward. No SD
backups, other-thread simulations or CI monitoring. Unrelated .githooks and
tools/verible setup belong to the user/other work and were left untouched.
