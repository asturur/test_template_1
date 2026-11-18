# ARM game PCM

## Stock firmware over the UPP DSP link

Game PCM resource `0xe8` belongs to the UPP's internal DSP at Phonet device
`0x7c`, object 1. The separate D550 music DSP uses device `0x78` on the
MADI serial transport. The original NOS router learns the internal route
from the MDI `0xd0/04` announcement and selects media `0x12`. Its
`0x515bf06c` callback queues the captured Sega Rally start, first-buffer
and stop frames for native MDI send task 4. The TX task swaps the Phonet
length to big-endian before publishing the frame to the shared ring.

With the experimental game PCM build option, the UPP MDI responder now
accepts those stock frames. It validates the two nonoverlapping SDRAM
halves within the pages mapped by `audio.ldd`, hands their addresses and
frame lengths to the existing PCM player, and sends start, refill and stop
responses through the native D2M ring and IRQ10. The 8 and 16 kHz mono
stream uses the same 48 kHz output and SDRAM arbiter as the diagnostic
player. The diagnostic register interface remains available for its
existing test. Native playback completion uses the MDI link.

`tests/phone/game_pcm/stock_route.py` runs the original name lookup, D0
registration, off-device route, MDI send callback and original return
route to task `0x2c`. The media pointer array, scheduler and pool are
fixture boundaries. `tests/phone/native_mdi/run.sh` runs the original ARM
ring write, receive and availability routines on the HDL CPU. Its authored
caller exercises signed playback from both halves, reply framing, stop,
restart and the RF request on the same link. Both wait profiles passed,
at 78,933 and 90,585 CPU clocks for wait 0 and 3. The production PCM/MMC
fixture passed with 64 sample reads, including one while MMC was active.
Routed timing and a full Sega Rally run on MiSTer with the original firmware
are still unverified.

## Original NEM-4 stream

Sega Rally ran from a private copy of its 16 MB card under the reference
NGVM kernel. The game and ROM MediaServer, audio stream plug-in and SoundDevice
ran their original code. Pressing OK on the game's title screen produced
non-silent menu audio. `SoundDevice.mda` is at `0x505b0010` in the checked ROM.
The direct copy call at `0x505b2d36` uses the descriptor bytes, byte count and
selected shared half. The other branch upsamples into that same destination.
The original `audio.ldd` contains the physical base `0x0a061000`.

In the 55-second capture, the original guest sent one `0xe8/20` with
half addresses `0x0a061000` and `0x0a063bc0`, capacity 5,600 samples per half
and rate code `0x46`. It submitted 720 signed mono samples per buffer at
16 kHz, first with `0x23` and then with `0x27` for 954 refills. The reference
answers these with `0x24` and `0x28` and sends `0x26` to request a half.
The PCM requests were on unit 0, sending object `0x4c`. The `0x0b/14`
parameter requests came from object `0x4e` on the same unit. These object
values are from the captured session. With only the first-buffer reply
suppressed in a separate run, SoundDevice used `0x23` on every submission
and still produced non-silent audio. The dated NGage2 donor uses `0x23`
and its captured object numbers differ.

The two handles belong to `MediaServerStub`. Both post their first receive
before the first stream start, with the volume handle also sending `0x0b/00`
at initialization. The bridge leaves those requests in the stock driver.

## Playback candidate

`ngage_game_pcm.v` adapts the donor `upp_haudio` at `6e80660` to Verilog-2001.
The software register window is at physical `0x0c1f0000`. Its two buffers
are fetched from handset SDRAM through the same arbiter as LCD and general
DMA. Completion uses W1C DONE bits and the IRQ input at source 5. The
separate hardware timer producer retains its own status and FIQ path.
The output drives signed 16-bit MiSTer L/R. Both channels use the donor's
48 kHz interpolator.

