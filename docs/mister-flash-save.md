# MiSTer flash and working save

Milestone 3's flash and save paths are connected in RTL, with the phone CPU still intentionally held in reset. This is simulation-tested development code, not a verified MiSTer build or a recommendation to use the only copy of valuable data.

`ngage_codeflash` handles the observed per-chip identify/unlock/burst and PMM status/program operations; lock status is scoped to the addressed 2 MiB bank. Normal array reads use two independently addressed read-side descramblers in the observed physical window. Writes to code-flash locations outside the 64 KiB PMM are rejected: a general mutable code-flash overlay is not yet implemented. `ngage_cflash` takes priority over the overlapping chip-select range and handles the observed x16 C: commands, 64 KiB and top 16 KiB sectors, polling, suspend and reset. Reads and writes use the existing DDR arbiter; dirty bits are set only after actual changed backing words commit. Operations already accepted are drained before flash command state resets.

The C: model deliberately reproduces the current software model's direct halfword assignment, including allowing 0-to-1 changes during programming. This is not established as physical NOR behavior. PMM programs instead use physical-style bitwise AND with the existing seed, including on the first write; the software overlay's first PMM write ignores the seed. This difference requires investigation against firmware and real flash evidence. Unsupported commands return an error, not fabricated success.

The save manager mounts a separate, pre-created `.nga` working image, checks its exact size, writability, header CRC, profile and stored core/extension SHA-256 values, restores all 4 MiB C: and 64 KiB PMM, and holds the CPU until restore and other boot gates complete. A user-requested flush snapshots dirty 512-byte sectors to the virtual disk. Writes that overlap a snapshot remain dirty and trigger another pass. Phone reset requests are deferred while a save/restore is active; flash writes drain while the phone resets. Replacing mounted media while data is dirty or during I/O reports an error and retains DDR data rather than writing it to the newly mounted image. The code cannot prevent external reconfiguration or power removal.

The FPGA currently identifies the audited core and extension by their validated CRC-32 values and compares the save header to the corresponding compiled-in SHA-256 values; it **does not calculate SHA-256 over firmware in hardware**. CRC-32 detects common corruption but is not cryptographic identity. Only the audited factory core/extension profile is enabled for save mounting. Read-only or wrongly sized images, mismatched/corrupt headers, incomplete sector reads and timed-out HPS operations are rejected. The controller requires all 256 halfwords of each sector read in order; this and the HPS request/ack timing have been tested against a model, not MiSTer Main running on hardware.

No journal or atomic power-loss recovery is implemented. HPS acknowledgement is not proof that storage is durable. A failed/uncertain flush is reported and leaves unsaved contents in volatile DDR, but automatic recovery/export of those contents is not implemented; do not reset, reconfigure or power off if preserving them matters. Keep backups of the working image. Replacing a bundle while a save is mounted is blocked; after confirming a save, restart and load the next bundle. The LED is solid when mounted and saved, blinks slowly while loading/saving, blinks quickly on an error or blocked bundle load, and is off when not mounted/saved. Actual Main OSD and LED behavior still require hardware verification.

## Prepare disposable inputs

These commands create new files and fail if either output already exists; they never replace the original inputs. Use `diagnostic-seeded-pmm` for the separately documented synthetic seeded PMM profile.

```sh
python3 tools/prepare_mister_images.py --profile diagnostic-erased-pmm --output scratch/working.ngb
python3 tools/prepare_mister_save.py create scratch/working.ngb scratch/working.nga
python3 tools/prepare_mister_save.py inspect scratch/working.nga --bundle scratch/working.ngb
```

The intended OSD flow is to load the NGB bundle first, mount the NGA working save, and use **Flush working save** after changes. This flow is not yet tested on a real MiSTer. The processor remains held while later board/peripheral milestones are incomplete.

## Verification

The focused test directories under `tests/phone/` cover flash descrambling, C: against both C++ boards, code-flash modes and PMM, dirty tracking, disk handshakes, header checks, sector snapshots, mount/flush/reload and reset deferral. `tests/phone/flash_decode/check_digest.py` verifies the stock firmware MD5 through actual descrambler RTL; `tests/phone/save_manager/run-full.sh` tests full-sized C:/PMM restore and reload with a simulated HPS disk. `tests/phone/save_manager/run.sh` additionally exercises real flash mutations through the DDR adapter, concurrent mutation during flush, invalid images, timeouts and media-change failure. Use `jotego/simulator:arm64`; see `docs/status.md` for commands and results.
