2026-11-13 follow-up: the new3ab8e10/seed43 board image fails earlier with a
bad RAM pointer. Bounded native simulations pass; a concrete SDRAM output IO
packing defect is corrected separately. Physical qualification of that change
and on-board qualification of UART TX progress remain pending. No rollback of
dbe5bc6 or firmware patches. See [current investigation](sdram-early-boot-2026-11-13.md).

# Native SDRAM implementation: validation handoff

The subsequent [request-ownership cleanup](sdram-request-ownership.md) removes
another 36 duplicate adapter state bits, adds reset-drain admission protection,
and preserves all measured native-controller latencies. Its own frozen baseline,
full controller/refill regressions and both bounded CPU/board rates pass. Area
and routed timing remain unmeasured. `run-native.sh` now includes its ownership
test. The original two-READ/two-WRITE results below remain the earlier baseline.

2026-11-12. Original core, branch `codex/ngage2-integration`.
The Docker-blocked attempts below have now been superseded: all documented
runtime commands pass using the existing image, including bounded real-controller
boots at both rates. The negative-control configuration was corrected without
relaxing vendor timing or expected Z failure; native concurrent-bank and DDIO
production-profile coverage were expanded. A matched physical-controller
benchmark was added as `tests/phone/sdram/run-latency.sh`.

