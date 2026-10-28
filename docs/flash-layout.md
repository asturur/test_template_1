# Physical flash capacity and unresolved layout

Current checkpoint: [status.md](status.md). Capacity audit: 2026-10-27.

## What is known

The user confirms three 64-Mbit internal flash devices (24 MiB total), with
roughly 3.4 MB exposed as user storage. The
[Nokia NEM-4 schematic, sheet A-10](https://altehandys.de/downloads/ser-no-n-gage-schematics.pdf#page=10)
independently shows D310/D311/D313 as AM29N643 devices, each labeled 4M x 16:
8 MiB per chip. The user has saved the canonical local PDF as
`docs/ser-no-n-gage-schematics.pdf`; its SHA-256 matches the previously retained
`scratch/research/schematics/nem4.pdf`:
`43d60e8c0a7e71aa6763b4dd66f4e000227da5f51fb62ae28ef9d8bbb3dc345e`.
The existing page render is `scratch/research/schematics/memories.png`.
These are flash devices, distinct from the SDRAM on the same sheet.

The user-visible drive capacity does not specify its physical start/end or the
allocation of reserved sectors. Do not treat it as the missing tail of SYM.ROM.

| Quantity | Bytes / hexadecimal | MiB |
| --- | --- | ---: |
| Three 64-Mbit chips | 25,165,824 / `0x01800000` | 24 |
| Supplied logical `SYM.ROM` | 18,612,224 / `0x011c0000` | 17.75 |
| Physical capacity minus dump length | 6,553,600 / `0x00640000` | 6.25 |
| Sum of type-1 entries in selected table `0x830` | 20,905,984 / `0x013f0000` | 19.9375 |
| Type-1 allocation minus dump length | 2,293,760 / `0x00230000` | 2.1875 |

These are binary capacities. The earlier conversational estimate of roughly
5.4 MB mixed decimal/binary units; the exact capacity difference is 6.25 MiB.
That difference includes unknown layout/content and is not a measured partition.

## 2026-10-28 flash-ID mismatch to investigate

The cache-disabled firmware continuation reaches a VARIANT 0x00010013
diagnostic after consuming early flash classifications 0,4,0. The bounded
boot trace `build/sim/runs/variant-early-trace/` shows these are produced by
the firmware probing our modeled CS0/CS1/CS2 IDs: CS1 uniquely uses the
assumed 0x257e identity and yields class 4, while CS0/CS2 use 0x227e and
yield class 0. Independent Unicorn execution of the unchanged firmware table validator
(`scratch/variant-class-test/`) confirms 0,4,0 reaches VARIANT fault 19, while
0,0,0, 4,4,4 and 0,0,4 pass this validator. It uses synthetic RAM and stops
before later side effects; it does not establish a working phone boot.
A cache-disabled checkpoint counterfactual changes only the saved CS1 class
from 4 to 0 after verifying the table; firmware passes the `VARIANT` diagnostic
and reaches an unknown write to 0x0c120074. This is an artificial intervention,
not evidence for the physical flash identity or a successful boot; see
`build/sim/runs/boot-variant-counterfactual/`.
The schematic labels all three devices AM29N643GT70MVAI, but
chip IDs, chip-select assignment and actual board variant remain unverified. The manufacturer-authored [Am29BDS643G datasheet](https://datasheet4u.com/pdf/564541/AM29BDS643G.pdf) lists manufacturer ID 0x0001 and three device words 0x227e/0x2202/0x2200; its handshake option is 0x0043 when enabled. The exact equivalence of the schematic marking AM29N643GT70MVAI to this datasheet and the installed hardware remain to be verified.

An independent Unicorn check using the original first-probe routine and
synthetic IDs (`scratch/flash-first-probe-test/results.json`) confirms results
0 for CS1 0x227e, 2 for 0x257e, and 1 for 0x22d1 when CS2 is AMD 0x227e.
Firmware's first probe explicitly recognizes 0x257e and chooses the 0x830
bank table with 16 MiB RAM; the 0x227e value is not among the compared AMD
device IDs and falls toward 0x638 with 8 MiB RAM. This conflicts with the
schematic's 16 MiB SDRAM and current logical dump reconstruction, so do not
silently make all IDs identical. Confirm the actual device identification and
reconcile firmware variant, bank table and physical memory mapping. The
`VARIANT` linkage is evidence under provisional assumptions, not proof of
physical behavior. A full fixed-cache V15 run with the same assumptions also
reached VARIANT fault 19 at cycle 725,795,188; the trace confirms the first
two classes 0 and 4 and the same flash identify responses. Its screen is the
white clear.

A bounded all-equal-ID diagnostic confirmed the firmware returns flash classes
0,0,0, but only after a separate hypothetical erased-value response for the
unknown CS2 array probe; without it the strict model stops at cycle 554. The
fallback table then exposes 8 MiB RAM, in tension with the schematic's 16 MiB
SDRAM. See `build/sim/runs/flash-all-equal-probe/` and
`build/sim/runs/flash-all-equal-erased/`. A bounded continuation reached
2,000,000 cycles with no additional unmapped access; it is not a full boot.
Neither is an authentic boot model.

Under the current table-order mapping assumption, table 0x638 has only
0x00df0000 bytes of type-1 ROM regions, versus the 0x011c0000-byte logical
image (short by 0x003d0000 bytes); table 0x744 has 0x00ff0000 type-1 bytes
(short by 0x001d0000). Other mappings or runtime extensions could change that
interpretation, so this arithmetic does not establish the physical layout.

A short fixed-cache run with all devices set to the hypothetical 0x257e
identity selected the 16 MiB table and wrote classes 4,4,4 directly through
firmware, without a RAM intervention. It remains unverified against the
schematic chips; a separate full diagnostic run is tracked in `status.md`.
Output: `build/sim/runs/flash-all-257e-probe/`.

## What the model currently assumes

The experimental map uses flash select windows at `0`, `0x02000000`, and
`0x04000000`. These are firmware-derived model addresses; matching them to all
physical chip/reset-decoder details remains unverified. Assigning consecutive
logical dump bytes to type-1 entries is also still a hypothesis.

Aggregating selected table `0x830` gives:

| CPU-visible span marked type 1 | Size | Assumed dump offset |
| --- | ---: | --- |
| `0x00000000..0x006fffff` | 7 MiB | `0x00000000` |
| `0x02000000..0x023fffff` | 4 MiB | `0x00700000` |
| `0x04000000..0x047fffff` | 8 MiB | `0x00b00000` |
| `0x00700000..0x007effff` | 0.9375 MiB | `0x01300000` |

The last span is later in table order despite being on the first address window.
Table order is not simply increasing physical address or a raw concatenation
of all three chips.

With three assumed 8-MiB chip spans, the portions not covered by those type-1
entries would be `0x007f0000..0x007fffff` (64 KiB) and
`0x02400000..0x027fffff` (4 MiB). This is consistent with there being room for a
user filesystem and reserved data, but does not establish their contents or
prove those are the exact filesystem boundaries.

The table additionally contains two type-3 entries at
`0x02400000..0x029fffff`, with different attribute flags. That 6-MiB window
extends beyond an 8-MiB chip starting at `0x02000000`. Aliasing, decoder behavior,
board variants and the meaning of those entries must be investigated before
converting the whole window into linear writable flash.

## Why the current stop is not resolved by capacity alone

The stop is a read at `0x046c001c` (PC `0x1ea4`), inside a span our selected table
marks type 1. The current mapping turns it into file offset `0x011c001c`,
28 bytes beyond the supplied dump. It is not automatically a read from the
3.4-MB user drive. The scanner at `0x1e24` is checking candidate image signatures.

Possible explanations still include a compacted logical ROM layout, physical
holes/aliases/reserved images, a wrong mapping hypothesis, or actual flash
contents absent from the logical dump. Capacity alone does not choose among them.
No additional firmware download or chip dump has been established as necessary.

## Current extension experiment and remaining map work

[firmware-inventory.md](firmware-inventory.md) identifies all 507 extra NEM-4
files in ROOT at inferred virtual `0x5123e338..0x51370000`. The subsequent
[reconstructed extension](extension-reconstruction.md) preserves them unchanged,
rebuilds missing directory/header metadata, and gets past the scanner. This is
a separate opt-in tail, with explicitly labeled erased padding only inside the
selected type-1 banks. It does not authenticate a complete physical flash dump.

The next physical-layout work remains to reconcile the bank ordering with three
8-MiB devices, existing headers at file `0` and `0x300000`, reserved images, and
the type-3 windows. In particular, explain the 6-MiB type-3 window beginning at
`0x02400000` versus an 8-MiB chip at `0x02000000`. Do not extend flash backing or
place the user drive from its reported logical capacity alone.

The scanner analysis below records the original no-extension frontier; it is
retained evidence, not the furthest current experiment.


## What the saved execution trace now establishes

`make inspect-flash-scan` reads the existing software bus/result files; it does
not rerun either CPU. It writes `build/sim/flash-scan-analysis.json`, including
source hashes and the actual caller/scanner observations. `make inspect-boot`
now also disassembles the caller and both mapping/scanning routines.

The observed sequence is more specific than an arbitrary missing ROM word:

1. Caller `0x0dc4` reads the core ROM base `0x50000000` at physical `0x8c` and
   size `0x011c0000` at `0x90`, then calls the bank mapper at `0x1c54`.
2. After that mapping, the caller's next virtual address is `0x511c0000`, exactly
   the core ROM end. The returned physical continuation is `0x046c0000`.
3. Caller `0xee4` invokes `0x1e24` with core-header pointer `0x80`, the remaining
   bank entry at RAM `0x0afff498`, and that physical continuation.
4. The scanner reads the bank's physical start `0x04100000` and size `0x00700000`.
   It compares the next candidate's words at `+0x1c/+0x20/+0x24` against the
   core words at `0x80/0x84/0x88`: `00000000,7c42f480,00e0aacc`.
   EKA2L1's EKA1 ROM header structure identifies these as version/build and time.
5. The first candidate read, `0x046c001c`, is where our bounded model stops.
   If comparison succeeds, code at `0x1ed0` also checks candidate `+0x0c` against
   the next virtual address, and reads its size at `+0x10`. On a mismatch,
   `0x1fc4/0x1fc8` advance both addresses by 64 KiB and continue through eligible
   banks. Exhausting the search can return zero at `0x1fec`.

This control flow is consistent with searching for an additional/extension image
**after** the mapped core ROM. That interpretation is inferred from code and
arguments. The later full firmware inventory also recovers actual additional
retail ROM payload in ROOT, linked beyond the core image. The separate extension
experiment now reconstructs its preceding metadata. Default model behavior
without that option is unchanged.

The 12-byte comparison pattern occurs at file `0x80` and `0x300080`. Neither is
at candidate base + `0x1c` for a 64-KiB-aligned file candidate; the offline search
finds no matching aligned extension header in the supplied file. This does not
prove no additional image exists elsewhere in the physical flash.

## Using emulator return values to identify dump offsets

The user's method is valid when an emulator performs the same access against an
independent image/device model. Record PC, address, memory mode, read width and
several neighboring returned bytes, then locate a sufficiently distinctive
sequence in the dump. Trace the backing-file offset as well where possible;
a single zero or `ffffffff` word does not identify a unique sector.

For that original missing-header read there is no independent emulator value:

- EKA2L1 maps the logical ROM file at its header's virtual base and supplies its
  own kernel startup. It does not run this physical candidate-header search.
- rengage reserves a synthetic 20-MiB virtual ROM window and loads the supplied
  file into it. Any zero backing beyond the file is an emulator allocation
  artifact, not captured physical flash data. Its startup is also not our cold boot.
- Our Unicorn reference and HDL runner share `BootProfile`. Both rejecting the
  missing bytes confirms their common execution frontier, not an independent
  answer about what a real phone returns there.

For known mapped ROM, EKA2L1's logical backing is still useful:
`file offset = virtual address - 0x50000000`. The candidate linear address
`0x511c001c` would imply offset `0x011c001c`, already past this file's end.
The observed zero at core `0x80` is an **expected comparison word**; it is not
the return value of the failed candidate read. Do not fill the candidate with
that value merely to make the comparison succeed.

A missing optional image can be represented by a nonmatching header; erased NOR
would be a separate explicit `ff`-content hypothesis. Establish a bounded range,
keep the original dump unchanged, and compare progress on both CPUs if implementing
such an experiment. The implemented extension instead combines known ROOT
payload with explicitly synthesized metadata and bounded erased padding; it does
not replace the entire retail tail with erased flash.
