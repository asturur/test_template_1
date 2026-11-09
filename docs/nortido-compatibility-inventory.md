## Bluetooth implemented, 2026-11-09

Bluetooth Compatibility is now an independent selector (status20), manual F4
Bluetooth_Compatibility.ngo and automatic boot3.rom/C0. Uses the pinned GPL HCI
responder and BTLDD glue, no real peer and no NOS enable dependency. Two8KiB
staging/undo engines arbitrate DDR writes; shared checksum descriptors stay
skipped until both selectors are OFF. Original NOS ID1 packages stay compatible;
BT ID2 files cannot be loaded through the NOS picker or vice versa. C:/PMM and
UI/startup helpers remain excluded. Reference's separate five BTLDD delay-literal
shortcuts are also excluded; compiled BT glue/object-size/payload are included.
See firmware-overlays.md and evidence/bluetooth-overlay-2026-11-09.json.
Older proposal/inventory notes below are historical, not additional scope.

## User scope update, 2026-11-09

Prioritize NOS, then independent Bluetooth and SIM compatibility. The current
reference NOS replacement has no SIM/network server or BT implementation. BT
has a separate HCI responder; SIM needs its own evidence and backend. Exclude
C: format/routing bypasses and UI/startup edits. Earlier inventory entries below
remain research findings, not permission to include those patches. The minimal
NOS service-table bootstrap is required for its replacement driver, not a UI stub.

## Implementation checkpoint, 2026-11-09

NOS Compatibility is now the first implemented selector/loader. It stages a
private NGO1 pack in explicit8KiB BRAM, applies/restores DDR firmware words and
holds the CPU until ready. Per the user’s updated instruction, NOS ON skips the
primary checksum rather than replacing its expected digest. NOS OFF restores
original descriptor/bytes; package CRC and target preflight remain enforced.
Human filename NOS_Compatibility.ngo; stock Main autoload alias boot2.rom.
See [firmware-overlays.md](firmware-overlays.md) for actual interface and tests.
The broader multi-component design below remains a proposal: Bluetooth/audio
and the proposed reserved-DDR sparse overlay mechanism are not implemented.

# Nortido compatibility-path inventory

Audit date: 2026-11-09. Reference: nortido/NGage-MiSTer at
`4b8480148db15d432e2abf6a6956832c91d9cf55`, read via `gh` into
`scratch/timer-irq-audit/nortido-4b848014/`. No reference build scripts or
binaries were executed. Our requested timer experiment is separate from these
firmware substitutions; no compatibility backend or dummy OSD switch is wired yet.

## What is replaced or bypassed

