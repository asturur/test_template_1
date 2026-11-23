# Earlier v5 timing experiments

These are source and test deltas from the exact revisions in the
[seed-44 report](historical-seed44-evidence.md) and the
[CPU and board isolation report](../../v5-timing-isolation.md).
Each patch starts at the listed base, including forward reverts where
they formed the physical control. The [manifest](manifest.json) and
`verify.py` check the actual affected blobs. Test commands written
within a patch use the test and tooling versions in that stage.

## Physical 78 MHz work

The first four trials are seed 44 only. The following matched triplets
use seeds 42, 43 and 44. Diagnostic 104 MHz figures in this period came
from 78 MHz placement and routing.

| Patch and target | Base | Design, check and result |
| --- | --- | --- |
| [Paired-load address match](historical/paired-load-address.patch) `b378969` | `237117d` | Registers the selected writeback-owner match beside the possible second word. Held data and writeback promotion stay aligned. Directed pair matching and all workloads passed. Hot slack improved from −1.746 to −1.056 ns. |
| [Wishbone refill classification](historical/wishbone-refill-classification.patch) `2cf19f0` | `b378969` | Registers line eligibility with the merged request, removing the old live address and cycle-type cone. Directed classifier and workload checks matched. Cold worst setup moved to D-cache write-through and issue. |
| [Clocked paired-load hint](historical/pair-hint-clocked-base.patch) `9637fca` | `2cf19f0` | Removes late write-through from the advisory base hint. Architectural operands and split fallback retain the exact live check. Workloads tied. Core TNS improved on this sequence. |
| [Preserve DMA command flops](historical/dma-command-flops.patch) `11d468f` | `9637fca` | Protects existing packet registers from retiming. Seed 44 regressed to −1.778 ns hot and −1.654 ns cold. The next trial restored the prior boundary. |
| [Scalar reply ownership](historical/scalar-reply-ownership.patch) `f2d9c04` | `11d468f` | Separates scalar reply cancellation and ownership from the next line classifier and removes the command-flop protection. Directed reply and workload checks matched. Seed 44 worst setup reached −0.894 ns. |
| [Capture lock with SDRAM packet](historical/sdram-packet-lock.patch) `581f8e6` | `f2d9c04` | Saves lock when a scalar packet is granted so a younger SWP cannot alter an older reply. Passed the 16 MiB pin scrub, younger-lock regression and workload checks. One of three seeds improved. |
| [Physical SDRAM command slot](historical/sdram-physical-command-slot.patch) `6c19540` | `581f8e6` | Registers the physical packet and overlaps capture with accepted line and scalar read grants. Pin checks cover clocks, contention, refresh and reset. Native cost +0.01122% and full-frame dirty writeback +1.702%. Hot scheduler endpoints moved out of the worst paths. |
| [Serial ARM load lists](historical/serial-arm-ldm.patch) `a5a7349` | `6c19540` | Uses ordinary sequencing for the two-word ARM LDM and retains the optional hinted issue overlay. Precise second-word abort and ordered writes passed. Native cost +0.0822%; worst setup improved on all seeds. |
| [Cache-local refill classification](historical/first-line-classification.patch) `7b10754` | `a5a7349` | Prepares first-refill authorization in each cache and carries it with the request. All workload cycles matched. Seed 43 closed physical 78 MHz at +0.210 ns with all recorded timing checks passing. |

## System clock and raster

| Patch and target | Base | Design, check and result |
| --- | --- | --- |
| [Physical 104 MHz clock](historical/physical-104mhz-clock.patch) `295b7ef` | `7b10754` | Changes the board PLL and drives peripheral rates from the physical system frequency. Adds verification for updated MMC clock logic and captures exact fitter inputs. This is the first part of the corrected 104 MHz baseline. |
| [MMC and analog clock divisors](historical/mmc-and-analog-clock-dividers.patch) `2bc545b` | `295b7ef` | Uses integer MMC timing and changes the intermediate analog source cadence. The 414-pixel raster had no FPGA fit. Includes clock and video fixtures. |
| [Original 400 × 262 raster](historical/original-analog-raster.patch) `9405da9` | `2bc545b` | Preserves original sync, blanking and pixel cadence by using a 104/16 clock enable. The raster comparisons matched the 78 MHz reference. The physical 104 MHz triplet became the running control. |

## Physical 104 MHz work

Unless noted, the matched seeds are 42, 43 and 44, DDR debug off.

