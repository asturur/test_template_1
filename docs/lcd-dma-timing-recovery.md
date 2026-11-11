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