At 78 MHz the donor bench checks aligned and split-word stereo, mono,
gain, playback rates, restart during reads, delayed memory and underrun.
It also passes with 32,000 non-silent samples from the original Sega Rally
capture. Its exact frame reference and resampler checks pass and emit a
48 kHz stereo WAV. The authored ARM integration sends 64 distinct-channel
stereo words through the production device and SDRAM route. It observes
signed L/R and reads the completion at ICU source 5, then clears it through
the PCM status register. One PCM read completes while native MMC is active
in that fixture. A separate mux test checks ownership under all three
requesters. The first prototype used default-low interrupt ports. That run
produced PCM while the guest still read source 5 as inactive. The candidate
uses explicitly driven ports and a compile-time enable at each boundary.

## Native NOS bridge

The NEM-4 4.03 patch changes the target word at `0x516c7ac0`. Its entry
checks the return address from the stock `DoControl(4)` send callback
at `0x514a17cc`. The other caller dispatches to the original router.
The playback handler checks the registered channel and validates mono
buffers in the fifteen audio.ldd SDRAM pages before starting. The running
stream also checks the source object for refills and stop.

Replies reenter the stock router with a native little-endian length and
the ADSP source address. The original driver still owns the posted receive,
descriptor copy and completion. DONE takes the original `IrqTimer5` entry.
Its interrupt acknowledges the device and uses a native TDfc to publish
work to the stock NOS work ring. The playback bridge runs this work in the
same NOS context as send callbacks.

The exact-ROM ARM fixture executes the send callback, the original reply
router through local task dispatch, original kernel IRQ binding and
dispatch, TDfc Add, and the native work-ring dispatcher. The fixture seeds
the boot-created interrupt name table and registry. Pool allocation, task
enqueue and IRQ-return scheduling are fixture boundaries. It checks reply
headers, the other thunk caller, coalesced refills, stop/restart, final-buffer
stop and closed-channel cleanup. The separate stock ABI fixture executes
the original mailbox pump, short-descriptor retry and cancel.

Sega Rally ran the same stream state machine with its original MediaServer
and SoundDevice under NGVM. Its Exit produced a final buffer and stop
response. A scheduled AppRun relaunched the original game in the same guest,
and both launches produced nonzero PCM. That test uses NGVM's audio FIFO
and completion transport.

A physical control on the installed `1928aee` bitstream observed the
original game send `0xe8/20` and `0xe8/2a` through this callback on unit
`0x14`, sender object `0x4c`. It confirmed the 16 kHz start format,
two exact SDRAM addresses and native little-endian message length.
The bridge acknowledges a correctly formed idle stop with zero bytes
and leaves the interrupt unbound until a supported start.

A second control returned only start and stop replies through the
original NOS route. The real SoundDevice submitted **119 first buffers**
after 119 start replies. Every first buffer described 720 samples.
The 118 stop replies also returned success from the stock router. This
control used the installed bitstream and exercised guest receive delivery.
It had no PCM engine or output capture.

The private patch builder verifies both original service inputs and the
primary MD5, changes the pointer and a formerly erased payload page, and
updates the expected digest while retaining the original checksum bounds.
The generated installer operates on volatile MiSTer DDR with the cold CPU
held and validates the whole image before and after. Reloading restores the
stock firmware. The private firmware, patch artifacts and game image stay
under `build/`.

## Fit and board capture

The CI option **Include experimental game PCM** selects
`NGAGE_GAME_PCM` during elaboration. With the DDR debugger enabled, a
65,536-frame ring records the signed stereo core output at 48 kHz, before
the MiSTer HDMI and analog paths. The ring publishes its completed head
and a loss count. It separately latches whether any nonzero output sample
coincided with MMC activity and LCD DMA. These are whole-session flags.
Take a screen capture at each game transition to identify the rendered scene.
The ring is nonblocking and its reader rejects overwrites and dropped frames.

