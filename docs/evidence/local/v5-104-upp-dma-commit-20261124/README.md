# Isolate DMA programming commit from the UPP response bank

The [incremental RTL patch](dma-commit.patch) applies to
`4c02fda`, the two-edge UPP trial. It feeds the separate DMA register
port its existing bus authorization and registered DMA claim directly.
Other peripherals keep the original bus authorization logic, ownership,
two-edge maturity and raw-access bypasses.

When the DMA programming port claims a packet, it already overrides
both the maturity/early-access and peripheral-pending gates. Write
and selector effects explicitly require that claim. START and STOP
require the valid decoded offset 0x08 within a known DMA register
window, so they also imply the claim. Restricting the separate commit
to an active DMA claim therefore preserves every DMA effect, including
a stop withdrawing a pending offer on the grant edge.

The new path does not need to reconstruct which overlapping device
makes a UPP access fast. In particular, claims on the ASIC ROM stub
or the 4 KiB SRAM lane, including priority at the shared boot scratch
range, remain as before. So do raw DDR entry and MDI's `0x0c10`
overlaps, MMC host transport, LCD and PCM access cadence, and direct
SDRAM/flash routing. The held packet registers, maturity, response
flops, SDC, and post-fit audits are byte-identical.

Both available 100 °C detailed fits of the original two-edge trial
show their worst path from the held address through the fast-lane
qualification into the DMA engine. Seed 43 goes through ICU/extra
ownership and seed 31337 through MDI and GPIO loopback. The latter
then passes through LCD stream request and DMA route into
`source_left` with −3.664 ns of slack. Its −40 °C worst path goes
through boot scratch ownership and DMA `cmd_valid` into the SDRAM
arbiter at −3.649 ns.

The 104 MHz mixed pin-model test matches all 171,501 cycle-stamped
records and all 128 PCM sample values against `4c02fda`. The separate
[ARM alias probe](gpio-boot-alias.S) checks both ends of the ASIC ROM
stub page, the first and last boot-scratch words and the adjacent
comm-RAM words. Its 326 pin-model records match. The staged DMA miter
checks starts, stops, stalls, cancellation, wrong channels, reset and
unrelated MMIO while an offer is held. It compares all 32,978
clocks, including 32 clocks with differing commit inputs and no
claimed DMA access. [Measured receipt](receipt.json)

The [miter patch](dma-commit-miter.patch) adapts the existing staged
DMA fixture. Apply it only on a disposable copy of `4c02fda` and
select `dma_commit_miter` as the Icarus top in place of
`program_predecode_tb`. The [two-edge trial recipe](../../../experiments/v5-performance/upp-two-edge.md#reapply-and-verify)
supplies the mixed fixture. Compile the alias guest with the same
linker and source recipe as the GPIO/EUART stress.
