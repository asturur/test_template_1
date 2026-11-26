# Store the D-cache background load lock as a tag and valid bit

The [design patch](patches/dcache-compact-lock.patch) applies to the timer-only build `9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e`, tree `0ccd13d8cd502bc14d3b89c6431ff0ebe4745612`. The phone wrapper opts into `COMPACT_LOCK`. That branch keeps the existing valid and six-bit tag registers, registers a scalar critical return alongside the existing data and write-mask registers, and derives the held and advancing lock decisions from tag equality. The bitmap is decoded for observers. The default branch retains bitmap storage, both `LOCK_SPLIT` options and the existing bitmap/valid assertion.

## Same lock ownership and return edge

Reset clears the token, return pulse, owner decisions and legacy bitmap. Admission can install a lock in only two read-miss branches of IDLE. The branch either starts a fetch or starts an aliasing dirty victim writeback. Starting that writeback requires `victim_alias`, which makes its captured `defer_writeback` false. Its only exit is therefore FETCH_SINGLE. TLB/alignment faults, TLB busy responses, uncached traffic, hits and stores do not install a lock.

For an admitted read, the cache captures read direction, destination mask and physical tag on the same edge. They hold through the fill. The core's W move expression also updates its one-hot load mask and selects M as the next W packet. The admit-time binary destination and mask therefore describe the same W register. Simulated compact instances assert this relationship. Redirects may change the live CPU inputs, but they cannot change the captured fill owner.

The 32-byte fetch starts at beat zero and advances by one per accepted ACK or bus error. The addressed critical word emits the captured destination mask on the same edge that the new scalar pulse captures `critical_take`. Exactly one beat matches a read's critical word. A fetch cannot reach its last beat before the critical beat, and its next states leave at least one intervening cycle before IDLE. Thus a fully completed fill clears its token before a new miss can install. An interrupted fill can instead end by reset, which clears the state and token together. A returning bus error follows the original fetch progression and the original return-data behavior.

For each owner check, the surviving old lock contributes exactly when the old token is valid, the registered critical return is absent and that owner equals the tag. The current install contributes exactly when the new destination equals the owner. Both terms still feed the same owner and return registers on the original edge. Returning the old owner and installing a new owner together selects the incoming tag. The paired fixture injects that registered state to test priorities independently of natural admission order.

Inside the phone core, `i_dc_lock`'s low bits only pass through `i_locked` to an unused decoder input. `RETURN_READY_FF` is enabled and consumes `o_lock_return`. The bitmap remains observable at `o_lock` and available to the legacy return-ready option. The CPU's separate registered mask and parallel results continue to drive writeback, forwarding and error behavior.

## Routed motivation and the new path

On the timer control, `o_lock_any` occurs in all six slow-corner top-1,000 exports. Seed 13 cold is ranked first at −2.214 ns, with 10.994 ns data delay and eight levels from TLB physical address bit 6. Its hot equivalent is ranked sixth at −1.980 ns. Seeds 43 and 31337 have the destination in both slow exports, reaching −2.030 and −1.607 ns. The prior valid-only trial removed that endpoint while retaining the bitmap, and its owner endpoint still appeared in three slow exports across two seeds. [Path census](../../evidence/v5-104-dcache-compact-lock-routes.json)

The phone branch removes 64 bits of RTL bitmap storage and adds one scalar register. It removes variable-index writes, the 64-bit next-bitmap reduction and indexed bitmap/mask reads for held and advancing owners. The late lock admission still drives valid directly. The critical beat now has one extra registered destination beside the existing data and mask captures. Its Wishbone ACK/error fanout and the two direct equality checks into owner/return need routed measurement.

## Qualification

- The exact FSM differential exhausts 262,203 Boolean next-state cases, including 576 admission vectors and two resets. The previous 1,064,960-transition lock formula check and the existing 64-tag fixture pass both retained and legacy candidate paths.
- A three-FSM directed test compares the retained FSM, candidate default bitmap and compact opt-in over 1,281 cycles. It covers held/advance selection, hit under miss, aliasing dirty writeback, an error on the final critical read beat, uncached abort, resets with a live request and reset coincident with the critical ACK. Two injected same/different-tag return-plus-install cases preserve the incoming owner.
- The four ARM9v2 board profiles, 105 fixed windows and four native frames match the exact timer control, including cycles, guest outputs, architectural events and Wishbone write digests. Both physical decks match all records. The normal replay has 171,496 records over 1,201,547 cycles. The timer/MMC/LCD overlap has 171,497 records over 1,201,528 cycles. Each mixed deck has 114 source inputs with only the generated CPU netlist changed.
- Pinned generator checks pass for both legs. Verilator fingerprints match across the board, fixed, native and physical candidate builds.

[Qualification receipt](../../evidence/v5-104-dcache-compact-lock.json)

## Reproduction

Use the frozen timer-only control decks, the pinned Jotego image and the established ARM cross-toolchain. Restore the helpers from the [replay patch](patches/dcache-compact-lock-replay.patch) in the repository root.

```sh
area=scratch/v5-fit-loop/dcache-compact-lock
catalog=docs/experiments/v5-performance/patches
prior=scratch/v5-fit-loop/timer-live-trust-combined/dispatch-20261126
out=build/sim/v5-104-dcache-compact-lock
mkdir -p "$area/reference" "$area/source" "$out"
for leg in reference source; do
  env GIT_OBJECT_DIRECTORY="$PWD/$prior/objects" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$prior/alternate-objects.txt")" \
    git archive 9f16d1a5b5bd5b255eb8f0b1a131399b7dcfb56e rtl tools tests/cpu/arm9v2_board \
      tests/cpu/spmark_payload tests/phone/upp_ddr_ram/peer.v tests/phone/timer_conformance/tb.v \
      tests/phone/timers/tb.sv sim/programs/link.ld | tar -x -C "$area/$leg"
done
git apply "$catalog/dcache-compact-lock-replay.patch"
git apply --directory="$area/source" "$catalog/dcache-compact-lock.patch"
for leg in reference source; do
  python3 -B "$area/$leg/tools/gen_arm9v2_phone.py" --stock build/arm9v2-assoc/stock-pinned.v --check
done
cp scratch/v5-fit-loop/timer-write-prepare/architectural_trace.vh "$area"
cp scratch/v5-fit-loop/timer-write-prepare/wb-write-trace.vh "$area"
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"
docker image inspect -f '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
sh "$area/directed.sh"
python3 -B "$area/prepare-state-proof.py"
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$out/state-proof:/proof" -w /proof --entrypoint sh jotego/simulator:arm64 \
  -ec 'iverilog -g2012 -s tb -o miter tb.sv reference.v trial.v region.v && vvp miter > run.log'
sh "$area/board.sh"
for kind in fixed native; do
  python3 -B "$area/replay.py" "$kind" --output qualification-final
done
sh "$area/mixed.sh"
python3 -B "$area/routes.py"
python3 -B "$area/record.py"
```
