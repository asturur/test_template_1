# CRT left-edge pixel corruption — 2026-11-13

The user's missing left white margin has a reproducible digital cause. The
LCD RAM reads ahead while the current raster coordinates and CE remain held.
`ngage_mister` previously copied that live RGB value on every system clock.
For most of each odd pixel period, the analog output therefore selected the
same halfword from the next pixel pair. A two-column white left border loses
most of its second column; this is not missing framebuffer storage.

The original implementation fails the continuous-output regression at raster
73,16 (native pixel1,0): RGB004400 instead ofFFFFFF. Across a full78MHz/div12
frame,199056 system-clock samples are incorrect. Existing native CE-qualified
scanout checks miss this because RGB is correct at the intended sampling edge.

## Fix and cost

Enable the existing12-bit `video_pixels` output register only on `raw_ce`.
It then holds the correct pixel for the full period. Existing sync/blanking
registers, pixel CE phase, framebuffer format and dimensions are unchanged.
No new register or RAM instance and no new pipeline stage are added. This is
an enable on an existing register; fitted cost and timing have not been measured.
PLL remains78MHz and104MHz stays the design target.

This corrects the outgoing digital RGB waveform. It does not establish actual
CRT geometry or explain every HDMI symptom. No porch/centering adjustment is
included; hardware confirmation with the screensaver is still required.

## Regression

Run `sh tests/phone/crt_output/run.sh` inside the existing offline simulator
image. It extracts the actual production output-register block verbatim from
`rtl/ngage_mister.v`, drives it with the real LCD framebuffer scanout, and uses
stock MiSTer `scanlines` and `vga_out` blocks. The fixture checks every system
clock, all176×208 pixels, first/last two columns, black blanking, and sync/DE
alignment, at div12 and div16 (78/104MHz production pixel ratios). It runs a
symmetric two-column white-border pattern and a distinct-column coordinate
pattern. The disabled OSD and sync-polarity adjustment are outside this fixture;
physical DAC, cable and monitor behavior are not simulated.

The before-source snapshot and logs are retained under
`scratch/crt-pixel-hold-20261113/`. The runner accepts `CRT_SOURCE` and `CRT_OUT`
for a negative control without editing maintained RTL. Production top structural
elaboration and the existing native CE/DE pixel test are separate checks.

Both patterns pass at both ratios:1,257,600 checked system clocks per pattern
at div12 and1,676,800 at div16,36,608 active pixels each. Each first/last
two-column edge contributes4,992/6,656 checked clocks respectively. The native
CE/DE test, production top structural elaboration and pinned formatting pass.
[Source hashes and results](evidence/crt-pixel-hold-2026-11-13.json).

## Additional user observation: HDMI-only pair ordering

The user reports adjacent columns appear swapped (hilo/lohi) on HDMI while CRT
column order looks correct. This is recorded separately in
[TODO.md](TODO.md#display-output-follow-up-2026-11-13); it is not a confirmed
remaining cause or a completed hardware retest of6a23a15.

`sys_top.v` feeds both paths from the same core RGB and stock scanline pipeline.
HDMI's `ascal` input uses `vga_data_sl` with `vga_ce_sl`; `ascal.vhd` registers
pixel, DE and CE together before CE-qualified processing. Unscaled CRT instead
continues through the OSD and continuous-clock analog pipeline. Neither branch
has an explicit phone halfword-order selector. The previously demonstrated
between-CE RGB corruption is a possible explanation for differing appearances,
not proof that it accounts for this report. First retest the hold fix, then
locate any remaining divergence at scaler sampling/packing/line readback rather
than changing shared framebuffer order based only on the HDMI appearance.
