# v5 and ngage2 frame-path comparison

The reported native SPMark04 Game results are **5.79 fps on v5** and
**6.62 fps on ngage2**. At exactly 78 MHz they imply **21.65 ms** or
**1,689,025 clocks** more per frame on v5. The user confirmed the
installed files use the current 78 MHz branch tips. Independent native
frame times remain open.

The stock ngage2 SDRAM path drained the same captured GLES fill stream
2.11× as fast as v5. The firmware and CPU are outside that matched
memory replay. A separate original-code fill through the two CPU and
memory paths showed almost exactly the same elapsed difference. The
native benchmark may also differ in firmware work, OS scheduling and
display traffic. No measured proxy event counts can yet be assigned to
the native Game frame.

> [Plan](arm9v2-donor-frame-gap-plan.md) ·
> [Raw counters, source hashes and timings](evidence/arm9v2-donor-frame-gap-20261119.json)

## Installed RBFs and firmware

| MiSTer file | Reported Game fps | Installed firmware | Build identity |
| --- | ---: | --- | --- |
| `ngage1.rbf` | 5.79 | NEM-4 4.03 | Exact hash match to v5 `8546db1`, seed 43, debugger off |
| `NGage.rbf` | 6.62 | RH-29 4.10 | User-confirmed `test-78` tip `ff6dcff`. Fitter seed unverified |

The v5 artifact is the exact simulation source baseline. Its archived
timing report shows −0.185 ns worst setup slack and +0.248 ns hold slack
on the system clock. CI produced the RBF and failed its timing gate.
The donor installed hash differs from the archived `6e80660` 78 MHz
build, the later stock master artifact, and the November 16 release.
The user identified the donor RBF as the current 78 MHz revision, and
the local and GitHub `test-78` tips both resolve to `ff6dcff`, the
simulation source. The source difference between `6e80660` and `ff6dcff` is an MMC receive FIFO clock-hold fix and
its test, so these two source revisions share the CPU and SDRAM logic.
The two installed firmware pairs match the known factory file hashes.
These are file identities from the mounted SD card. The reported Game
results still need independent render and display interval counters.
[Installed file hashes and comparison artifacts](evidence/arm9v2-donor-frame-gap-board-20261119.json).

## Original-code rendering proxies

All clocks are at 78 MHz. V5 is `8546db1` with two-way 16 KiB per side,
32-byte lines, XOR-selected data section TLB, 32 KiB D2, 39 MHz MMC and
a 64 Hz NOS counter. Stock ngage2 is `ff6dcff` with two-way 16 KiB I/8 KiB
D, 16-byte lines, direct section TLB and 128 KiB flash backing. Both
execute the same hash-checked guest bytes and original NEM-4 helpers
over their own CPU, flash and physical SDRAM RTL. The donor test connects
the DDR and SDRAM peers directly to its production memory block. The
Sega proxy executes the original FbsCli helper. Both tests check their
output per window, match original payload/helper retirement counts
and reject deliberately wrong output. The donor mailbox also has to
reach the actual SDRAM model. Two runs match exactly, and each reported
median uses five scored windows.

| Physical path and change | GLES 176×208 fill | Sega Rally 176×208 scan |
| --- | ---: | ---: |
| Stock v5 | 299,252 | 2,466,436 |
| Stock ngage2 | 149,869 | 4,456,598 |
| v5 early instruction restart | 299,252 | 2,466,436 |
| v5 ordered one-entry write posting | 295,306 | 2,465,549 |
| v5 donor-style bank interleave | 297,306 | 2,465,118 |
| v5 posting and interleave | 293,338 | 2,465,320 |
| ngage2 posted scalar writes with write gathering disabled | 138,752 | 4,451,870 |
| ngage2 16 KiB D-cache | 174,368 | 4,453,597 |
| ngage2 v5 data section-TLB index | — | 2,440,099 |
| ngage2 16 KiB D-cache and v5 data section-TLB index | 173,629 | 2,441,243 |

- The isolated ngage2 XOR trial removes 109,850 logged data section
  translations in the Sega frame and saves 2,016,499 clocks. With both
  D-cache capacity and section index matched, ngage2 is 25,193 clocks
  ahead of v5 on that proxy. The 16 KiB data-cache trial by itself
  saves only 3,001 Sega clocks and costs 24,499 on the fill. Line sizes
  and bus implementations still differ.