| Area | Concrete reference behavior | Relevance to our core |
|---|---|---|
| NOS/modem bootstrap | Service overlay redirects `nosstarter.ext` at file offset `350504` to injected initializer `50320860`. That builds a service table containing return-zero functions and installs interface/global pointers. | A NOS replacement must account for this bootstrap, not merely replace three later exports. |
| NOS driver | `hps/guest/nos_glue.S` replaces export words at `511B4028/30`, changes allocation size at `511B413C`, and supplies new object methods. GPL ARM code lives in erased tail `511B6000..511BFFFF`. | Potentially portable to our ARMv4T CPU as optional guest code, after validating the exact firmware profile and kernel ABI. |
| Phone service replies | `nos_isi.c` implements channel construction, pending receives/cancel/completion and narrow accessory/light replies; it records vibration state. Unhandled resources/functions return without providing full cellular service. | Not a complete NOS, MTC, SIM, calls or SMS implementation. Its working UI cannot validate the original NOS hardware path. |
| Bluetooth | `bt_glue.S`, `bt_hci.c` replace the BTLDD write/receive path, enlarge its object, and generate local HCI responses. No real radio peer/link. | Optional independent compatibility feature; no-peer behavior is software substitution, not validation of LRB2 hardware. |
| Audio / external DSP | Service overlays alter MediaServer, SoundDevice and audio-stream code. A PCM mark at file offset `5B2D22` feeds the HPS monitor's audio path and custom FPGA ring. | Not TMS320 DSP execution or its physical protocol. Our soft-CPU core needs a new PCM transport instead of copying the HPS monitor trap. |
| Handset/startup values | `ecust.dll` at `349DA4` changes a load to `mov r0,#3`; helper/startup branches are changed. Gsmbas is redirected toward inserted fixed UTF-16 identity data. | Explicit compatibility values/bypasses. Exact meaning of every altered API is not established; do not promote them to chip reset values. |
| UI/application startup | Starter code/resources change, including redirected application paths. Watcher, Sysagx, Mailinit and FbServ also contain rewrites. | Additional UI/service changes beyond NOS. Semantic purpose of every rewrite remains unclassified; these are not automatically required for a minimal NOS option. |
| C: handling | EStart has a conditional `cdrv` format-guard mark and rewrite; the monitor has a custom C: routing/persistence path. | Our separate C:/PMM storage remains authoritative. Do not copy its save transport or format bypass wholesale. |
| Firmware verification | Service overlay writes both primary digest descriptor address words at `8F18..8F1F` to `FFFFFFFF`, taking the firmware verifier's absent-descriptor early return. | A real checksum bypass. Never include this in our original-firmware mode or quietly claim modified mode is stock verification. |
| Backlight/vibration | HPS software observes kernel activity and replacement NOS vibration state and drives output behavior. | Useful functional stand-ins, not UEM/motor pin/protocol emulation. |
| UEM/battery and other registers | FPGA UEM model uses fixed ADC/profile values and permissive register behavior. | Implementation hypotheses, not physical phone measurements. |
| CPU/system operations | Monitor traps emulate privileged/system instructions and guest execution on the HPS ARM. DMA/cache/address translations bridge the guest and host memories. | HPS execution machinery, not phone services. Our ZAP CPU already owns those architectural functions; copying these traps would require an unnecessary monitor ABI. |

LCD, keypad, MMC and general timers also have FPGA implementations. Their
presence does not make every register/timing detail a verified phone behavior,
but they should not all be called stubs. Nortido's general timers use 26 MHz;
its original NOS scheduling path is replaced.

## Counted coverage and uncertainty

The current release patch list contains **1,428 entries**:
103 monitor traps, 1,320 direct rewrites, two marks, one conditional exit,
one PCM marker and one learned-address marker. Of these entries, 374 lie in
the injected NOS tail and 580 in the injected Bluetooth range; counting them
as separate hardware bypasses would be misleading. The service assembler
additionally applies **589 bytes in 111 runs**.

Every entry was classified by syntax and attributed to an original ROM directory
payload when possible. Module attribution is not a complete semantic decode.
The structured inventory, including unassigned boot/tail ranges, is
`scratch/timer-irq-audit/nortido-patch-inventory.json`, generated by
`scratch/timer-irq-audit/inventory-nortido.py`. Remaining UI/resource rewrites
need individual control-flow review before inclusion in any compatibility set.

## Agreed Firmware menu layout and automatic loading

User decision2026-11-09: **separate ON/OFF entries inside Firmware**, with
selected overlays automatically prepared after the boot files and before CPU Run.
This replaces the earlier file-picker/one-backend selector proposal.

Proposed rows, exposed only for implemented payload capabilities:

- NOS compatibility: Off / On (includes its bootstrap and driver together).
- Bluetooth replacement: Off / On.
- Audio replacement: Off / On.
- Startup helpers: Off / On (only individually audited required helpers).
- Reload overlay pack: manual recovery/reload action.

All overlays default OFF. Selection and applied state are distinct: a requested
ON entry is not ready until its payload, target profile, dependencies and checksum
view are validated. Invalid/missing payload keeps the CPU held and identifies the
reason. Switching a selection while running requires resetting/rebuilding the
firmware view; a live toggle must not leave patched pointers or stale caches.
Turning a component OFF restores its original words and payload padding, not just
an enable bit. C:/PMM stays untouched.

### Automatic payload transport

Use one optional, GPL-only overlay pack containing the available component
payloads and manifests. A practical stock-Main transport is `boot2.rom` alongside
unchanged `boot.rom` and `boot1.rom`, with a manual reload on the Firmware page.
The pack is not Nokia service firmware; its own magic/version/profile/CRC must be
validated and its payload staged separately in reserved DDR.

