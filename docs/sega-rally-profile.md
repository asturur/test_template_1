# Sega Rally race capture on MiSTer

The 17 November capture started during the race countdown. A second screenshot showed 111 km/h and a running clock. The passive DDR recorder returned 357 distinct fetch-PC snapshots spanning 89.5 seconds at 78 MHz, with two missing sequences and a single reset generation. It reported build tag `261117`. The exact active bitstream commit was not established.

## Where the fetch PC landed

| Region | Samples | Share of entire window |
|---|---:|---:|
| Game application | 128 | 35.9% |
| Firmware ROM | 227 | 63.6% |
| Other addresses | 2 | 0.6% |

The firmware count includes 67 in FbsCli.dll, 47 in EUser.dll, 19 in scdv.dll and 11 in BitGdi.dll. The most frequent individual address was 0x50328414 (44 samples, 12.3% of the window). It is the backward branch of a firmware loop issuing CP15 data-cache clean-and-invalidate by index. This records fetch location; the caller, duration of an individual maintenance operation, and effect on frame rate remain unmeasured.

## Payloads worth retaining

All offsets below are relative to the start of E32 code. Counts include both ends of each range and exclude time in any called routines.

| Game loop | Samples | Replay use |
|---|---:|---|
| 0x1da54–0x1daa0 | 21 | Self-contained 20-instruction ARM span. Two fixed-point coordinates feed mask operations and an MLA, followed by two byte loads, a combine and a halfword store. Good cross-check for the Super Monkey Ball span with a different address calculation. |
| 0x1dcc4–0x1dcf4 | 15 | Scans 0x8f00 (176 × 208) halfwords. Tests bit 15, conditionally calls FbsCli ordinal 105, and calls FbsCli ordinal 62 on every iteration. A replay measuring the full scan needs those implementations and their object state. |
| 0x1c9f4–0x1ca04 | 12 | Indexed halfword fill with increment, compare and backward branch. |

The import attribution follows both BL destinations through the application's veneers to their IAT slots, checked against the E32 import block for FBSCLI[10003a15]. The 67 FbsCli samples are module-wide. The capture cannot assign all of them to this one call site.

The original file was read from the local Sega Rally card image at `/SYSTEM/APPS/6R12/6R12.APP`. The Git-ignored copy is `tests/cpu/sega_rally/local/6R12.app` (251,508 bytes, SHA-256 `236f5094346a8ebf4ec49ac76bcd381f59ba49642fd3f182e27c28a248bfbe16`). E32 code starts at file offset 0x7c. Using inferred runtime code base 0xfff00000, 74 of the 128 in-range samples matched the word at the aligned fetch address and another 45 matched the following word. Firmware ranges used the local NEM-4 ROM module map and the reference ROM words. A fetch PC and returned instruction can reflect adjacent pipeline stages. The capture supplies an original executable and candidate loop boundaries for future offline benchmarking; it contains no timed offline replay or FPS measurement.

The 5L third-slot experiment replays both independent loops and the full-screen scan. The full scan connects the original veneers to both native FbsCli exports and uses a checked synthetic post-`Begin` bitmap cursor. [Matched Sega Rally results](cpu-third-data-mapping.md)

[PC histogram, image hashes and attribution counts](evidence/sega-rally-profile-20261117.json)
