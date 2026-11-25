# Qualify posted SDRAM writes from the existing slot

The [exact Git patch](patches/sdram-post-capacity.patch) applies to
`e11a637`. It removes the scheduler's `cmd_ready` from the capacity
check that drives the posted CPU ACK. An empty slot still ACKs a write
on its original edge. The payload can bypass to the scheduler on that
edge or enter the slot if the scheduler is busy. If a write finds the
slot full, it waits until the existing entry has drained. This can add
one clock on a full-slot replacement. It uses the existing storage and
keeps the prior order for queued writes, scalar reads, lines and SWP.
The scheduler's initialization flag still participates in readiness.

This targets the retained hot rank 2 path on seed 13 and rank 1 on
seed 31337. Both run from the SDRAM scheduler through `cmd_ready`,
the posted ACK and the I-cache strobe to the Wishbone address register.
Their hot slacks are −2.055 ns and −2.278 ns. The one-slot capacity
decision should remove that `cmd_ready` arc. The rest of the path and
the other timing limits need a routed measurement.
[Retained seed 13](https://github.com/asturur/test_template_1/actions/runs/45414703565) ·
[Retained seed 31337](https://github.com/asturur/test_template_1/actions/runs/45414709004)

The mixed census on the retained stream saw all 19,075 posted writes
go through the direct path. It saw zero replacements and zero blocked
offers. The directed test queues a masked scalar write while the
scheduler stalls, offers a 16-byte block against the full slot, and
checks that dequeue preserves the first payload while the second waits
for registered capacity. The retained version fails that dequeue-edge
assertion. The 104 MHz physical SDRAM stream test matched the retained
summary for 1,048,650 commands, including the full scrub. It passed
refresh, packet masks, scalar and line replies, SWP and reset drain.
The mixed replay matches 171,496 trace records over 1,201,547 clocks,
including LCD, PCM and MMC persistence.

All 15 fixed workloads matched cycle for cycle across 105 windows,
including ordered guest events and the cycle-stamped write trace.
Native PolyCount took 57,508,501 clocks over four frames, 130 more
than control (+0.00023%). The ordered architectural digests, WB
write count (278,165) and output match. The cycle-stamped native
write trace changed, and it recorded 5,401 additional stalled
write-offer clocks. [Replay counts](../../evidence/v5-104-sdram-post-capacity.json)

## Routed comparison

The production fits use `ff66e03`, 104 MHz and DDR debugging disabled.
The fit manifests match the retained QSF and change only the SDRAM
stream among the 133 compiled inputs.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45688763667) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45688761432) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45688759230)

| Seed | Retained setup slack (ns) | Capacity setup slack (ns) | Retained ALMs | Capacity ALMs |
| ---: | ---: | ---: | ---: | ---: |
| 43 | −2.508 | −2.588 | 36,446 | 37,123 |
| 13 | −2.061 | −2.708 | 36,420 | 37,217 |
| 31337 | −2.471 | −2.310 | 36,461 | 37,069 |

In the 100 °C top-1,000 lists, named `cmd_ready` paths through the
posted decision fall from 0, 52 and 103 to zero. Named posted ACK
paths into the merger fall from 26, 34 and 54 to zero. Median core
setup TNS improves by 822.484 ns to −4,321.167 ns. Median worst setup
moves from −2.471 to −2.588 ns and median area rises 677 ALMs. Each
fit uses 321 M10Ks. All three pass hold, recovery, removal and minimum
pulse width and miss setup.

The new limiting paths include the D-cache return into the CPU M
packet, refill state into the Wishbone address, and TLB physical
address into the D-cache lock decision. Seed 31337 produced the best
candidate bitstream at `build/fit/v5-104mhz-ff66e03-seed31337/ngage1.rbf`.
Hardware behavior remains unverified. The build branch still points to
`ff66e03` for testing. [Matched fit evidence](../../evidence/v5-104-sdram-post-capacity-fits.json)

## Reproduce

Prepare the [write-data workloads](prepared-wb-write-data.md) and their
mixed reference. Use the [posted-ACK replay fixture](cpu-posted-sdram-ack.md#replay)
for the retained guest retirement observer.

```sh
catalog=docs/experiments/v5-performance
fit=scratch/v5-fit-loop
area=$fit/sdram-post-capacity
git apply "$catalog/patches/sdram-post-capacity-replay.patch"
mkdir -p "$area/source"
git archive e11a637 | tar -x -C "$area/source"
git apply --directory="$area/source" "$catalog/patches/sdram-post-capacity.patch"
cp "$area/source/rtl/ngage_cpu.sv" "$area/"
cp "$fit/cpu-posted-sdram-ack/architectural_trace.vh" "$area/"
cp "$fit/cpu-posted-sdram-ack/wb-write-trace.vh" "$area/"
iverilog -g2012 -s post_capacity_tb -o "$area/post-capacity-test" \
  "$area/post_capacity_tb.v" "$area/source/rtl/ngage_sdram_stream.v"
vvp "$area/post-capacity-test"
for measure in fixed native; do
  python3 -B "$area/replay.py" "$measure" --output candidate
done
(
  export PHONE_SDRAM_SYS_HZ=104000000
  export PHONE_SDRAM_MODEL="$PWD/build/sim/unit-hardware-boot-real-sdram/mt48lc16m16a2-verilator.v"
  cd "$area/source"
  mkdir -p build/sim
  sh tests/phone/sdram/run-stream.sh registered-post-capacity
)
```

Run `python3 -B "$area/mixed.py"` from the repository root. Build
`build/sim/v5-104-sdram-post-capacity-pin-mixed/mixed` with its `build.sh`
and run `obj/Vtb` with `+upp_stress` and `+compare_trace` as in the
write-data example. Compare against the retained mixed trace.
