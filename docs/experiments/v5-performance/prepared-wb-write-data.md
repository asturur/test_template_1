# Prepare D-cache Wishbone write data before ACK selection

The [RTL, generator and directed test patch](patches/prepared-wb-write-data.patch)
applies to public `a846b87`. The trial is `e9552bd`.

On the retained physical 104 MHz tree, the refill `cpu_ack` path reached
Wishbone merger `data_data_ff` through tag-maintenance next-data logic on
seeds 43 and 13. On seed 31337 it went through the D-cache TLB owner
selection, even though its walker only reads. The affected paths ranked
third, first and third in the 100 °C reports, with slack of −2.189,
−2.476 and −2.342 ns.

The tag-maintenance writer samples the current and successor words in
parallel and registers the existing `take` decision on the same edge.
The registered decision selects the word. The cache controller keeps
its existing captured data, and the posted-store FIFO's successor is
sampled on the same request edge. The original registered D-cache
owner selects the prepared data, then the existing registered I/D
owner selects the external result. Addresses, byte enables, cycle
type, arbitration, replies and request timing use the original logic.
Idle and read beats do not consume write data. Scalar eviction and
posted FIFO advancement still have a real ACK-dependent next word.

This differs from the [Wishbone payload-banks trial](historical/wishbone-payload-banks.patch).
That experiment also moved address selection after capture and left
the tag writer's live current/successor data mux intact.

## Matched write census

The observer records every valid CYC/STB/WE offer and its cycle,
address, lane mask, CTI, lock, data and response. For native writes it
also records the full 16-byte payload. Read ACKs count separately.
The changed-payload count considers an immediate valid write after a
successful write ACK. Read-to-write counts describe adjacency and do
not imply a read ACK supplied write data.

| Timed test | Read ACKs | Write ACKs | Stalled write clocks | Read ACK followed by write | Write ACK followed by changed write payload |
| --- | ---: | ---: | ---: | ---: | ---: |
| 105 windows across 15 fixed workloads | 393,755 | 52,087 | 52,087 | 3 | 8,554 |
| Four native PolyCount frames | 5,944,584 | 278,165 | 530,081 | 5,781 | 27,686 |

The fixed writes were native dirty evictions. Native PolyCount issued
18,535 native eviction writes and 259,630 posted writes. It had 7,491
changed eviction successors and 20,195 changed posted successors.
All measured workload cycles, outputs, ordered architectural digests
and the cycle-stamped valid write digests matched the control.

## Directed and pin-model qualification

The ordinary timed windows issued zero tag-maintenance writes. The
initial directed guest missed the write observer's coverage gate.
The final guest deliberately writes distinct words to a dirty victim,
checks all eight backing words after eviction and separately issues
posted word, halfword and byte writes. The reference and trial matched
all four ordinary board profiles in both scalar and native writeback
modes, plus a stalled-write reset and restart in each mode. Each
profile acknowledged 2,076 tag-maintenance words and recorded 522 ACKs
followed by a changed tag word. The cases covered backpressure, the
last-beat I/D and cache/TLB-owner transitions, a rejected scalar store,
read and refill errors, translation retry, SWPB, and lane masking.
Each scalar profile saw 12 dirty eviction words, and each native
profile saw three 16-byte eviction blocks.

The 104 MHz pin-model replay matched all 171,496 events and 1,201,547
clocks, including native LCD, PCM, MMC persistence and physical
SDRAM commands and data. [Qualification and write census](prepared-wb-write-data-replay.json)

## Reapply and verify

Run in the repository root with pinned stock netlist, ARM GNU tools,
and the installed offline Jotego simulator.

```sh
area=scratch/v5-fit-loop/prepared-wb-write-data
catalog=docs/experiments/v5-performance
mkdir -p "$area/source"
git archive a846b87 | tar -x -C "$area/source"
git show a846b87:rtl/arm9v2/arm925t_phone.v > "$area/reference.v"
git show a846b87:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
git apply --directory="$area/source" "$catalog/patches/prepared-wb-write-data.patch"
python3 -B "$area/source/tools/gen_arm9v2_phone.py" --stock build/arm9v2-assoc/stock-pinned.v --check
(
  cd "$area/source"
  sh tests/cpu/arm9v2_board/run-wb-data-contract.sh ../reference.v
)
```

Prepare the [checked DMA predecode reference decks](dma-command-predecode.md#reapply-and-verify)
using `--output final-replay` and apply the
[replay helper patch](patches/prepared-wb-write-data-replay.patch).
The workload observer traces only valid writes and counts the
response and owner classes. Run both measured variants.

```sh
git apply "$catalog/patches/prepared-wb-write-data-replay.patch"
for measure in fixed native; do
  python3 -B "$area/replay.py" "$measure" --control --output control
  python3 -B "$area/replay.py" "$measure" --output candidate
done
```

For the pin model, run `prepare-mixed.py` twice with
`prepared-wb-write-data-control-pin` and `prepared-wb-write-data-pin`
using the [DMA predecode pin replay commands](dma-command-predecode.md#reapply-and-verify).

The production fits pin `e9552bd` at physical 104 MHz with DDR
debugging off. Preflight verified 132 selected source hashes and the
effective QSF against the retained control for each seed. The generated
CPU netlist is the only changed fit input.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45414696142) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45414703565) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45414709004)

## Routed results

Retained `e9552bd`. Median setup improved by 0.094 ns and median
area fell by 196 ALMs. The fit kept 321 M10Ks. Median core setup
TNS worsened by 993.367 ns, and seed 43's setup regressed. Seed 13
reached −2.061 ns. Counts into the old write-data register from the
named refill ACK path fell from 32, 7 and 30 to zero in the three
100 °C top-1,000 exports. These counts follow routed names and the
report cutoff. All three fits failed setup and passed all other
four-corner checks. [Matched fits and archived bitstream](../../v5-alm-storage-results.md#prepared-wishbone-write-data) ·
[Fit evidence](../../evidence/v5-104-ack-write-data-fits.json)
