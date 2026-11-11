## 2026-11-11: Timing patch fails LAB fit; isolate before further changes

User reported4277 required LABs versus4191 available for840e3d4. A one-shot
artifact download of completed failed run43059270414 confirms42,407 required
ALMs,47,605 fitter registers,42 DSPs and497 M10Ks in the detailed report.
The failed summary's zero RAM blocks is again a partial-fit summary artifact.
Reports are retained under
`scratch/ngage2-integration/timing-recovery-2026-11-11/ci-43059270414/`.
No build monitoring/polling or new RTL changes occurred during this audit.

The only synthesized source changes since c8add13 are LCD header/geometry
prevalidation and the local DMA registered response. PLL, SDC, Template profile,
QSF options, caches, worker count and enabled peripherals are unchanged. The
LCD patch adds precomputed geometry/limit/valid state and two source-level
constant multiplier expressions; DMA adds a32-bit data/one-bit error snapshot
and one response state. Synthesis FF count is44,061->44,128 (**+67**, correcting
the initial spoken +68); DSP count40->42. No feature was re-enabled.

The old93% ALM headline did not represent7% physical placement headroom. The
fitter formula was40,492 placed -2,533 estimated recoverable +1,036 unavailable
=38,995 required. The failed run reports41,551 placed -1 recoverable +857
unavailable =42,407 required. Thus the required estimate rises3,412 while the
placed count rises1,059; loss of dense-packing credit accounts for2,532 of the
required increase (with unavailable estimate down179). The prior placement was
already97% occupied. Failed-fit packing/hierarchy figures are incomplete and
are not a controlled per-module area measurement.

The changed netlist caused global mapping/packing differences, including
unchanged timers, ICU, CPU and DMA workers. This establishes an area regression
but not which of the two patches triggered it. Local functional/cycle tests do
not prove area or timing benefit. Next isolate LCD-only and DMA-response-only
against c8add13 with identical78 MHz clocks/options/toolchain, inspecting map
as well as fitter packing; do not add more features or tune a seed to hide it.
Actual operating clock remains78 MHz; RTL target remains104 MHz.

# LCD/local-DMA timing recovery — 2026-11-11

## Supplied build: fit succeeds, setup timing fails

The new logs report38,995/41,910 ALMs (93%),47,503 registers,497/553 M10Ks
(90%),40/112 DSPs and successful Quartus full compilation/assembly. This is
not another device-capacity failure. The project's timing gate correctly
rejects the TimeQuest report. At the actual78 MHz clock, worst setup slack
is-2.657 ns, TNS-4,592.500 ns and reported Fmax64.61 MHz. Hold slack is+0.242 ns.
The supplied artifact does not independently establish its Git commit identity.

The exported1000 paths contain one worst path per endpoint, not every path.
The worst path is DMA-local-active through the shared UPP bus address/decode,
programming-read readiness and ACK, then route response and DMA engine state
(15 logic levels/14.633 ns data). LCD row geometry reaches fast-stream control
and881 framebuffer endpoints. Row-end multiply/subtract/byte-count comparison
remains in a per-pixel write admission signal, distributing that late decision
across the framebuffer RAMs. The register file is not the first reported
bottleneck in this sample.

## Timing objective and clock policy

**Keep the actual PLL and production SYS_CLK_HZ at78 MHz.** User explicitly
clarified104 MHz as the RTL design north star (9.615 ns budget), not permission
to increase the current operating clock. PLL/Template clock changes made during
this investigation were restored before publication; static configuration and
both78/104 MHz logical timebase tests pass. No SDC relaxation, false paths or
slower clock are introduced. This change alone does not prove104 MHz closure.

## Implemented boundaries

- LCD validates a pixel header and captures its write limit on the accepted
  header write. Row-band transport byte count is prepared when the row-window
  payload commits. Pixel beats use registered header validity, memory-write
  state and cursor/limit; they no longer recalculate row multipliers and header
  byte extent. A geometry update requires a non-pixel header first, which
  invalidates the old decision. No pixel queue/transfer stage is added.
- The local DMA route captures the exact response data/error at its accepted
  peripheral ACK, then presents one registered completion cycle. This cuts
  late shared-bus decode from engine state updates. No additional bus request
  or peripheral side effect is issued. SDRAM response timing and the separate
  fast LCD stream are unchanged. One clock is added to local response delivery;
  reset/stop/ownership and error identity must span that stage.

## Verification and performance

- Frozen pre-change LCD reference versus new controller: all43,681 row pairs
  from0..208, correct/off-by-one/legacy pixel headers, every external output
  compared for1,135,723 cycles. PASS. Existing full-frame, malformed window,
  extent rejection, direct/DMA priority, partial/out-of-order updates and raster
  tests pass too. These are transaction-level model checks, not phone evidence.
- DMA route: delayed local acceptance, exact captured read/error, CPU lock after
  acceptance, same-edge FIFO completion, stale ACK, reset killing a queued
  completion and original SDRAM response cycle pass. Existing masks/contention/
  rejects/reset checks pass.
- Production ARM DMA/LCD at timer divider4/NOS64 Hz: full-frame interval remains
  **130,685 clocks**. Complete normal/held fixtures are152,457/152,538, exactly
  one clock above the earlier152,456/152,537. This includes a local control/error
  transaction; it is not one extra clock per LCD word. Queue-tail/reset and
  CPU-Hold reset tests pass.
- MMC remains30 bus cases/132,221 clocks and98 DMA phases/667,085 clocks,
  including all channels, native transfers, stalls, ownership and cancellation.
- Real SDRAM controller with unchanged Micron timing:104/78 MHz, clock-pin
  delays0/.25/.5/1 ns all pass; wrong capture-edge negative control still fails
  as expected. Logical timer/timebase/raster tests pass at both clock profiles.
- Production top structural elaboration (HPS/PLL stubbed) and173-file/nine-QIP
  source preflight pass. No long startup run or other-chat checkpoint is touched.

The next routed build remains78 MHz. It must establish new area and setup/hold
results before these changes can be called timing fixes on silicon. Check all
path families again using newly supplied results; do not monitor CI. Continue
reducing stage depth/fanout toward104 MHz rather than lowering frequency.
Game audio remains ARM PCM only, with no DSP/telephony audio implementation in
this work; see P7 and the RF/audio audit for the updated scope.