- V5 and stock ngage2 both execute 22,896 payload instructions on the
  fill, and 640,677 payload plus 787,302 helper instructions on Sega.
  In the first scored fill v5 sends 2,288 SDRAM lines, six scalar reads
  and 16,256 scalar writes. Stock ngage2 sends 4,583 read requests and
  4,320 gathered write requests. Donor scalar mode sends 17,280 writes
  and is 11,117 clocks faster than gathering on this fill. The controller
  and CPU can overlap its posted scalar path with discovery of later
  dirty words. The timing comparison covers that behavior as a whole.
- V5 posting saves 3,946 elapsed fill clocks even though the scalar
  interface spends 20,629 fewer clocks waiting in the first scored
  window. The queue still serializes physical commands and stalls as
  it fills. The directed queue test checks full-queue behavior, partial
  masking, ordered readback, line admission, locked completion and
  logical reset drain. Dirty-write gathering on v5 remains unimplemented.
- The combined v5 change saves 5,914 clocks, 1.98% of its fill time.
  The remaining gap to stock ngage2 is 143,469 clocks, or 96.0% of the
  original matched fill gap. The combined candidate and control
  pass all 15 retained payloads at the production SDRAM pin timing.
  The older `0:0` and `2:9` profiles use a synthetic responder that
  bypasses the controllers. The delayed physical regression instead adds
  two clocks before each DDR burst and nine before each SDRAM request
  while retaining the pin protocols. With this delay both configurations
  pass all 15 cases again. The GLES fill goes from 465,570 to 459,830 clocks
  and Sega from 2,563,393 to 2,561,384. The largest short-case slowdown is
  six clocks. The experiments ran entirely in simulation.
- The delayed NOR case exercises all eight possible word offsets. With
  the same 48-clock tail hold, v5 retires the first instruction 11
  clocks after the final DDR beat at all offsets. The early trial
  retires offsets 0–20 bytes 36–41 clocks before the final beat and
  has a 0–1 clock benefit at the other two offsets. The ordinary
  wrapper with the trial netlist and the certificate held low passes
  all four fault-capable contract settings, including rejected and
  delayed line offers. The early wrapper is specific to the simulated
  error-free SDRAM/NOR line peer. Both hot rendering proxies show zero
  scored instruction-line fills, which accounts for the zero speedup.
- The fill produces one scored DDR read per v5 window and zero on
  ngage2. Sega produces three on each. V5 has zero scored MMC edges
  and IRQ-mode clocks. The proxies use minimal guests with no native
  scheduler or active LCD upload.

## Same SDRAM requests on all three paths

The captured v5 stream is submitted in order with no guest think time.
Writes keep their request positions and use checked deterministic
values. The donor consumes each 32-byte read as two native 16-byte
bursts. Both maps run on the real v5 JTFRAME controller and preserve all
16 MiB. Each case verifies every returned beat, drains before stopping
the clock and checks final written memory. Refresh runs during all
measurements. The controller peers share the same Micron pin model.
V5 uses its stock falling-edge data capture. The donor uses its
rising-edge capture with a 5.5 ns data-return delay in its documented
board allowance (4.5–7 ns).

| First scored v5 stream | Requests | Pins READ / WRITE | v5 clocks | v5 interleaved clocks | ngage2 clocks |
| --- | ---: | ---: | ---: | ---: | ---: |
| GLES fill | 18,550 | 4,583 / 32,512 | 284,450 | 282,462 | 134,704 |
| Sega Rally | 21,730 | 9,265 / 34,192 | 360,587 | 353,932 | 215,532 |

The captured GLES stream crosses rows often, especially at 16 KiB and
16 KiB + 4 bytes. Both mappings conflict at those spacings. The
address-only open-row model predicts 4,076 v5 conflicts and 3,587 with
the donor map. For Sega the same counts are 6,217 and 4,540. Actual
interleaving cuts v5 ACT commands from 4,472 to 3,995 on GLES and from
6,667 to 5,058 on Sega. Matched elapsed savings are 1,988 and 6,655
clocks, respectively. Address-only counts exclude refresh.

