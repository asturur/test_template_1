# Early hardware RAM fault and SDRAM pin-register fix — 2026-11-13

The new boot-fix RBF has an earlier hardware failure. The unmodified RTL boot
has **not reproduced that fault in Verilator**. A separate, concrete FPGA
implementation defect has been corrected in RTL: SDRAM data-output registers
could not pack into I/O cells. This is a board-fix candidate, not a verified
successful boot or a new timing result.

## Board observations

Installed RBF exactly matches3ab8e10, run43391828015, seed43, SHA256
`32655ead988e28e32c191f4d0abf9507aab7dc1e93b25eb97b522e1d7c950985`.
Live ROM is the original `88fd596a23269ecb0d9f7544d540c59010d276574dbe3d0262c870c429e58329`.
C:/PMM retain the known-good card hashes; autosave remains Off. No ROM/RAM
patches, overlays, saves, PMM record injections or clock changes were applied.

Three cold reloads of that image reach a low-vector abort loop at0000060C:

| Attempt | First bad address | Recorded first-fault PC | First bad snapshot CPU cycles |
| --- | --- | --- | ---: |
|1|2AFFF3DC|00000F84|1,407,559|
|2|2AFFF400|0000177C|338,998,394|
|3|2AFFF400|00001720|354,135,565|

The recorded PC is the monitor's associated PC, not a full faulting instruction
context. F84 is an original stack store. The later PCs are RAM-descriptor
lookup code; the monitor can report the instruction following a memory access.
Do not invent a2A RAM alias to acknowledge these bad pointers. The second/third
attempts pass the first stack setup and fail after the original boot delay.

A same-board control launches the previous a413b1e/seed44 RBF from a temporary
Linux RAM file. It passes those early stages, produces normal kernel text and
reaches the already known UART drain loop with0C15055C=10 and no sticky data
fault. The card's installed RBF was not overwritten. The temporary copy is
removed; the latest installed RBF is restored with CPU Hold, both images mounted
and autosave Off. Capture processes are stopped and card disk hashes rechecked.

## Review of dbe5bc6

The requested commit is `dbe5bc6d551081d7cd51f3190960a76224103bf4`.
It is present in **both** board images. The only production RTL difference
between a413b1e and3ab8e10 is TX-ready tied1 instead of0. Thus dbe5bc6 is not a
unique source regression between these two RBFs. Placement changes can expose
an existing physical margin problem; this does not clear its controller changes
of every possible bug.

| Change | Relevance to this fault |
| --- | --- |
| One logical256-bit line service, two physical BL8 READs | Candidate transport ownership/data-order change; isolated physical tests and native early boot pass |
| Two consecutive masked WRITE commands | Most relevant protocol change if physical write margins are weak; retain as a suspect until board qualification |
| Reuse outer arbiter write payload; remove duplicate DMA snapshot | Retention/reset contract passes; DMA work is not needed to reach the first stack store |
| Two active banks; programmer/unused banks excluded | Geometry stays AW22 and two8MiB banks; changes placement/resource use |
| Native BL8 init mapping for logical256-bit services | Physical mode stays BL8; not a new16-beat device burst |

The exact parent versions of the adapter, DMA RAM mux and three changed SDRAM
controller files were factored out into an isolated Verilator comparison.
The test uses the parent128-bit service parameters and old interface. Both
parent and current memory implementations pass the first200,000 native cycles
with a valid0A... stack. No working-tree rollback or extra production option
was introduced. This comparison does not cover the entire later boot delay.

## Confirmed implementation defect and correction

The new fitter report explicitly says it cannot pack each `dq_pad[0..15]`
register into its SDRAM_DQ I/O pin: the inferred register cannot simultaneously
use clear and load signals. The Bidir Pins table confirms:

- 16/16 input registers packed.
- 0/16 data-output registers packed.
- 16/16 output-enable registers packed.

The sequential `dq_pad <= write ? data : Z` shape predates dbe5bc6. New placement
and consecutive writes can expose its cost, but no captured electrical waveform
yet proves this is the cause of the board pointers. The completed fit also has
core setup−0.071ns and HDMI setup−0.128ns; this patch does not claim to fix those
reported paths or complete external-I/O timing sign-off.

`jtframe_sdram64.v` now samples data unconditionally into `dq_pad` and samples
write ownership separately into `dq_oe`; a combinational tristate assignment
connects the data only while that registered enable is active. The Verilator
split write-data port sees the same registered word. No bus stage, command,
request gap, address geometry, refresh rate or PLL changes. Existing FAST_OUTPUT
and FAST_OUTPUT_ENABLE assignments remain in force. Fitted area is unmeasured.

## Verification and limits

All use the existing offline `jotego/simulator:arm64` image:

- Original firmware five-million-cycle real-controller smoke passes:12 known
  instruction-side probe errors, zero data errors.
- Six DDR response delays1/2/3/4/5/7 pass the first200,000 native cycles.
- Full16MiB physical-model scrub followed by200,000 native cycles passes.
- Existing Intel altdpram RF model, then Intel RF+M10K models together, pass
  early boot; their local selection/debug wrappers are not production files.
- A board-settings profile (UEM2, timer divide3, NOS64Hz, test SIM disabled,
  no SIM) passes the first200,000 native cycles.
- That profile with127,214 diagnostic-region DDR writes passes one million
  native cycles. No diagnostic write touches firmware or disk regions.
- Pin-register candidate passes native early boot at78/104MHz. At78MHz all360
  cycle-tagged stack/retirement/RAM/fault trace rows exactly match the original.
- Four-state Micron tests pass full/native scalar/line traffic, all byte masks,
  bank concurrency,78/104MHz and clock-pin delays0/.25/.5/1ns. The wrong-edge
  Z-data negative control still fails as required. Top elaboration passes.

These are bounded CPU/board/controller fixtures, not a whole placed FPGA. The
full-scrub run uses the historical bounded power/timer profile; the separate
board-settings run uses the short scrub. The later~339M-cycle hardware point
has not been replayed through that entire delay. Vendor functional models do
not prove FPGA pin packing or electrical margins.

Raw sources, captures, RBF identities, original disassembly inputs and logs are
persistent under `scratch/board-debug-next-20261113/`. Selected model work uses
local existing Intel/Micron libraries; no Quartus/software was downloaded.
[Compact results/source hashes](evidence/sdram-early-boot-2026-11-13.json).

## Required next qualification

1. Build the pin-register fix with unchanged78MHz PLL. Run
   `python3 tools/check_sdram_io_registers.py output_files/Template.fit.rpt`.
   Require all16 DQ data/input/OE registers packed and absence of the old
   clear/load packing warnings. The checker rejects all16 old data outputs.
   This remains a manual checker: the current gh token rejects workflow-file
   edits. The existing build workflow and failed-timing RBF/report retention
   remain unchanged. The proposed CI guard is preserved in scratch publication
   notes for later authentication/CI integration.
2. Inspect setup/hold and external SDRAM timing; no false/multicycle exceptions
   or softened vendor checks were added to hide this failure.
3. Repeat the same original-ROM/card boot. Confirm valid early RAM pointers
   before qualifying the UART fix and selecting the next native stopper.
4. If this still fails, use the isolated pre-dbe5bc6 backend as a controlled
   board comparison, or factor paired writes separately. Do not blanket-revert
   unrelated CPU/DDR/diagnostic fixes or claim the optimization bundle proven bad
   from the current evidence.
