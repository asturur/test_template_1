# UPP RAM latency and reset replay

## Retained RTL and workload

The two candidates are the 64 KiB upload window at `0x0c03xxxx` and the
64 KiB generic NOS backing at `0x0c10xxxx` in `53b707b`. The registered UPP
peripheral boundary selects the raw banks. A claimed MDI transaction uses the
local ring and pointers at aligned addresses `0x0c100000..0x0c1003ec`, or its
control register at `0x0c14b004`. The first raw NOS word is `0x0c1003f0`.
The auxiliary DSP upload at `0x0c06ff00` uses a separate bank. The passive ICU
and timer storage and the keypad state have their own address-qualified effects.

The test fixture substitutes an independent 64-bit, byte-enabled storage model
behind one or both raw banks with a programmable blocking wait per accepted
read and write. The model uses the UPP response and byte-enable checks, one
transaction at a time, with acknowledgment after the wait. The sweeps add
8 read and 4 write clocks, or 48 read and 24 write clocks. These are sensitivity
points. The model serves the flash port with the existing independent peer.
HPS arbitration, HPS contention and real DDR return times require separate
measurements.

The workload runs the retained ARM9V2, card host and DMA, the LCD client and
SDRAM scheduler with a Micron SDRAM pin model, and the shared PCM player.
An authored ARM caller uses the diagnostic stereo PCM registers, submits a
128-sample buffer, renders a frame and writes and reads back an MMC sector.
The stress variant additionally checks 128 addresses in each raw bank with
one zero read, one word write, one partial write and one merged read per
address. It submits one MDI pointer read. The stress transfers all overlap
both PCM playback and LCD DMA. Between 39 and 74 also overlap the MMC
host-write acknowledgment window.

## Mixed LCD, MMC and PCM results

An idle raw RAM control reproduced the archived mixed completion at
1,189,662 clocks with BRAM, upload modeled, and NOS modeled. All three runs
made zero accepted accesses to either bank. The authored stress issues 256
reads and 256 writes per bank. Upload valid write lanes cover 640 bytes
(word plus byte), and NOS lanes cover 768 bytes (word plus halfword).

| Stress variant | Upload hold clocks | NOS hold clocks | First to last raw transfer clocks, inclusive | End clocks |
| --- | ---: | ---: | ---: | ---: |
| BRAM | 0 | 0 | 38,569 | 1,189,648 |
| Upload +8/+4 | 3,072 | 0 | 41,378 | 1,189,664 |
| NOS +8/+4 | 0 | 3,072 | 41,385 | 1,189,664 |
| Upload +48/+24 | 18,432 | 0 | 56,698 | 1,189,664 |
| NOS +48/+24 | 0 | 18,432 | 56,745 | 1,189,664 |
| Both +48/+24 | 18,432 | 18,432 | 74,874 | 1,189,680 |