The already-audited Main source (scratch/service-rom-loader/user_io.cpp:1696–1708)
tries numbered boot0..3 with indices0/40/80/C0, then the legacy boot.rom fallback.
Therefore boot2.rom may be transferred **before** boot.rom. Auto-application must
wait for both original service slots to validate, regardless of arrival order.
The installed Main build still needs an end-to-end transport check; do not rely
on that order without staging/gating. The automatic method applies the selected
components after the boot files are complete, rather than assuming Main sends
all payloads in the desired order.

Stage the whole pack and check it before altering any firmware backing bytes.
For each selected component, check expected original words and dependency/conflict
metadata. Per the user's updated preference, any enabled firmware patch also selects
the reference's explicit checksum bypass. Restore the original descriptor when
all patches are OFF; do not recompute or overwrite the expected digest. Keep the CPU
held until all writes drain and cache/reset preparation completes. A reload of
either official service file invalidates applied-overlay readiness and schedules
reapplication after both slots are complete. Missing pack is harmless with all
entries OFF; no fake enabled backend is exposed. Implementation remains pending.

## Concrete OSD path

The separate reset-only component selectors above are feasible with one existing
ARM CPU and a validated overlay pack. No second phone instance is needed.

1. Keep all overlays OFF by default. Latch selections during reset, hold the CPU
   while preparing the selected view, and invalidate the ROM instruction buffer
   and CPU caches through the normal reset path. Record the selected profile in
   diagnostic exports and simulation manifests. Stock and compatibility states
   must never be restored interchangeably.
2. Package only GPL replacement code and a bounded patch manifest, keyed to our
   checked MCU/PPM identity. Load it separately from official `boot.rom` and
   `boot1.rom`; leave those files and the user's C:/PMM images unchanged. A menu
   reload action can load the same pack manually on the Firmware page.
3. Use spare reserved DDR after the current PMM allocation for the replacement
   payload, with a small sparse read-overlay table for hook words. Current
   reserved allocation ends at offset `1810000`; a candidate payload base is
   `1820000`, subject to the actual reservation bound. This avoids another CPU
   and a large BRAM copy of firmware. Original mode bypasses the overlay entirely.
4. Start with the minimal NOS bootstrap/export payload. Verify its callable ABI,
   actual return/cancel behavior and absence of original NOS scheduling before
   adding Bluetooth. Audio is a later distinct transport task. Exclude HPS CPU
   traps, unrelated launcher edits and C: format bypasses from this first set.
5. Handle firmware checks explicitly. NOS export changes lie inside the primary
   MD5 range. The user explicitly selected checksum skipping when a patch is
   enabled: replace both primary descriptor address words (8F18..8F1F) with
   FFFFFFFF, taking the reference's absent-descriptor early return. NOS OFF
   restores the original descriptor and all bytes; expected digest words remain
   unchanged. This is compatibility mode, not stock verification. Avoid a late
   uncoordinated overlay: the checksum can leave
   affected words in D-cache, requiring a proven cache transition.
6. Test Original byte identity, wrong-profile rejection, payload bounds, reset
   transitions, C:/PMM preservation, buffer invalidation and a separate boot to UI
   in each profile. Do not expose an OSD option until it actually selects a
   complete working backend.

This is an implementable parallel path, but not a quick replacement of a single
HDL peripheral. It intentionally changes the *executed guest view* only in the
explicit compatibility mode; source service files remain untouched.

## Reference entry points

- [Service overlay](https://github.com/nortido/NGage-MiSTer/blob/4b8480148db15d432e2abf6a6956832c91d9cf55/hps/lib/ngl_svcrom.c)
- [NOS export/glue replacement](https://github.com/nortido/NGage-MiSTer/blob/4b8480148db15d432e2abf6a6956832c91d9cf55/hps/guest/nos_glue.S)
- [NOS reply implementation](https://github.com/nortido/NGage-MiSTer/blob/4b8480148db15d432e2abf6a6956832c91d9cf55/hps/guest/nos_isi.c)
- [Bluetooth replacement](https://github.com/nortido/NGage-MiSTer/blob/4b8480148db15d432e2abf6a6956832c91d9cf55/hps/guest/bt_glue.S)
- [Release patch list](https://github.com/nortido/NGage-MiSTer/blob/4b8480148db15d432e2abf6a6956832c91d9cf55/releases/ngage_patch.txt)
