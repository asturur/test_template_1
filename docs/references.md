# N-Gage reference research

Current checkpoint and resume tasks: [status.md](status.md).

Inspected 2026-10-27. The requested inexpensive research agent inspected the
repositories; its full notes are preserved locally in
`scratch/research/ngage-reference-findings.md`. Reference checkouts remain in
`scratch/references/`; no reference project scripts were executed.

## Supplied repositories and website

| Reference | Inspected revision | Useful contribution |
| --- | --- | --- |
| [JaCzekanski/rengage](https://github.com/JaCzekanski/rengage/tree/db52d00f285c71c340acc902a8b208d228e3581a) | `db52d00f285c71c340acc902a8b208d228e3581a` | Minimal Unicorn replay harness and dump-loading convention |
| [loociano/n-gage-emulation-docs](https://github.com/loociano/n-gage-emulation-docs/tree/e3cdd42a09fd6d93e9050bdb26a9a8ec3811ccad) | `e3cdd42a09fd6d93e9050bdb26a9a8ec3811ccad` | Virtual memory map, file formats, SDK and reverse-engineering references |
| [N-Gage Emulation Docs: memory map](https://n-gage.loociano.com/#memory-map) | Same map as the inspected repository | Convenient published version of the virtual layout |

The published map is explicitly headed **Virtual Address Map**. Selected entries:

| Virtual address | Meaning in those notes |
| --- | --- |
| `0x40000000` | Super page and CPU page |
| `0x41000000` | Page directory |
| `0x42000000` | Page tables |
| `0x50000000` | ROM image |
| `0x58000000` | Memory-mapped I/O |
| `0x5f000000` | Video RAM |
| `0x60000000` | RAM |
| `0x80000000` | Kernel data/bss |
| `0xffff0000` | Vectors |

Source: [index.md, lines 45–69](https://github.com/loociano/n-gage-emulation-docs/blob/e3cdd42a09fd6d93e9050bdb26a9a8ec3811ccad/index.md#L45-L69).
These are useful targets for inspecting the firmware's page tables after MMU
setup. They do not identify physical SDRAM, LCD wiring, reset aliases, or the
startup register block at `0x08000000`.

[rengage's main.cpp](https://github.com/JaCzekanski/rengage/blob/db52d00f285c71c340acc902a8b208d228e3581a/src/main.cpp)
loads an 8 KiB `boot.dmp` at zero and reserves `0x1400000` bytes for `rom.dmp` at
`0x50000000`. It creates synthetic superpage, MMIO, and high-vector arrays and
single-steps Unicorn. It has no register-level Nokia peripheral model or
physical SDRAM model. Its flat MMIO array cannot establish hardware behavior.

## What BOOT, ROM, and ROOT dumps contain

Following the docs' SDumper link led to
[Rusty Starship](https://gitlab.com/tambre/rusty_starship/-/tree/c8a3fa850bd3ef14be96131391b3c5f51d32d387),
revision `c8a3fa850bd3ef14be96131391b3c5f51d32d387`. Its running Symbian application
uses `Mem::Copy` from process-visible addresses and writes files through the OS.

- [BOOT](https://gitlab.com/tambre/rusty_starship/-/blob/c8a3fa850bd3ef14be96131391b3c5f51d32d387/symbian_dumper/symbian_dumper.cpp#L155-171)
  is an 8 KiB snapshot starting at virtual address zero while Symbian is running.
  It does not establish the chip's power-on instruction fetch contents. The
  model ID is included in the filename.
- [ROM](https://gitlab.com/tambre/rusty_starship/-/blob/c8a3fa850bd3ef14be96131391b3c5f51d32d387/symbian_dumper/symbian_dumper.cpp#L121-143)
  starts at `UserSvr::RomHeaderAddress()` and uses `TRomHeader.iRomSize`.
  It is a logical OS image and need not be a complete physical flash dump.
- [ROOT](https://gitlab.com/tambre/rusty_starship/-/blob/c8a3fa850bd3ef14be96131391b3c5f51d32d387/symbian_dumper/symbian_dumper.cpp#L173-200)
  starts at `UserSvr::RomRootDirectoryAddress()` and spans accessible memory
  until the dumper encounters a fault. It is not a raw flash partition by
  construction.

The supplied NEM-4 BOOT blob's first vector points to `0x50327fe0`, a kernel
exception/fault stub in the supplied `SYM.ROM`. This local disassembly observation
is consistent with the dumper's runtime snapshot semantics. The archive's file
provenance has not been independently authenticated; its filenames and sizes
match this convention. Do not concatenate BOOT/ROOT/ROM into a physical flash
image based on their names alone.

## Physical hardware leads

The [original Nokia NEM-4 schematic](https://altehandys.de/downloads/ser-no-n-gage-schematics.pdf)
shows UPP_WD2 external memory and SDRAM buses on sheet A-3 and a memories sheet
A-10. This supplies board wiring evidence, but no software register map.
The service material describes three flash devices interfacing with UPP_WD2.
A chip-level programming manual, trustworthy low-level implementation, or
hardware trace is still needed to settle register functions and cold-reset state.

Additional local leads are `scratch/references/TriX` and
`scratch/references/nokia_6600_recomp`. TriX's emulated TIKU/ASIC11 maps are not
NEM-4's map. Nokia 6600 shares a WD2-family lead but has a different phone and OS
configuration, and that project explicitly uses synthetic boot handoffs.
Neither is treated as hardware ground truth.

The measured firmware experiment and its remaining assumptions are documented
in [boot-model.md](boot-model.md).

## Further local evidence from startup

Visual inspection of NEM-4 sheet A-10 identifies D310/D311/D313 as
`AM29N643GT70MVAI`, each labeled 4M x 16 flash, and D312 as 8M x 16 SDRAM.
The retained PDF and page render are under `scratch/research/schematics/`.
The AMD Am29BDS643G datasheet was also retained there; its autoselect and burst
configuration tables inform the bounded simulation model. The schematic is a
board-revision source and does not authenticate the installed parts or the dump's
physical flash layout. The simulated CS1 variant remains a hypothesis.

The ROM's own MMU-state-dependent address selections now confirm specific
physical/virtual MMIO pairs, including `0x0c14f008` and `0x5814f008`.
`make inspect-boot` writes these pairs, all three startup tables, and relevant
disassembly to `build/sim/boot-analysis.json`. See [boot-model.md](boot-model.md)
for the exact pairs, current firmware frontier, and still unknown reset values.


## Software emulator execution versus phone startup

EKA2L1 was inspected at revision `4dfaf5060e3bbb4b7e7bbc26f8ec7ffc2b959bc3`.
It maps the logical ROM and executes guest ARM code, but supplies kernel/thread
startup and supervisor-call implementations on the host. The relevant source
permalinks and how we use a separate Unicorn reference for actual bootstrap
instructions are in [software-reference.md](software-reference.md).
The three local manuals in `docs/` provide the ARM architecture/CPU reference;
they do not document Nokia's UPP_WD2 peripheral registers.


The user has now placed the same NEM-4 schematic at
`docs/ser-no-n-gage-schematics.pdf`. Its SHA-256 is
`43d60e8c0a7e71aa6763b4dd66f4e000227da5f51fb62ae28ef9d8bbb3dc345e`,
identical to `scratch/research/schematics/nem4.pdf`. Prefer the docs copy as the
local source; existing page renders remain useful.


## Full local firmware audit

See [firmware-inventory.md](firmware-inventory.md) and `make firmware-inventory`
for verified NEM-4, QD retail, and QD developer inputs. All 3,241 core-ROM files
match the unpacked trees. The two retail ROOT snapshots contain every additional
unpacked file absent from their core ROMs; the developer ROOT is an exact ROM
suffix. This adds real beyond-core input bytes to the earlier dump-provenance
research without making ROOT a complete raw physical flash image.

## UEM ADC evidence at the post-MMU frontier

TriX revision `f35f8bfa90641e17ab4b33ba644482d303faa5cd` is retained locally.
Its real-device `projects/uem_dump/uem_dump.c` and simulated
`plugins/TriX_HWemu/hw_cbus_devices.c` agree on the conversion-control/result
register pair. The exact NEM-4 sequence, BSI/channel-6 interpretation, limits and
source links are recorded in [uem-control-bus.md](uem-control-bus.md). This does
not transfer TriX's ASIC11/TIKU memory map or analog defaults to NEM-4.
