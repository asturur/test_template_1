# Diagnostic video retirement

User requested DDR-only diagnostics before the next FPGA build on2026-11-12,
to reserve area for native startup peripherals. Production `ngage_mister` no
longer instantiates `ngage_debug_video`; Quartus excludes that source, its font
module and font initialization files. The LCD receives a constant Phone-mode
selection, so its diagnostic color/status bars also disappear from synthesis.
The OSD Display selector is removed. Automatic original aspect is always11:13;
previously stored status17 cannot restore diagnostic video.

The existing one-clock RGB/control output register remains. No PLL or raster
frequency change is made: operating clock78MHz, design objective104MHz. The
768-bit observation collector, panic/fault/trace recorder, DDR snapshot/text
streams, SSH readback and export remain. Removing the renderer removes its
separate768-bit video snapshot,99-bit panic snapshot, character selection,
hexadecimal formatting, font and text composition. Exact ALM/BRAM/timing savings
require a Quartus result and are not estimated as measured savings.

The old renderer/font files remain reference material, excluded from production.
The unused diagnostic_video input on ngage_mister is retained for authored
fixture source compatibility; it cannot select a renderer or change panel mode.
No default build option enables the removed path. The board/LCD's standalone
reference fixtures can still exercise their older diagnostic inputs.

Validation is recorded in scratch/hdl-native-startup-20261112/:
renderer-retirement-ddr.log (recorder, DDR and export regressions) and
renderer-retirement-board-cpu.log (integrated CPU/LCD/DMA/IRQ checks).
No Quartus build, CI monitoring or hardware deployment is part of this change.