Each run produced 128 PCM samples with hash `175ee178` at output ticks
914,114 through 1,189,281, no underruns or overwritten requests, 18,304
correct LCD words and all 512 written MMC bytes intact. At +48/+24 active
sample ticks occurred during eight upload waits, nine NOS waits and seventeen
combined waits. The matching audio timing and near-neutral whole-test
completion reflect the fixture's independent PCM/LCD progress. They do not
make the CPU wait free. A guest on the critical path could see the full delay
of each serialized raw access. The waveform result covers the shared output
engine. Stock game audio uses MDI to submit SDRAM buffers, and the MDI
transport has a different caller and completion path. See
[stock PCM routing](game-pcm.md#stock-firmware-over-the-upp-dsp-link).

## Reset and startup checks

A separate registered UPP test passed with BRAM, either bank modeled alone,
and both modeled. It checks high and low addresses, independent banks and
32-bit halves of a 64-bit beat, valid lane masks `1/2/4/8/3/c/f`, rejection
of mask `5`, the independently reset MDI pointer, the local auxiliary
window, an unaccepted write withdrawn during warm reset, retention of
completed writes across warm reset, and a second cold clear of dirty words.

The retained cold initializer covers 16,384 32-bit words per bank in parallel.
The test model clears 8,192 unique 64-bit beats per externalized bank, one
per clock, with the existing initialization gate. Its raw counters include
four repeated beats or words while cold reset holds index zero. A real
shared port must clear both regions in 16,384 accepted beats. At 104 MHz
this is 0.158 ms at one accepted beat per clock, or 0.210 ms at 78 MHz,
before port command overhead and stalls. With one bank the raw transfer
takes 0.079 ms at 104 MHz or 0.105 ms at 78 MHz under that same assumption.
One bank has room to overlap its clear with the existing 16,384-clock local
sweep. Preserve init gating until all zero writes complete and keep warm
reset independent.

The stock NEM-4 ARM9V2 HDL cold trace runs 100,000,000 clocks at 104 MHz
with production flash transport, 32 KiB flash cache, 64 Hz NOS timing,
26 MHz timers, default MMC divider 4, no SIM and the stock PCM path. The
Nokia framebuffer completed at clock 32,622,444. The trace ended at
`0x50004024` in the firmware MD5 transform with 18,353 LCD data writes
and zero data faults. The observer registered zero accepted raw upload
reads or writes, zero raw NOS reads or writes and zero MDI transfers in
this prefix. This prefix did not reach the DSP upload, the NOS app grid or
gameplay.

The older boot record documents DSP upload after the clock units initialize.
The archived ownership section at `5a65948:docs/peripheral-ownership.md`
records 36,248 upload image bytes at offsets `0x0100..0x8e97` matched
against decoded flash. The whole-system NEM-4 MAME trace independently
records 18,124 halfword writes across that range. Applying the replay's
four- and 24-clock write delays to those transactions would add 0.70 ms and
4.18 ms at 104 MHz before any overlap, coalescing or flash contention.
The shared-DDR service experiment models a separate range of costs.
[Historical startup record](status.md#2026-10-31-night-nos-startup-running-live-mtc-traces-captured-asic-rom-service-wall-stubbed) ·
[Guest access trace](evidence/v5-upp-ram-game-traffic-20261122.json) ·
[DDR assessment](peripheral-ram-ddr-assessment.md)

## Reproduction

Use the existing `jotego/simulator:arm64` and local ARM assembler. The
baseline mixed pin replay requires the adapted Micron model at
`build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v`.
The [existing SDRAM harness](../tests/phone/hardware_boot/run-real-sdram.sh)
documents the model adaptation. The generator verifies its hash.
The historical pin-replay changes are stored as test fixture patches against
`53b707b`. The generator rebuilds the synthetic card and both programs
and materializes exact retained HDL inputs plus the fixture substitutions
under `build/sim/upp-ddr3-impact/mixed/`.

```sh
python3 -B tests/phone/upp_ddr3_impact/prepare.py mixed
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work --entrypoint /bin/sh jotego/simulator:arm64 -ec '
    sh build/sim/upp-ddr3-impact/mixed/reset.sh
    sh build/sim/upp-ddr3-impact/mixed/build.sh
    sh tests/phone/upp_ddr3_impact/run-matrix.sh'
```

The passive boot observer is a separate harness. It uses the local
hardware boot runner with its stock PCM and flash-cache-size options.
The evidence records the exact compiled sources and boot-input hashes.

```sh
python3 -B tests/phone/upp_ddr3_impact/prepare.py boot
python3 scratch/upp-ddr3-impact/run-logo.py \
  --name upp-ddr3-impact-cold-104-repro --cycles 100000000 \
  --timer-clock 26mhz --nos-tick-hz 64 --line-refill --production-ddr \
  --flash-cache-bytes 32768 --stock-game-pcm --cdrive runtime/boot/cdrive-11b.img
```

[Machine-readable results and provenance](evidence/upp-ddr3-rtl-replay-20261122.json)
