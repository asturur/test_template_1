# Super Monkey Ball on the 5F MiSTer build

On 17 November 2026 the operator identified the running build as 5F. The recorder reported tag `261117`, 78 MHz and reset generation 2 throughout. MiSTer had `games/NGage/super-monkey-ball.mmc` open. One screenshot showed the Floor 01 introduction. A screenshot at the start of the operator-confirmed play window showed Floor 01 with the ball moving at 005 km/h and the countdown at 007:64. Transitions after each screenshot are unlabelled. Capture used passive DDR diagnostics and screenshots without input or reload.

## Where the front end spent time

Each percentage is the fraction of all valid snapshots in that window whose last fetch PC fell in the indicated loop. The names describe the operations inferred from the game's ARM instructions.

| Observed app loop | Initial capture, 399 | Second capture, 258 | Confirmed play start, 239 |
|---|---:|---:|---:|
| Sample and write a 16-bit pixel | 153 (38.3%) | 89 (34.5%) | 28 (11.7%) |
| Convert packed pixel channels | 32 (8.0%) | 19 (7.4%) | 42 (17.6%) |
| Fill 32 bytes per iteration | 19 (4.8%) | 8 (3.1%) | 20 (8.4%) |
| **Combined** | **204 (51.1%)** | **116 (45.0%)** | **90 (37.7%)** |

The mix changed even within the last window. In its first half the span loop appeared in 25 of 119 samples and conversion in 8. In the second half those counts were 3 and 34 of 120. A gameplay average will depend on the scene and transitions.

- **Span, code offsets 0x93e38–0x93e84 inclusive.** A 20-instruction ARM loop advances a fixed-point coordinate, computes a source address with MLA, reads two adjacent bytes, combines them and stores one halfword. Six LDRs read stack slots per iteration, including the bound just before the compare and backward branch. The halfword destination uses a register-offset address without post-index writeback. This is a concrete case where the specific 5F post-index store improvement has no direct match in the hot loop.
- **Packed conversion, 0xa3814–0xa3848.** A two-register LDM reads eight bytes, shifts and masks rearrange channels, and a two-register STM writes eight bytes. The loop includes a decrement and conditional back edge.
- **Fill, 0xa31a0–0xa31a8.** An eight-register STM writes 32 bytes, followed by a decrement and conditional back edge. This exercises the block-transfer path.

## Executable and attribution

The local, Git-ignored benchmark input is `tests/cpu/super_monkey_ball/local/SuperMonkeyBall.app`. It contains 793,068 bytes, UID3 `0x101fb883`, SHA-256 `d43052bebaed6401bd8a1482b5a2072022b2d0ff3ac7d6f538be860f0d5ddd77`. It was read from the mounted SD share at FAT short path `/SYSTEM/APPS/SUPERM~1/SUPERM~1.APP`. The checkout holds no copy of the whole card from this investigation.

The E32 code starts at file offset 0x7c and spans 0xbd718 bytes. The preferred code base in the header is 0x10000000. Aligning distinct sampled PC/instruction pairs to the file gives a runtime code base of 0xfff00000. Of the 239 final samples, 193 had PCs in that range. Of those, 132 matched the file word exactly at the reported PC, 54 matched the following word and 7 are range-only. Another 44 PCs fell in the firmware ROM window and 2 elsewhere. The table uses PC ranges independently of word matching.

The hardware records the instruction address bus and returned instruction data on its debug fetch signal. Pipeline overlap allows adjacent-word observations. Branch PCs can remain visible while other work completes. The samples measure front-end location at 250 ms intervals. They do not establish branch penalties, retired IPC, frame boundaries or FPS. Elapsed core time between first and last snapshots was 99.5, 64.5 and 59.5 seconds respectively. The second capture missed one sequence. The three sequence ranges are disjoint.

## First offline benchmark

Use the original span loop first. Run a fixed number of pixels with bounded source and destination buffers, original stack inputs and an independent reference for byte selection, output values and untouched guards. Compare identical work on 5F and the next candidate. Report cycles per output pixel and instruction count, then inspect load-use waits, MLA dependencies, store admission and back-edge delivery in simulation. The block conversion and fill loops provide two further candidates if the first cannot explain gameplay results. No loop replay or game FPS measurement was performed in this capture.

[Per-window PC histograms and counter deltas](evidence/super-monkey-ball-5f-20261117.json) · [5F integrated measurements](cpu-integrated-5f.md)

The subsequent [Step 5I offline replay](super-monkey-ball-span.md) validates the
original span with two bounded synthetic patterns, measures warm cycles per
pixel, and records its load/store/MLA schedules and next-experiment decision.
