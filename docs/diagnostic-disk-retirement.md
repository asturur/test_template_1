# Diagnostic disk retirement — 2026-11-13

The diagnostic disk transport is removed. Runtime diagnostics use DDR3 snapshots
and text capture through `tools/ngage_runtime_diag.py` over SSH. No firmware,
media files, CPU clock or memory-map changes are involved.

## Removed implementation

- Mount diagnostic disk (S3/NGD) and Export diagnostics OSD entries.
- `ngage_diag_export.v`, its source-list entry, disk CLI
  `tools/ngage_diagnostics.py` and dedicated exporter tests.
- Export trigger/pending state, controller, timeout, LED indications and NGD
  read-port mux/arbitration. The DDR producer now owns that read port directly;
  its obsolete `allow_capture` input is removed.
- Fourth HPS disk slot and corresponding array elements. Production slots are
  now C:0, PMM1 and read-only MMC2. Persistence/MMC fixtures use the same slot
  counts; the legacy single-bundle fixture retains only its one real slot.

Two exporter RAM instances disappear: a512×16 snapshot and the exporter's
256×16 sector buffer, totaling12,288 payload bits. Controller and HPS slot
logic also disappear. This is a source inventory, not a fitted ALM/M10K count.
Quartus fit and timing have not been run for this change. In particular, this
cleanup does not establish closure of the separate DDR snapshot timing paths.
Operation remains78MHz;104MHz remains the design objective.

## Preserved behavior

The NGD recorder remains because DDR snapshots consume it. Snapshot/text DDR
addresses, wire version, seals, record layout and host reader are unchanged.
The retired disk-busy status bit is tied to0 to retain its existing position;
other LCD/DMA/MMC errors remain reported. C:/PMM save controls and MMC remain.
There is no diagnostic video renderer reintroduction.

Removing the mount row shifts CPU mode one selectable OSD row upward. Any
script using the old seven-Down navigation must be adjusted; confirm the menu
position before starting the CPU. Old diagnostic disk images are unnecessary
but this change does not remove files from the user's SD card.

## Verification

All checks below pass using the existing offline `jotego/simulator:arm64` image:

| Check | Result |
| --- | --- |
| DDR diagnostics and host reader | Ring10/ring3, physical DDR, poisoned snapshot/text BRAM, reset, ownership, torn reads, wrap and dedup pass |
| NGD recorder | Existing diagnostics regression passes |
| Actual three-slot raw persistence |31checks,49reads,12writes |
| Ordered/background persistence |36checks,59reads,20writes, including bounded save/reset and delayed write errors |
| Actual MMC/HPS | Direct36cases; three-slot265094clocks,9card reads,2other reads,2bulk reads,7tail words and2128overlap cycles |
| Legacy NGA save fixtures | Both restore/flush/remount/mutation cases pass,22reads/7writes each |
| Production raw NOR | Stream/cache8KiB/bulk configuration passes, original firmware immutable;12reads/6writes, restore5914/save14495cycles |
| Source graph |173files across9QIPs; deleted exporter absent |
| Production top | Structural elaboration passes with HPS/PLL stubs |
| Formatting | Pinned Verible idempotent for changed maintained RTL |

Commands are the existing `tests/phone/diag_ddr/run.sh`,
`tests/phone/diagnostics/run.sh`, `tests/phone/raw_save/run-hps.sh`
(with and without `ORDERED_SAVE=1`), `tests/phone/mmc_hps/run.sh`,
`tests/phone/save_hps/run.sh`, and
`STREAM_TRANSPORT=1 FLASH_CACHE_BYTES=8192 BULK_PERSISTENCE=1 sh tests/phone/raw_save/run-nor.sh`.
Top check: `sh tests/phone/mister_transport/lint-top.sh`.
Source check: `tclsh tools/check_quartus_sources.tcl`.

The legacy NOR fixture initially exposed missing stream-adapter source-list
dependencies. Its runner now includes the two existing stream modules; the
full rerun passes. No production transport change was needed for that repair.
Board operation, fitted savings and timing remain unverified for this cleanup.

[Source hashes and check results](evidence/diagnostic-disk-retirement-2026-11-13.json).
