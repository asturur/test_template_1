# ARM game PCM

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
router through the local task dispatch, the kernel TDfc Add and the native
work-ring dispatcher. Pool allocation, IRQ registration and task enqueue
are fixture boundaries. It checks reinjection headers, one passthrough
from the other thunk caller, refills, explicit stop/restart, final-buffer
stop and closed-channel cleanup. The separate stock ABI fixture executes
the original mailbox pump, short-descriptor retry and cancel.

Sega Rally ran the same stream state machine with its original MediaServer
and SoundDevice under NGVM. Its Exit produced a final buffer and stop
response. A scheduled AppRun relaunched the original game in the same guest,
and both launches produced nonzero PCM. That test uses NGVM's audio FIFO
and completion transport. Full native firmware boot and the physical
playback run are still to be checked.

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
Run matching 78 MHz seed 42 fits with the game PCM option off and on.
[Machine evidence](evidence/game-pcm-20261118.json).

## Reproduction

Run the integration with a new output name. Run the capture using a private
hash-matching card and the existing local firmware and reference tooling.
Logs, game media and generated WAVs stay under ignored `build/sim/`.

```sh
python3 tests/phone/game_pcm/integration.py game-pcm-board
python3 tests/phone/game_pcm/replay.py game-pcm-sega --mmc /path/to/sega-rally.mmc
python3 -B tools/build_game_pcm.py build/firmware-overlays/game-pcm
docker run --rm --pull never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work -e PYTHONPATH=/work/build/tool-cache/linux-unicorn/site \
  --entrypoint python3 jotego/simulator:arm64 -B tests/phone/game_pcm/native_abi.py \
  build/firmware-overlays/game-pcm build/firmware-overlays/game-pcm/window-dec.bin
```
