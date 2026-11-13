# LCD adjacent-column order — 2026-11-13

The shared scanout emitted the high-address halfword before the low-address
halfword. Native framebuffer words contain pixel x in the low halfword and
pixel x+1 in the high halfword. The old native test concealed this reversal
with `(x-72)^1`; the CRT fixture also loaded artificially reversed words.

Select the low-address pixel first in `ngage_lcd_display.v`. Storage, LCD DMA,
window commands and partial updates are unchanged. Preserve the earlier
CE-qualified output-register hold fix: it fixes a separate between-CE defect.
Both outputs consume this corrected shared source. The user's later report
that both CRT and HDMI are swapped supersedes the earlier HDMI-only report.

This selector inversion adds no register, RAM, pipeline stage or bus clock.
Actual PLL remains78MHz;104MHz is the design target. No fitted resource or
routed timing result exists for this change. Physical HDMI/CRT confirmation
requires the next RBF; the installed b656156 still contains the old order.

## Verification

Run these inside the existing offline `jotego/simulator:arm64` image:

```sh
sh tests/phone/lcd_display/run.sh
sh tests/phone/lcd_display/run-native.sh
sh tests/phone/crt_output/run.sh
sh tests/phone/mister_transport/lint-top.sh
```

The natural-coordinate oracle now expects x directly, without pair swapping.
Old RTL fails at the very first pixel: raster72,16 gives010 instead of000.
The corrected RTL passes every176×208 native pixel. Full protocol/state
comparison retains1,135,723 checks over43,681 row pairs; RGB equality against
the historical reversed reference is intentionally replaced by the independent
native-coordinate oracle.

The production output register plus stock MiSTer scanlines/analog pipeline
passes two patterns at div12 and16: symmetric two-column white borders and
distinct columns. Continuous CRT checks cover1,257,600/1,676,800 system clocks
per pattern; HDMI checks the actual CE-qualified RGB/DE source feeding ascal.
Both paths contain all36,608 active pixels with matching left/right coverage.
The scaler's internal RAM, physical HDMI link and DAC/monitor are outside this
fixture. Top structural elaboration also passes (HPS/PLL stubbed).

Logs and old-source negative control: `scratch/lcd-pair-order-20261113/`.
[Small maintained evidence](evidence/lcd-pair-order-2026-11-13.json).
