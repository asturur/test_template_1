# Isolate the register-shift count from a live load

The [Git patch](patches/live-rs-prep.patch) starts from `e11a637`, the
retained 104 MHz tree. It sources the fast ARM register-shift count from
the registered no-hit grant and reads a W-stage ALU count directly. A
count that depends on a returning W-stage load goes through the existing
held-count path and spends one extra preparation clock when it would
otherwise issue directly. W-stage auxiliary results already use that
path. Ordinary load forwarding, including into the operand being shifted,
still uses the existing hit path.

## What the retained core does

The passive census checks S-to-A acceptance for a direct ARM register
shift whose winning Rs producer is a live W-stage load. There were zero
such accepts in 105 windows from 15 workloads and four native PolyCount
frames. The broader execute-stage load path was much busier. Same-cycle
returning values were present at execute completion on 254,249 of
2,395,767 clocks in a steady Sega Rally scan window (10.61%) and on
1,607,751 of 57,508,371 native clocks (2.80%). These counts measure how
often the bypass is used. A stall's measured workload cost can differ.

In the 100 °C top-1,000 exports for retained seeds 43, 13 and 31337,
46, 40 and 30 paths traversed execute and one of the named live-cache
word, trust, hit or W load-select signals. The first ranked 19th, 24th
and 155th. The narrower trust-through-Rs-wait-to-rotate path was absent
from all three exports. It appeared 23 times in the parked posted-ACK
trial's seed 43 and was its worst path at −2.734 ns. The candidate
remains unfitted. Routed improvement for the retained build is open.

## Simulation

The directed differential passed 3,093 register and immediate shifts
against an independent ARM value and carry oracle. It covered each of
the 256 counts in all four shift modes for W auxiliary, W primary ALU
and W primary load. It also checked load trust, M priority, backpressure,
flush, RRX and shifting a live loaded Rm. The 15 fixed workloads and
four native frames matched clocks, outputs, ordered guest retirement,
memory and MMIO hashes and the valid write trace. All four focused
board profiles and 171,496 mixed events matched, including LCD, PCM,
MMC persistence and the physical SDRAM pin model.
[Replay counts](../../evidence/v5-104-live-rs-prep.json)

## Next timing target

The retained seed 13 hot rank 2 path (−2.055 ns) and seed 31337 hot
rank 1 path (−2.278 ns) both start at the SDRAM scheduler's `ready_q`.
They traverse `cmd_ready`, `phone_sdram.post`, `cpu_ack` and the
I-cache strobe into the Wishbone address. Retained seed 43 also
has a posted-write-to-address path at hot rank 3. The previous
[CPU reply register](cpu-posted-sdram-ack.md) removed the sampled
paths by delaying each posted acknowledgment. It made whole-core
slack and mixed behavior worse.

The retained mixed replay took the direct route for all 19,075 posted
writes. It never replaced a queued write on its dequeue edge. That
supports starting with the [existing slot's registered capacity](sdram-post-capacity.md).
An overflow entry would restore same-edge replacement if benchmarks
find the added clock matters.

## Reproduce

Prepare the [write-data workloads](prepared-wb-write-data.md), their
mixed reference and the DMA reference listed there. Apply the
[replay helper patch](patches/live-rs-prep-replay.patch).

```sh
catalog=docs/experiments/v5-performance
fit=scratch/v5-fit-loop
candidate=$fit/live-rs-prep
census=$fit/live-w-load-census
git apply "$catalog/patches/live-rs-prep-replay.patch"
for area in "$candidate" "$census"; do
  mkdir -p "$area/source"
  git archive e11a637 | tar -x -C "$area/source"
  cp "$area/source/rtl/ngage_cpu.sv" "$area/"
  cp "$fit/prepared-wb-write-data/architectural_trace.vh" "$area/"
  cp "$fit/prepared-wb-write-data/wb-write-trace.vh" "$area/"
done
git apply --directory="$candidate/source" "$catalog/patches/live-rs-prep.patch"
git show 3363c87:rtl/arm9v2/arm925t_phone.v > "$candidate/directed-reference.v"
python3 -B "$candidate/source/tools/gen_arm9v2_phone.py" --stock build/arm9v2-assoc/stock-pinned.v --check
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$candidate:/stage" -w /stage/source --entrypoint sh jotego/simulator:arm64 \
  -ec 'sh tests/cpu/arm9v2_board/run-wb-rs.sh ../directed-reference.v'
for measure in fixed native; do
  python3 -B "$census/replay.py" "$measure" --output census
  python3 -B "$candidate/replay.py" "$measure" --output candidate
done
```

Use the [focused ARM fixture](early-shift-select.md#reapply-and-verify)
against `e11a637` and the candidate. For the pin model run
`python3 -B "$candidate/mixed.py"` from the repository root. Build
the resulting `build/sim/v5-104-live-rs-prep-pin-mixed/mixed` leg with
its `build.sh` and run `obj/Vtb` with `+upp_stress` and
`+compare_trace` as in the prepared write-data example. Compare the
trace byte for byte against the retained mixed leg.

For the queue census, run `python3 -B "$candidate/post-capacity.py"`
and use the same pin-model commands in
`build/sim/v5-104-post-capacity-census-pin-mixed/mixed`. The bench prints
one `POST_CAPACITY` line at the end. Compare its traffic trace to the
same retained mixed leg.