Both fits used the same `3449395` source, Quartus 17.0.2, seed 42, DDR debug,
the physical 78 MHz PLL, and the same production BRAM. The PCM macro is the
only effective configuration difference. Both pass the 16 SDRAM DQ
input/output/output-enable register checks.

| Fitted result | PCM off | PCM on |
| --- | ---: | ---: |
| ALMs | 37,647 | 38,057 |
| Placed ALMs | 39,259 | 39,558 |
| Occupied LABs | 4,142 | 4,149 |
| Registers | 42,423 | 42,915 |
| M10Ks | 514 | 514 |
| DSPs | 41 | 46 |
| Worst setup at 78 MHz | −0.868 ns | −1.598 ns |
| Worst setup at 104 MHz | −4.073 ns | −4.803 ns |

The 104 MHz figures reuse the routed netlists with an alternate constraint.
The worst 78 MHz PCM-on path launches from the CPU memory address register
into UPP CPU block control. Both builds miss the 78 MHz timing gate. The
PCM-on archive is available for diagnostic use.
[PCM off fit](https://github.com/asturur/test_template_1/actions/runs/44324809548) ·
[PCM on fit](https://github.com/asturur/test_template_1/actions/runs/44324813605).

On the first fitted-board run, Sega Rally stalled at its legal splash. PC
samples alternated between the original interrupt dispatcher and the PCM ISR.
ICU current returned 6 (source 5) while the PCM DONE register returned zero.
The fitted source combines the legacy timer-5 pending latch with PCM DONE.
The bridge now acknowledges that latch by writing back the read timer status,
which retains the value read by polling firmware. It leaves the latch to a
FIQ user if FIQ 5 is enabled and suppresses its IRQ until the next supported
start. The ARM fixture checks the timer-only path, combined completion,
FIQ ownership and restart after the mask clears. This is a firmware change
on the same fitted RTL.

The corrected native firmware booted and played the original Sega Rally
menu and Desert race on the PCM-on artifact. The 48 kHz menu recording has
42,226 nonzero frames out of 48,000, with signed values from −13,758 to
15,645. The first race countdown recording has 20,962 nonzero frames.
The LCD DMA overlap flag was set. The recorded signal is the core's digital
output before the HDMI and analog paths.

The original task switcher closed Sega Rally. A one-second capture after
its exit contained 48,000 zero frames. Relaunching the original game on the
same running core gave 39,839 nonzero frames in the mode menu. The recorder's
sample index advanced through exit and relaunch without a core reload.

FExplorer copied the 1,316,762-byte replay sound asset on the separate
test card. Linux FAT readback found the exact bytes and matching FAT copies.
The game went silent when switched out. The physical recorder did not
observe nonzero PCM overlapping external MMC traffic in these runs.
The production-RTL ARM fixture still confirms one PCM SDRAM read during
active MMC.

[Machine evidence](evidence/game-pcm-20261118.json).

## Reproduction

Run the integration with a new output name. Run the capture using a private
hash-matching card and the existing local firmware and reference tooling.
Logs, game media and generated WAVs stay under ignored `build/sim/`.

```sh
python3 tests/phone/game_pcm/integration.py game-pcm-board
sh tests/phone/native_mdi/run.sh
docker run --rm --pull never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work -e PYTHONPATH=/work/build/tool-cache/linux-unicorn/site \
  --entrypoint python3 jotego/simulator:arm64 -B tests/phone/game_pcm/stock_route.py
python3 tests/phone/game_pcm/replay.py game-pcm-sega --mmc /path/to/sega-rally.mmc
python3 -B tools/build_game_pcm.py build/firmware-overlays/game-pcm
docker run --rm --pull never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work -e PYTHONPATH=/work/build/tool-cache/linux-unicorn/site \
  --entrypoint python3 jotego/simulator:arm64 -B tests/phone/game_pcm/native_abi.py \
  build/firmware-overlays/game-pcm build/firmware-overlays/game-pcm/window-dec.bin
```
