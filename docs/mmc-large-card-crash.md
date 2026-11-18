128MB Group1 result: successful native installer discovery in App Manager,
103SIS, no kernel panic/save error in120s, save queue0. Card left mounted.
This differs in count/content AND capacity from failing383-file cards;
capacity alone remains an unproved explanation. See sis-library.md for details.

Latest state: user requested permanent four-group collection and128MB Group1.
Old local control images described below have been deleted; hashes/audits remain.
See [sis-library.md](sis-library.md) for current sources, new image and pending
SD cleanup/native test. User's running full SPMark test must remain untouched.

# Large installer-card crash investigation — 2026-11-16

Installed RBF is exactly b707ebd, SHA256
fbc5ba96eaba51502cc73502ebf4bef8e1138e79e355ac15dc6b92c1a99ea46d.
This is the old read-only MMC interface, not the new7bbf860 write build.
Actual clock remains78MHz. Its fit fails setup by2.087ns, so physical timing
remains an unresolved confounder rather than a signed-off platform.

## Captured observations

| Card/test | Observed result |
| --- | --- |
| User cold boot,1GB with383SIS at root | Screenshot App. closed — Main.12s DDR capture: CPU running, no kernel panic, zero save queue/errors. Main is the displayed name; its exact process/category/reason is not captured. |
| Original-firmware replay, same full1GB | Different failure: final kernel spin50324294. Special10000000 packet preserves PC503416DC and fault address85D03EF8, not an ASCII category. Native instruction at503416DC is LDR r3,[r0]. Queue/errors remain clear. |
| Empty1GB, identical MBR/BPB/CID/CSD | Reaches normal Phone home after120s, no panic or helper confirmations. Linux image position295424 equals FAT root-directory end, supporting native reads beyond footer/boot metadata. No full operation/capacity qualification yet. |
| Same383SIS in512MB FAT16/8KiB clusters | Same App. closed — Main after cold boot; CPU alive, no kernel panic or save error. Reducing capacity alone does not fix it. |
|512MB, same packages, FExplorer root/rest in INSTALL | Same Main dialog; after one OK, another dialog identifies EtelServer. This layout does not avoid the failure. |
|512MB original root layout with CSD temporary WP | Same Main application error; protection alone is insufficient. |
|256MB, all383SIS, FAT16/4KiB, read-only | Same App. closed — Main, independently confirmed by screenshot and user; CPU alive, no kernel panic/save error. |
|64MB, threeSIS, FAT16/4KiB, read-only | Reaches FExplorer Installer information/confirmation screen; no Main dialog, kernel panic or save error during120s capture. Installer not confirmed. |

These boots naturally update C:/PMM through the user's autosave. They are not
byte-identical restored-disk replays. Full1GB replay reported reset generation0;
empty1GB and512MB reported1. Keep those initialization differences visible and
do not claim the directory contents alone already prove a root cause.

## Observer attempt and original firmware

The existing c76a4d88 exit observer passes current ZAP argument/register/flags/SP
and ARM/Thumb return tests at waits0/3 in a private fixture. Host guard tests
also pass. However, its strict fresh-generation/save guard refused application
on this board's held startup. One captured refusal has zero execution/bus
history but reset generation1. No guard was relaxed and no observer was applied.
Original ROM88fd596a... checks passed. The subsequent hardware replays are
uninstrumented original firmware, with no checksum/deadline/startup substitutions.

Temporary saved Hold/save-Off settings were restored to the original16bytes,
00002000000000000000000000000000. Native replays run with Background save On.
No C:/PMM image was replaced and no card backup was created. Only generated
MMC controls are changed. Other chats' simulations/checkpoints are untouched.

## Image controls

The512MB card holds exactly the same383SIS payloads and385total files as the
1GB card. Its independent FAT audit and full SD checksum pass:
536,740,352bytes, SHA256
7e32b199df0d77bff790c876f65a2240d84ed7192610882714feeebfe359ab59.
Free space296.5703125MiB. Card identity changes naturally with the new capacity.

The directory-layout control reuses its exact CID/CSD and package bytes;
FExplorer121361bytes remains at root and382SIS files move under INSTALL.
Independent FAT/readback checks pass. Only10aligned4KiB blocks differ. After
Menu unloaded every handle, those blocks were updated on the generated SD
512MB image and its full readback matched the local control SHA256
a3bdac23e0fb2f07feb90a9864377830673568ab9929a3d8e6cde9b4462ec54a.
The original1GB SIS file remains unchanged. The active512MB SD filename now
contains this folder-layout control, unlike the original local root-layout
build/mmc/ultimate-sis-512mb.mmc. Local matching control is
build/mmc/ultimate-sis-512mb-folders.mmc.

A further control sets CSD temporary write protection on the original512MB
root layout. It was deployed and its original-firmware replay reproduced Main application error.
The active SD512MB file is SHA16ef5beda7f9a4969b3cc0fa1879f256c60635b38e50a4da7a0b0c431f87c5d4,
matching local build/mmc/ultimate-sis-512mb-protected.mmc; it supersedes the
folder-layout file described above. The unchanged error shows that advertising read-only media does not by itself
fix this failure. The exact application panic reason remains unknown.

Evidence: scratch/mmc-1gb-crash-20261116/, with exact identities, original
settings, DDR JSONL, decoded text, observer refusal/qualification, transfer
receipts, control patch and capture-summary.json. Screenshots live under
build/sim/screens/mmc-1gb-crash-20261116/.

## 256 MB and 64 MB read-only controls

User requested smaller read-only cards. Both are independently audited FAT16
with 4 KiB clusters, a complete capacity/footer and CSD temporary write protection.
All staged SIS files were read back and checked byte for byte.

- `build/mmc/ultimate-sis-256mb-ro.mmc`: 383 installers, 41.83203125 MiB free;
  SHA256 `9a8b9168ca124fd5cb934ead582b0e9d7914a4058a08e404aa908e88d32aa32c`.
- `build/mmc/ngage-test-64mb-ro.mmc`: SPMark04, FExplorer 1.17 and Fatal Arena 3D;
  62.734375 MiB free; SHA256
  `de2cf3bcfb69e08f18d942289a8b8187e10078d4ad5cb0f177b5a34cb50c185c`.

Both cards were copied to `/media/fat/games/NGage/`, synced and fully re-read
with matching SHA256. The 256 MB native cold boot reproduces Main. The 64 MB three-installer cold
boot reaches FExplorer Installer information/confirmation, with zero final
save queue and no kernel panic/save errors over480 snapshots. Linux MMC FD
points to the intended64MB image (observed position98816 during startup).
No installer confirmation, date key or startup firmware patch was sent.
The phone is left running at this prompt with the64MB card mounted. These are MB-sized cards, not 64 GB.
Capacity, cluster size and collection size differ between controls; a success
would narrow the investigation without independently proving which factor matters.

This is a successful native read/installer-discovery observation, not completed
installation or a full filesystem/capacity qualification. Package count/content
and capacity both changed between256MB/all383 and64MB/three. A same-three-file
256MB comparison would isolate capacity more directly; do not assert an original
phone capacity limit or a broken large-block stream from these results alone.