| Patch and target | Base | Design, check and result |
| --- | --- | --- |
| [LCD DMA read eligibility](historical/lcd-dma-eligibility.patch) `993eb2b` | `9405da9` | Registers remaining-word eligibility flags before SDRAM grant. Worst setup improved on all three seeds relative to the original-raster control. |
| [Registered SDRAM scalar read completion](historical/sdram-scalar-read-completion.patch) `ae3ff84` | `993eb2b` | Captures the scalar read reply in the stream adapter. Directed streaming test exercises response timing. Median setup fell from −2.995 to −3.143 ns. |
| [Captured slow UPP owner](historical/captured-upp-owner.patch) `06a7aad` | `ae3ff84` | Holds admitted slow requests with the registered owner instead of the live selection. The UPP request-stage test checks ownership under hold. Median setup improved to −3.054 ns. |
| [Packed D-cache write enables](historical/packed-d-cache-write-enables.patch) `69773af` | `06a7aad` | Predecodes each way's write enable alongside packed cache data while retaining permission checks and byte masks. Seed 44 reached −2.688 ns. The packed write regression is included. |
| [Cache feedback at issue](historical/cache-feedback-at-issue.patch) `ff8becc` | `69773af` | Captures the miss-load destination and chooses DSP inputs by product owner. Four contracts and workload cycles matched. Named D-cache-to-execute endpoints improved; whole-design best was −2.914 ns. |
| [SDRAM payload preview](historical/sdram-payload-preview.patch) `c90ea0f` | `ff8becc` | An empty command slot previews payload while the final grant sets validity. Workloads and 1,048,650 accepted commands and replies matched. Command-slot endpoints fell sharply in the hot exports. Median setup −2.869 ns. |
| [Execute forwarding grants](historical/execute-forwarding.patch) `6c569de` | `c90ea0f` | Precomputes grant choices for the candidate producer transitions and selects them using writeback. Twenty contracts and all workload cycles matched. Median setup −2.744 ns; best −2.689 ns. This is the round-three CPU control. |
| [Owned Wishbone completion](historical/owned-wishbone-completion.patch) `d4edf9b` | `6c569de` | Registers the scalar packet and response owner while preserving the qualified SDRAM read path. Native payload cost was small, but mixed LCD/MMC/PCM increased 7.27%. Seed 44 improved to −2.569 ns and median regressed to −2.937 ns. |
| [Register-shift operand shape](historical/register-shift-shape.patch) `94bcc14` | `d567759` | Predecodes the register-count source while preserving the readiness interlock and same-cycle shift. All workload and mixed cycles matched. Median setup fell to −3.289 ns. |
| [Original BRAM fetch queue](historical/fetch-queue-original.patch) `dc1903f` | `74de910` | Original 112-bit queue RAM and 8,504-cycle differential. Whole-core area fell from 90–91% to 86% and all workload cycles matched. Setup regressed on all seeds. The later [DDR-backed replay](patches/fetch-queue.patch) uses the same fetch logic. |
| [Registered cache authorization](historical/registered-cache-authorization.patch) `2e7b7bd` | `6b66d43` | Precomputes per-access load/store fast completion authorization and preserves fault, lock and replay fallback. Contracts, 15 workloads and native frames matched. Median setup −3.120 ns. |
| [Pipelined register-count shifter](historical/pipelined-register-shift.patch) `e8bc7b4` | `691ee0f` | Splits the barrel shift after its first two rotation stages. All 18,432 directed comparisons passed. Native cost +2.02%, Asphalt single lookup +6.68% and all seeds regressed. |
| [CPU and board isolated-fit harness](historical/isolated-fit-harness.patch) `08f79f8` | `4c88998` | Builds CPU/registered-memory and board/traffic-generator halves, with distinct source manifests and fixture timing constraints. Includes the isolated workflows and contract fixtures. Scope is diagnostic. |
| [LCD packet reservation](historical/lcd-packet-reservation.patch) `cd609b2` | `d5c3d62` | Prepares the next local address and transfer size before grant. Eighteen pin-model tests and mixed replay matched. Internal median gained 0.006 ns; the integrated round-three CPU setup median gained 0.112 ns. |
| [Repeated-load interlock](historical/repeated-load-interlock.patch) `eb2abbc` | `cd609b2` | Takes the younger same-destination issue slot early and waits for the older writer to retire. Native cost +0.101% and a directed 32-load chain rose from 104 to 128 clocks. Isolated CPU setup regressed. |
| [Wishbone payload banks](historical/wishbone-payload-banks.patch) `9d2e76c` | `75186be` | Captures request payloads at their sources and selects by registered owner. Four contracts, 256 arbitration combinations and all workloads matched. Area fell on all seeds, but setup median went from −2.632 to −2.884 ns. |

Forward reverts and documentation-only comparison commits serve as
provenance. The external donor runs remain comparative evidence in the
timing reports. The historical simulation-only extra stage on every
cacheable D completion and the first unqualified scalar-reply stage
have narrative results there; this catalog covers their fitted successors.
