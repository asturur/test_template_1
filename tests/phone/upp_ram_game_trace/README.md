# UPP RAM game trace

The replay measures guest physical program-space accesses to the DSP upload
window `0x0c030000–0x0c03ffff` and raw UPP RAM
`0x0c1003f0–0x0c10ffff`. It also counts the guest-facing MDI rings, pointers
and control register. The read and write taps leave guest values intact.

Use the local N-Gage-enabled build of MAME 0.289
(`mame0289-2410-gddbf0bd899b-dirty` in the recorded run) with the ARM920T
interpreter. The [recorded result](../../../docs/evidence/v5-upp-ram-game-traffic-20261122.json)
lists the executable, driver and ROM archive hashes. The runner defaults to
`~/develop/mame/ngagetest` and its adjacent `roms/`. Set `NGAGE_MAME` and
`NGAGE_MAME_ROMPATH` for other locations. Calibration uses
`arm-none-eabi-gcc` and `arm-none-eabi-objcopy`. The JSON summarizer uses
Python 3.10 or newer and Pillow.

Provide private copies of stock Sega Rally Championship and SonicN MMC
images and prepared MAME profile directories with `cfg/` and `nvram/`.
Sega Rally uses NEM-4 4.03 with Test SIM, initialized C: and the Sega Rally
icon reachable by the recorded Menu actions. SonicN uses QD 4.10 with Test
SIM, initialized C: and the Phone screen's Game soft key. Both profiles
use the default 104 MHz ARM clock. The keypad scripts account for the
startup time and date prompts. A different C: app layout or startup
sequence can require adjusting the timed inputs in `trace.lua`.

From the project root, set `SEGA_PROFILE`, `SONIC_PROFILE`, `SEGA_MMC` and
`SONIC_MMC` to the input paths. Each run creates a new directory and uses
its own profile and card copies.

```sh
test_dir=tests/phone/upp_ram_game_trace
trace_dir=build/upp-ram-game-trace-replay
mkdir -p "$trace_dir"
"$test_dir/run.sh" calibration "$trace_dir/calibration"
"$test_dir/run.sh" sega "$trace_dir/sega" "$SEGA_PROFILE" "$SEGA_MMC"
"$test_dir/run.sh" sonic "$trace_dir/sonic" "$SONIC_PROFILE" "$SONIC_MMC"
python3 "$test_dir/summarize.py" "$trace_dir" > "$trace_dir/summary.json"
```

Calibration runs guest 32-bit loads and stores at the lower edges,
halfword stores and byte loads at the upper edges, and a `BX LR` from
each window. The run checks the observed address, mask and direction
for each operation and checks a guest-written completion word.

The replay saves per-phase access counts and first and last emulated
timestamps in `accesses.tsv`. Check the late screenshots for a changing
Desert race in Sega Rally and a changing beach level in SonicN. The
`SNAP` lines in `trace.log` report cumulative nonzero pre-mixer samples
from MAME's PCM device. That signal is emulated audio. The ARM interpreter
does not model caches or FPGA RAM timing. The MAME driver models the MDI
protocol and keeps its internal ring updates outside the tap. Its
modeled MMC and LCD DMA and PCM sample buffers are restricted to SDRAM.