| 1,024 alternating accesses | v5 clocks | v5 interleaved clocks | ngage2 clocks |
| --- | ---: | ---: | ---: |
| Read at 32-byte spacing | 12,378 | 12,378 | 10,348 |
| Read at 4 KiB spacing | 16,421 | 12,385 | 10,384 |
| Read at 8 KiB spacing | 16,418 | 12,432 | 10,392 |
| Read at 16 KiB spacing | 16,430 | 16,411 | 14,410 |
| Read at 8 MiB spacing | 12,382 | 16,415 | 14,413 |
| Write at 32-byte spacing, including drain | 13,449 | 13,448 | 3,152 |
| Write at 4 KiB spacing, including drain | 17,440 | 13,455 | 3,152 |

The map fixes the 4/8 KiB microbenchmark conflicts and creates a conflict
at 8 MiB. Most of the GLES replay difference persists with the same bank
map and pin command counts. The same-row scalar write microbenchmark
identifies transaction completion and overlap as direct targets for
further investigation.
[Scalar handoff timing](arm9v2-sdram-handoff.md).

## Presentation and guest time

A sequential readback of the same 73,216-byte framebuffer takes
221,942 clocks on stock v5, 221,878 on interleaved v5 and 185,413 on
ngage2. This measures SDRAM service for scalar scan reads. Native LCD
DMA, panel transfer, repeated scanout, IRQ and concurrent CPU service
are outside its scope. The times cannot be added to the render proxies
to derive a native frame rate.

The original `3DTEST.DLL` passes through EUSER ordinal 1166
(`TTime::UniversalTime`) at offsets `0x7ea4`, `0x8208`, `0x82f4`
and ordinal 695 (`TTime::MicroSecondsFrom`) at `0x8238` and
`0x8308`. The score calculation at `0x8298`–`0x82c0`
converts elapsed microseconds using 1,000,000 and divides work by
elapsed seconds. The DLL also uses ordinal 1137 (`User::TickCount`)
at `0x5b0` in a separate time helper. It has no EUSER
`FastCounter` import. Offsets are relative to the preferred
`0x10000000` base. The local original E32 imports, ARM call stubs and
N-Gage EUSER ordinal definitions were checked together. Checked
3DTEST SHA-256 is
`5b918e3d10a8b4e91265325649c98c72fba7260be6cab37a102d7f50cd7eebef`.

The production source and documented firmware reloads imply 64 Hz
Timer0 on NEM-4 (26 MHz / 406,250) and approximately 64.00008 Hz on
the donor (34⅔ MHz / 541,666). These are nominal kernel tick rates.
The NOS compare counter is separate. This leaves guest seconds per measured hardware second, native Game
work per frame, and visible LCD upload boundaries to verify. The full provisional
1.69M-clock native difference remains unassigned.

## Replay

Use the prepared Micron Verilator model from the real SDRAM boot
fixture and the pinned checked payload archives under `build/sim`.
All runs use the installed offline simulator image.

```sh
model=build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v
test_dir=tests/cpu/arm9v2_board
python3 "$test_dir/payload_clocks.py" --name v5-physical \
  --config 2:64 --flash-cache-bytes 32768 --sdram-model "$model" \
  --case fill16_frame --case sega-scan
python3 "$test_dir/frame_gap_donor.py" --name donor-physical --sdram-model "$model"
PHONE_SDRAM_MODEL="$model" FRAME_GAP_TRACES=build/sim/payload-clocks/v5-physical \
  sh tests/phone/sdram/run-frame-gap-banks.sh frame-gap-physical-pins
```

On v5 add `--posted-writes`, `--interleave` or both for isolated trials,
and omit `--case` to run all 15. Add `--pin-waits` for the delayed
physical profile. On the donor use `--scalar-writeback`,
`--dcache-16k` or `--section-xor`. Generate the early-restart overlay
with `frame_gap_early.py --out build/early-restart-fresh`, then give
that wrapper and netlist to either `payload_clocks.py` or
`tests/phone/ddr_flash_cache/run_trace.py` using the two alternate
source options. The scorecard script records the archived run names,
all scored medians and input identities.
