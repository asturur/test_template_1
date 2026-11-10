# P0 integration baseline and transaction contracts

Integration work is isolated to `codex/ngage2-integration`, baseline commit
`7f55e93982219b8ad5315b785e63be4d4532a756`. Existing dirty plan/index/status notes
were preserved. Source identities and the original dirty patch are recorded in
`scratch/ngage2-integration/p0/source.json` and `dirty.patch`. All outputs and
new containers belong to this worktree. The original checkout and its running
simulations/checkpoints are untouched. No simulator lineage was migrated.

Toolchain image: existing `jotego/simulator:arm64`, Linux/arm64,
`sha256:df6f55924d5fab96083d01332e45cd734f22277c4dd3b34f55a09cd8dbc3eb8d`.
Verilator 5.050 (2026-07-01), Icarus 13.0 stable; host GNU ARM GCC 15.2.0.
Containers use network none. No Quartus download/build/push/CI/deployment.

Private core/extension and original four-state Micron model were copied read
only from the original checkout into this worktree's `scratch/` fixtures, then
local test paths. Hashes/source paths/sizes are in `p0/fixtures.json`. Core:
`be8b2ecdf5ff81f424b58838a8b93a1d1f65c0ae74890d2b96df8d5a7189b524`;
extension: `cb6e0b39c90df00864fc21ee527624372b1e4f5c3ff3c985f397172d30446cf3`.
The audited C: fixture was also copied for the legacy converter create/inspect
compatibility test. It was read only; no existing save/checkpoint was changed.
No new full-phone boot or firmware execution was performed.

## Ownership and completion contracts

| Path | Acceptance and lifetime | Completion/cancellation |
| --- | --- | --- |
| Scalar DDR | `valid && ready` captures owner/address/write/data/mask; one outstanding per arbiter | One response to captured owner; request held until acceptance; reset drains accepted downstream work before reuse |
| 32-byte refill | Descriptor captures CPU/cache owner and physical address after MMU/cache admission; reserves ordered beats | Existing line/error/last protocol installs only complete expected data; late response after reset drains; no new early completion |
| NOR mutation | Program/erase engine owns actual physical writes and emits dirty sectors on committed changes | Flash quiescence includes pending engine work; Save waits; no synthetic success for unsupported NOR operations |
| Save snapshot | Single scalar sector bridge snapshots 128 words before starting host write | Host buffer frozen through ACK fall; tracker keeps mutation-during-snapshot/transfer dirty and rescans; error retains dirty state |
| Peripheral masters | Existing CPU/direct-SDRAM/LCD and loader arbitration only | Existing captured-owner routing and reset behavior preserved; no new general DMA/MMC master in P0/S1/S2 |
| Reset | Phone warm reset requests defer behind save/load; transport cold reset remains explicit and immediate | Cold reset cancels manager/dirty state; external accepted memory operations follow existing drain rules; no power-loss durability claim |

DDR writers remain explicit: firmware/bundle/service loader, independent NOS/BT
overlay patch/undo, C:/PMM restore, NOR C:/PMM program/erase, and the existing
CPU diagnostic/test paths. Read-only trace export writes its diagnostic disk,
not the firmware backing region. S2 adds no new DDR storage/coherence owner;
restores remain gated behind known firmware and ahead of CPU release.

## Measurements retained, rather than fabricated

Existing measured evidence is in `docs/cache-line-refill.md`,
`docs/evidence/line-refill-2026-11-10.json`,
`docs/evidence/sdram-short-reads-2026-11-10.json` and the newest status entries.
The matched cache-active 50M segments measured raw I-refill 137.37→22.87 clocks,
D-refill 136.84→39.92, and DDR commands 722967→252294. These are existing line
transport results, not new S2 performance. Micro-op counts are not architectural
retirement; changed C: positions are not copied-byte throughput. The cold 50M
physical-controller run remained in the early cache-off startup loop (errors12,
data_errors0), so it does not measure cache performance or establish UI boot.

Current architecture/profile is retained: original NEM-4 firmware and NOR,
ARM920/ZAP CPU, unchanged phone/timer clocks; physical SDRAM regressions explicitly
include 78/104MHz and modeled pin delay. No architectural-instruction/branch/
load/store throughput, cache reuse, SDRAM row-locality/occupancy/refresh-speed,
full-phone restore/flush wall time, FPGA resources/Fmax or whole-phone performance
numbers are newly claimed. Those require their own future matched workload or
hardware gates; host simulation speed is not phone speed.

## Baseline fixture failures and disposition

The first actual-HPS NOR run stopped because this fresh worktree lacked private
firmware fixtures. After the immutable local copies, both legacy HPS tests pass.
The standalone save-sector bench failed word-zero roundtrip with both original
baseline bridge and the default-mode extended bridge. It sampled the now
synchronous HPS BRAM before a clock after changing address. The fixture now
prefetches/ticks before sampling; maintained RTL was not changed for this failure.

Flash-reset and dependent memory-owner benches initially failed elaboration:
their CPU stubs predated the existing `LINE_REFILL` parameter/ports. The three
reset stubs now expose the current disabled line interface and drive requests
inactive. These are fixture repairs, not CPU, reset or peripheral behavior edits.
Failure summaries and retained pristine/stub logs are in `scratch/ngage2-integration/p0/`.

## Completion results

Full `tests/cpu/run.sh`: **180 PASS**, exit0. Thirteen selected phone suite
entry points pass, including all corrected fixtures, legacy actual-HPS/NOR,
full-size save manager, scalar sector, dirty/reset/diagnostic, flash reset,
line/owner and physical SDRAM/DDIO/short-read coverage. Source graph171files,
9QIPs and structural top elaboration pass. New raw-stage tests are recorded in
`merge-plan.md`. See `scratch/ngage2-integration/p0/completion.json` for final
counts, failures, source identities and exact log locations.

The initial `source.json` describes capture time before fixture copies. This
completion paragraph and `fixtures.json` supersede its initial firmware-copy
statement: later tests read/compare immutable firmware bytes without executing
them. Donor baseline remains `e3d2bf778319bdf4ef2bf21a4fc7376186b00a63`, read only.
