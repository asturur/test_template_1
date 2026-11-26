# Capture SDRAM block data on the arbiter's free edge

The [design patch](patches/sdram-block-payload.patch) applies to the timer baseline `9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e`, tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. `Template.sv` enables `PRECAPTURE_BLOCK_DATA` beside the established CPU block-write option. The parameter defaults to zero, preserving the original payload capture for other callers. The production capture enable is now `!reset && state == FREE` across all 128 bits.

Every accepted CPU block starts in FREE, so its data is captured on its grant edge. The separately registered request, owner, block qualifier and lock still determine when that data is valid. ACTIVE holds the data until ACK or reset. DMA and scalar CPU handoffs select scalar data. A younger CPU request or a changing live lock cannot modify an active packet.

The SDRAM stream sees a valid direct or locked write only with an active request. A queued posted write copies the payload into the stream's own pending register at its ACK edge, then drains from that copy through logical reset. The scheduler can sample tentative data into its empty slot, but issues only a valid command with its held payload. A cold or free-cycle unknown value at the arbiter output therefore cannot reach a physical request. A pin scrub uses zero data. The capture may toggle idle payload bits more often. Area, slack and power effects require a fit.

## Timing witness

The timer baseline's top-1,000 setup exports contain the following paths ending at `ram_arbiter.mem_block_data`. The sample includes all four corners in the receipt. The fast exports have zero negative paths to this endpoint.

| Seed | Slow hot negative / below −1.5 ns | Slow hot worst | Slow cold negative / below −1.5 ns | Slow cold worst |
| --- | ---: | ---: | ---: | ---: |
| 13 | 87 / 0 | −1.311 ns | 115 / 0 | −1.201 ns |
| 43 | 135 / 95 | −1.940 ns | 135 / 82 | −1.805 ns |
| 31337 | 108 / 58 | −1.868 ns | 113 / 42 | −1.740 ns |

The dominant late sources include UPP peripheral and CPU write-owner controls. The capture switch removes grant, write direction and block decode from the wide data-register enable. The MiSTer scheduler remains the same. The donor SDRAM controller has comparable packed write data on its command interface, with a different producer and owner boundary. [Exact path census](../../evidence/v5-104-sdram-block-payload-routes.json)

## Qualification

- The Verilog-2001 miter compared original, default and production modes over 65,543 cycles. It covered 3,107 qualified blocks, 1,314 contending CPU block grants, 1,830 locked grants, 2,928 held cycles with changing inputs and 183 reset cancellations. It injected unknown tentative data after cold reset and on the live bus behind a held block. The original and default modes matched all bits, including unqualified payload. The production output matched whenever the payload was qualified.
- The 104 MHz physical SDRAM stream fixture matched all checks including a complete 16 MiB cold scrub, command ordering, refresh, a pending posted block draining through reset, and a locked block completing at the pins with the original held payload.
- Both standard mixed traces match timer-only control. The normal replay is 171,496 records at 1,201,547 clocks. The timer/MMC/LCD replay is 171,497 records at 1,201,528 clocks. Their only block writes are the cold scrub. A separate guest keeps the original mixed workload bytes through its final success store, then dirties and evicts an ARM D-cache line. Both pin traces match at 172,060 records and 1,204,706 clocks. They contain two full-mask CPU block writes to `0x0a005d00` and `0x0a005d10` with all eight expected words, followed by guest readback.
- All 105 fixed windows and four native frames match the timer baseline, including cycle counts, guest outputs and architectural and Wishbone-write digests. Verilator records the exact candidate arbiter fingerprint in those decks and both pin-model fixtures. Each testbench opts into the production capture explicitly.

[Qualification receipt](../../evidence/v5-104-sdram-block-payload.json)

## Reproduction

Restore the helpers from the [replay patch](patches/sdram-block-payload-replay.patch) at the repository root. Use the existing frozen timer and retained replay decks, pinned Verible, cached Jotego image and established ARM cross-toolchain.

```sh
area=scratch/v5-fit-loop/sdram-block-payload
prior=scratch/v5-fit-loop/timer-live-trust-combined/dispatch-20261126
out=build/sim/v5-104-sdram-block-payload
mkdir -p "$area/reference" "$area/source" "$out"
for leg in reference source; do
  env GIT_OBJECT_DIRECTORY="$PWD/$prior/objects" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$prior/alternate-objects.txt")" \
    git archive 9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e Template.sv .rules.verible_format \
      rtl tools tests/cpu/arm9v2_board tests/cpu/spmark_payload tests/phone/upp_ddr_ram/peer.v \
      tests/phone/mmc_mister tests/phone/sdram sim/programs/link.ld | tar -x -C "$area/$leg"
done
git apply --directory="$area/source" docs/experiments/v5-performance/patches/sdram-block-payload.patch
cp scratch/v5-fit-loop/timer-write-prepare/architectural_trace.vh "$area"
cp scratch/v5-fit-loop/timer-write-prepare/wb-write-trace.vh "$area"
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
docker image inspect -f '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
sh "$area/arbiter.sh"
sh "$area/stream.sh"
sh "$area/mixed.sh"
sh "$area/block-guest.sh"
for kind in fixed native; do
  python3 -B "$area/replay.py" "$kind" --output qualification
done
python3 -B "$area/routes.py"
python3 -B "$area/record.py"
```
