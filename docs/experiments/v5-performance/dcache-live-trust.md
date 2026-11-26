# Simplify D-cache live-hit trust

The [design patch](patches/dcache-live-trust.patch) applies to `11c4a0c`, the exact retained `e9552bd` tree.
The generator keeps the original live-trust register and now sets it from
`hum_slot_nxt || (state_nxt[IDLE] && !o_fill_busy)`. The full next-fill
decode continues to drive its existing outputs and unrelated consumers.
The live-trust reset value and sampling edge are unchanged.

## Equivalence

Reset sets exactly the IDLE bit. The transition block starts with the
old state, selects a single case arm, and holds the state or clears the
current bit and sets one successor. The three-way branches are exhaustive
partitions. Deferred writeback and write unlock use `keep_more` and
`wait1_ff` to select IDLE, RELOOKUP1 or RELOOKUP2. The register unlock
uses stored write direction and pending access to select UNLOCK_WR,
RELOOKUP0 or IDLE. The other arms hold or set a single successor when
their condition is true. Alignment and TLB faults leave IDLE selected,
and Wishbone fault completion takes the same state path as ACK. Redirects
can change the requests presented to the FSM. They have no separate
state assignment. The reset and transition assignments establish one-hot
state by induction.

A next hit-under-miss slot requires one of CLEAN_SINGLE, FETCH_SINGLE or
UNLOCK_WR. All three set the next-fill decode, so the original trust
expression is true for that slot. With next IDLE selected, the one-hot
state rules out all next-fill states and trust requires the current fill
to be idle. Both expressions are false when neither condition holds.

A differential bench copied the exact generated FSMs, forced the direct
branch conditions independently, and checked 262,203 next-state cases.
A second pass clocked both trust registers for all 14 one-hot next-state
encodings and every combination of the five input predicates, 448 cases, plus
cold and warm reset. The pinned generator check passed in both legs.

## Routed motivation

The retained census finds `u_zap_cache_fsm.o_live_trust` in 39 of the
40 top-1,000 setup exports. The path is below −1.5 ns at all ten hot
slow corners and eight cold slow corners. The worst measured route starts
at the D-side TLB walk output in seed 6, at −2.579 ns hot and −2.428 ns
cold. Seeds 43 and 1 also rank the destination fifth in the hot export
at −2.389 ns and −2.373 ns. Their worst launches are the SDRAM arbiter
write-enable register.

The detailed seed 6 hot witness traverses the TLB fault logic, the next
state and the hit-under-miss logic before the final trust cell. That
hit-under-miss path still exists. The RTL removes the alternate full
next-fill decode from the destination cone. A fitter can potentially
absorb the final condition into one LUT in both versions. Routed path
length, slack and area remain unmeasured for the candidate.

The production triplet uses `f6ae7f6`, a child of forward restore
`5abddb8`, at physical 104 MHz with DDR debugging off. The restore's
tree is identical to the retained control.
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45818144877) ·
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45818145038) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45818144548)

## Workload qualification

The four ARM9v2 board contract profiles match with the retained
half-writeback and two-way XOR fixtures. All 105 fixed windows match,
including the repeated runs and negative-output checks. All four native
PolyCount frames match at 14,391,395, 14,467,552, 14,346,201 and
14,303,223 clocks, with matching guest output and architectural and
valid-write digests. The physical SDRAM model matches all 171,496 trace
records and 1,201,547 clocks with LCD, PCM, MMC persistence and both
UPP DDR banks active. The generated CPU netlist is the sole differing
input across the 114 physical model source hashes.
[Qualification receipt](../../evidence/v5-104-dcache-live-trust.json)

## Reproduction

Run from the repository root with the known frozen input decks,
prepared Wishbone write-data receipts and offline Jotego image. Restore
the scripts with the [replay helper patch](patches/dcache-live-trust-replay.patch). The pinned stock
netlist is `build/arm9v2-assoc/stock-pinned.v`.

```sh
area=scratch/v5-fit-loop/dcache-live-trust
catalog=docs/experiments/v5-performance
out=build/sim/v5-104-dcache-live-trust
mkdir -p "$area/reference" "$area/source"
for leg in reference source; do
  git archive 11c4a0c rtl tools tests/cpu/arm9v2_board tests/cpu/spmark_payload \
    tests/phone/upp_ddr_ram/peer.v sim/programs/link.ld | tar -x -C "$area/$leg"
done
git apply "$catalog/patches/dcache-live-trust-replay.patch"
git apply --directory="$area/source" "$catalog/patches/dcache-live-trust.patch"
for leg in reference source; do
  python3 -B "$area/$leg/tools/gen_arm9v2_phone.py" \
    --stock build/arm9v2-assoc/stock-pinned.v --check
done
cp scratch/v5-fit-loop/prepared-wb-write-data/{architectural_trace.vh,wb-write-trace.vh} "$area"
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
python3 -B "$area/prepare-proof.py"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$out/proof:/proof" -w /proof --entrypoint sh jotego/simulator:arm64 \
  -ec 'iverilog -g2012 -s tb -o miter tb.sv reference.v trial.v region.v && vvp miter'
sh "$area/board.sh"
for measure in fixed native; do
  python3 -B "$area/replay.py" "$measure" --output qualification
done
python3 -B "$area/mixed.py"
mixed="$out/mixed"
retained=build/sim/v5-104-more-ram-prepared-wb-write-data-pin-mixed/mixed
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD:/work" -w /work --entrypoint sh jotego/simulator:arm64 \
  -ec "sh '$mixed/build.sh'
'$mixed/obj/Vtb' +upp_stress '+compare_trace=$mixed/traffic.log' > '$mixed/replay.log'"
cmp "$retained/traffic.log" "$mixed/traffic.log"
python3 -B "$area/routes.py"
```