Row-hit line whole latency29->23 clocks (first8 unchanged), masked writes21->12;
mixed workload4693->4119 clocks with a CPU-read latency tradeoff. See
[full results and remaining gates](cache-line-refill.md#native-sdram-runtime-validation-and-latency-2026-11-12)
and [structured evidence](evidence/sdram-native-validation-2026-11-12.json).
Raw logs/source snapshots: `scratch/sdram-native-runtime-20261112/`.
No branch switch, commit, push, deployment or existing simulation/checkpoint
change. Fit, board timing/geometry and full boot/gameplay remain unverified.
The directions below remain the reproducible validation procedure.

## Validation procedure

Implement validation and fix failures for the original core's native SDRAM
changes in `/Users/andreabogazzi/develop/NGage_MiSTer`. Read `AGENTS.md`,
`docs/status.md`, `docs/README.md`, the native-service section at the end of
`docs/cache-line-refill.md`, and this handoff first. Stay on the existing branch;
do not create a branch. Preserve unrelated dirty work and all running simulations
and checkpoints. Use the existing `jotego/simulator:arm64` image with
`--pull=never`; do not download Quartus or change the simulation image.

The implementation changes are:

- `Template.sv`: two active banks, programmer excluded, logical BA0/1 length256.
- `rtl/sdram/jtframe_sdram64*.v`: keep physical BL8/CL2, schedule the second line
  READ eight clocks after the first, and reserve command slots for it and for
  the second masked WRITE. Native word writes finish after recovery.
- `rtl/ngage_sdram_adapter.v`: one controller request for sixteen halfwords,
  direct cache streaming, native32-bit writes; old half-line restart/GAP removed.
- `rtl/ngage_dma_ram_mux.v`: remove62 duplicate payload registers. The connected
  `ngage_sdram_arbiter` retains the accepted packet; mux owns the response tag.
- Focused tests check command spacing, continuous line data, all masks, boundaries,
  reset/drain, full scrub and actual outer-arbiter packet retention. The testbench
  prints aggregate write/line wait clocks for measurement; these are not yet results.

The mapping deliberately remains AW22 / two physical8MiB banks. A32MiB x16
SDRAM has8MiB per physical bank; one16MiB physical bank requires larger chip
geometry. Installed geometry is unverified. Do not silently change AW to23 or
claim that a single16MiB bank works on the existing module.

1. Confirm Docker access and image availability without pulling:

   ```sh
   docker image inspect jotego/simulator:arm64 --format '{{.Id}}'
   ```

2. Format and structurally check the changed phone RTL, then run focused physical
   SDRAM and ownership regressions. The cached Verible binary is Linux ARM64,
   so it must run in the container, not directly on macOS:

   ```sh
   docker run --rm --pull=never --network none --platform linux/arm64 \
     -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 -c '
   set -eu
   fmt=scratch/rtl-format/tools/verible-v0.0-4298-g085eef05/bin/verible-verilog-format
   python3 tools/format_phone_rtl.py --formatter "$fmt" Template.sv rtl/ngage_sdram_adapter.v rtl/ngage_dma_ram_mux.v
   python3 tools/format_phone_rtl.py --formatter "$fmt" --check Template.sv rtl/ngage_sdram_adapter.v rtl/ngage_dma_ram_mux.v
   sh tests/phone/mister_transport/lint-top.sh
   '
   sh tests/phone/sdram/run-native.sh
   ```

   The focused wrapper includes the Micron four-state model, wrong-edge negative
   control,78/104MHz and clock-delay cases, terminated short reads, concurrent
   banks, all byte masks, first/last rows and banks, uninterrupted16-beat refills,
   native WRITE adjacency, SWP exclusion, reset drain, full16MiB scrub, DMA/LCD
   mux tests and LCD routing comparison. Inspect every log for timing errors;
   a PASS banner alone is insufficient. Do not weaken the vendor timings or
   the negative control to make failures disappear. Preserve DDIO pin boundaries.

3. Run DMA/LCD integration and CPU/real-controller checks:

   ```sh
   sh tests/phone/dma_channels/run-concurrency.sh
   sh tests/phone/dma_handover/run.sh
   docker run --rm --pull=never --network none --platform linux/arm64 \
     -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
     -c 'sh tests/phone/line_refill/run.sh'
   PHONE_SYS_CLK_HZ=78000000 PHONE_LINE_REFILL=1 PHONE_SHORT_READS=1 \
     sh tests/phone/hardware_boot/run-real-sdram.sh
   PHONE_SYS_CLK_HZ=104000000 PHONE_LINE_REFILL=1 PHONE_SHORT_READS=1 \
     sh tests/phone/hardware_boot/run-real-sdram.sh
   ```

   Check that the documented default firmware/C: files exist before the boot
   commands. Otherwise select existing equivalent inputs explicitly with
   `PHONE_CORE`, `PHONE_EXTENSION`, `PHONE_CDRIVE`, and record hashes/profile.
   The runner uses a disposable testbench memory; never rewrite the source C:
   image. Save each rate's logs before the next command reuses its output folder.
   A bounded boot is not proof of complete Symbian boot or gameplay performance.

4. Measure first-beat/whole-line and masked-word latency, including row hits,
   conflicts, refresh and mixed CPU/LCD load. Use the physical controller, not
   an idealized RAM fixture, for controller speed claims. Extend the counters
   if necessary. Pre-change implementation copies are in
   `scratch/sdram-specialize-20261112/before/`; the original focused testbench
   can also be read from Git HEAD. For comparisons, create isolated scratch
   copies (no branch, no switching/restoring files over the working tree), use
   identical traffic and clocks, and retain old/new logs. Some other files were
   already dirty before this task, so Git HEAD is not a whole-project baseline.
   The new WRITE-adjacency/continuous-line assertions intentionally do not apply
   to the old controller. Never use different cache/clock configurations and
   attribute their effect to SDRAM. No baseline Quartus fit is required.

5. Fix real failures, rerun affected checks, and update `docs/cache-line-refill.md`
   and `docs/status.md` with exact commands, outcomes, measured cycle deltas and
   remaining gates. Keep fit/104MHz routed timing, board tests and gameplay FPS
   explicitly unverified unless actually measured. Do not commit/push/deploy
   unless requested.

## Earlier pre-runtime checkpoint (superseded by results above)

Local Icarus elaboration only: configured native controller/adapter with the
Micron model; full scrub fixture; mux unit and actual outer-arbiter retention
fixtures; existing concurrent128-bit-bank fixture; generic four-bank/programmer
configuration. Shell syntax and `git diff --check` passed. No HDL simulation,
runtime benchmark, full top lint, formatter check or routed fit has passed here.
The cached Linux formatter cannot execute directly on macOS (`Exec format error`).
