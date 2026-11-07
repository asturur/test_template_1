# MiSTer flash and working save

**2026-11-07 firmware-only update:** top-level firmware input is now the original
4.03 service pair: `nem440.3c1` copied unchanged as `boot.rom`, `nem440.326` as
`boot1.rom`. MCU/PPM manual selectors are also available; either order works.
Load both first, then mount the existing `.nga` on S0. C:/PMM layout, save/flush
behavior and S1 diagnostics are unchanged. Both existing seed-profile IDs are
accepted against the verified service pair's unchanged firmware hashes. NGB
creation below remains useful only for creating a disposable NGA or older RBFs;
the new top no longer takes NGB as firmware. Real board validation is pending.
See [service loader evidence and remaining plan](service-firmware-loader-plan.md).

**Phase A result (2026-11-06):** The actual-HPS, NOR/DDR, full-size save and bundle, reset/dirty and concurrent diagnostic-disk simulations pass; see the latest [status checkpoint](status.md). The mount indication is now edge-detected and a clean zero-size unmount is supported. On the diagnostic raster, the save cell is gray when unmounted, amber when dirty, cyan when saving, green when saved and red on error. The operator must explicitly select **Flush working save** and wait for green before treating the image as flushed. Real Main, media and controlled power-cycle verification remain phase B and have not been performed; a sudden power loss may lose unflushed data.

The NGA image is 4,260,352 bytes: header at file offsets `0x000000–0x0001ff` (LBA 0), C: at `0x000200–0x4001ff` (LBAs 1–8192), and PMM at `0x400200–0x4101ff` (LBAs 8193–8320). Mount the separately created working image on S0; S1 is the separate diagnostic disk. Bundle seeds initialize a newly created save only. A mounted save supplies the authoritative C:/PMM bytes.

**Agreed architecture (2026-11-06):** immutable firmware loads into DDR via ioctl; C:/PMM persistence uses a separate writable mounted block device, with DDR retained as fast working storage. See [implementation milestone 6.5](mister-implementation-plan.md#65-verify-firmware-in-ddr-and-writable-cpmm-persistence) for Terra’s simulation and hardware acceptance instructions. Run its simulation phase after milestone 6 and its hardware phase at milestone 9.

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

The current OSD flow is to load both service containers first, mount the NGA working save, and use **Flush working save** after changes. This flow is not yet tested on a real MiSTer. The processor remains held while later board/peripheral milestones are incomplete.

## Verification

The focused test directories under `tests/phone/` cover flash descrambling, C: against both C++ boards, code-flash modes and PMM, dirty tracking, disk handshakes, header checks, sector snapshots, mount/flush/reload and reset deferral. `tests/phone/flash_decode/check_digest.py` verifies the stock firmware MD5 through actual descrambler RTL; `tests/phone/save_manager/run-full.sh` tests full-sized C:/PMM restore and reload with a simulated HPS disk. `tests/phone/save_manager/run.sh` additionally exercises real flash mutations through the DDR adapter, concurrent mutation during flush, invalid images, timeouts and media-change failure. Use `jotego/simulator:arm64`; see `docs/status.md` for commands and results.

## Standard MiSTer block-device contract (2026-11-06 audit)

The C:/PMM working image uses the standard [hps_io virtual hard drives and block devices](https://mister-devel.github.io/MkDocs_MiSTer/developer/hps_io/#virtual-hard-drives-and-block-devices), through OSD `S0`, device index 0. Diagnostic export uses a separate `S1` device. The firmware still sees NOR flash; block I/O is the host persistence transport, not a replacement for guest flash commands or LFFS.

The local interface uses WIDE=1 and default BLKSZ=2: a sector is 512 bytes transferred as 256 16-bit buffer words. Set `sd_lba`, request exactly one block (`sd_blk_cnt=0`), hold the request until its matching `sd_ack` asserts, and wait for it to deassert before reporting completion or reusing the sector buffer. There is no per-word backpressure. The bridge therefore snapshots the complete sector before asserting `sd_wr`; on reads it checks all buffer words arrive in order. Mount metadata is valid with its `img_mounted` event; zero image size is an unmount. Respect read-only mounts, sizes, per-device acknowledgement/data routing and the common clk_sys domain. The guide's byte-oriented wording must be interpreted with the actual local WIDE implementation, which increments the buffer index once per 16-bit word.

Current file layout is custom NGA, not a FAT disk: LBA0 is the save header, LBA1..8192 are 4 MiB C:, and LBA8193..8320 are 64 KiB PMM. Protect the original seed images. Guest program/erase marks changed sectors dirty; an explicit **Flush working save** writes them. This is not automatic write-through persistence. Retain the dirty bit if a sector changes while being saved, and never report Saved on timeout, media change or failed/incomplete transfer. HPS transaction acknowledgement is not a power-loss durability guarantee.

Audit checks passed: `tests/phone/sd_sector/run.sh`, `tests/phone/save_manager/run.sh`, and `tests/phone/diag_export/run.sh` inside the existing simulator image. The last includes actual local `hps_io` mount/LBA/ack/buffer traffic for diagnostic writes (with only the documented test-only PS/2 scope adjustment). Logs: `scratch/mister-block-device-audit/tests.log`. No new firmware simulation, synthesis or hardware write was performed.

**Historical C: acceptance gate (phase A now passed; real-hardware phase B remains):** extend real-hps_io coverage to C:/PMM header/restore, dirty-sector writes and remount, including first/last C: sectors, adjacent PMM boundaries, both virtual devices active, read-only/zero-size mount, delayed ack, media replacement and a mutation during flush. Existing full-size tests use a modeled HPS peer; the actual-hps_io diagnostic test does not validate the complete C: save path. Then repeat with installed MiSTer Main and disposable host image: load, make a reversible guest change, flush, reset/remount and power cycle after Saved, compare resulting image bytes. Do not claim hardware persistence until that passes. If automatic saving is wanted, add and test bounded background dirty-sector flushing separately from this protocol conformance gate.

## Explicit block RAM buffers

Sector buffers and the dirty bitmap use explicit Cyclone V M10K primitives.
Both local and HPS buffer reads have one clock of latency; HPS transfer strobes
are spaced sufficiently by the actual local `hps_io` protocol. The save bridge
prefetches each low/high halfword, and the header validator waits after each
address change. No per-word backpressure or shortened ACK lifetime was added.
Diagnostic snapshots and trace readout are synchronous as well. Actual HPS
save/NOR/DDR and diagnostic-export regressions check this timing; changing the
RAM interface requires rerunning them. See `quartus-memory-audit.md` for the
wrapper, collision handling and resource-validation limits.
