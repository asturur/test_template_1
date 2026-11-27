# Capture A's right operand on the existing A-space edge

**Parked.** Production `ngage2_zap_top` uses the core default `S_AGU=0` and `PAYLOAD_FREE=1`. The timing trial requires `PAYLOAD_FREE && S_AGU`, so both private production candidates built the inactive branch. The matched workload and integrated test results below verify that inactive branch. The earlier readiness and preflight status did not establish active elaboration.

A separately forced `S_AGU=0` paired execute reproducer shows why enabling this implementation for production is unsafe. Both modules admit `LDR r2,[r1,#4]` with a zero base and expose address `0x00000004`. It retires as S is invalid with offset `0xc4` present on the unused input. The reference retains `0x00000004`; forcing vacant capture changes the raw address to `0x000000c4` immediately after that edge with both A valid bits low. Legacy mode preserves the address.

In non-S-AGU, `o_data_wb_adr_nxt` in RUN consumes the raw A address, and `check_ff[45:14]` can sample an invalid record's address. The D-cache's `victim_safe_nxt` and `line_safe_nxt` use `i_address_check` whenever `!cpu_wait`, without an access-valid qualifier. They feed `hum_slot_nxt`, registered `o_live_lookup` and `o_live_trust`. The directed witness establishes an electrical lookahead difference and the RTL shows its control consumer. It does not measure a complete guest-level timing failure. Making the gate accept-dependent again retains the investigated timing cone. This version is excluded from fits.

The trial starts at `ab75a622a80a5aedae347f63ae195f3da965815a`, tree `57cc1a796acc9b15a61522ccf2397230f38e9799`. The standalone candidate tree is `3cda36842d97f591bd9f46513e98cecdfe6d4cad`. The design patch changes the pinned generator and its emitted CPU. This reuses the current A register and clock edge. The opt-in requires `PAYLOAD_FREE && S_AGU` and is disabled in production. The standalone execute module's default takes its original `accept` edge, including for vacant payload bits. The optional hinted-LDM generator emits identical bytes.

## Routed timing witness

| Seed and slow corner | Leading path | Slack |
| --- | --- | ---: |
| 13 hot rank 1 | `w[541]` through `complete_class[0]` and `ready_if_hit` to `a[241]` | −2.006 ns |
| 13 cold rank 1 | Same W-valid launch, completion select and A endpoint | −1.994 ns |
| 13 hot rank 3 | Decode `o_forward_grant[25]` through operand select/rotate to `a[233]` | −1.943 ns |
| 13 cold rank 3 | W load owner `w[527]` through `direct_reg_shift` to `a[233]` | −1.946 ns |
| 43 hot rank 1 | W destination bit `w[93]` through `s_wait_w_nohit` and `ready_if_nohit` to `a[239]` | −2.636 ns |
| 43 cold rank 1 | Same W destination launch, no-hit wait and A endpoint | −2.570 ns |

The three endpoints are bits 23, 15 and 21 of the 32-bit right operand. Four sampled paths in each seed 13 slow corner launch at `w[541]` and go through `complete_class`. Two of those routes per corner end in A's right operand and two in the memory check record. The seed 43 hot/cold samples have 13 and 16 routes through `s_wait_w_nohit`, respectively. The cut removes the S-ready and packet-admission mux control at the A right endpoint for both hit arms. The rank 3 data cones still feed the right operand. Other A fields, valid, prepared shift bookkeeping and the early SMULL launch still require `accept`. The independently prepared W completion class changes the launch-side classifier and remains separately selectable.

## Same-edge equivalence

Let `h` select the current hit or no-hit arm. In the actual RTL, `finish = a_valid_common && a_ready_h && i_ready = a_finish_h` for the selected arm. Each `ready_if_h` requires `!a_valid || a_finish_h`. Since the hit selector also chooses `o_ready_payload`, every `accept = i_valid && o_ready` implies `space = !a_valid || finish`. Reset retains the full packet clear. Remaining edges follow three cases.

- On admission, write A-right on the same edge with the original shifted default, both ARM MEM immediates, signed BLOCK offset, BX/SWP raw right operand and Thumb SUFFIX immediate. If the same-edge late S return overrides it, port 1 still wins over port 0. The admitted packet retains all source wait and metadata priorities, including the late return clearing its wait bit.
- A live packet that cannot finish keeps its original `right_a` forwarding or A-side return update, with the original held data and normal product phase. The early DSP launch still requires acceptance. The scheduled DSP phase still requires an owned A record and its own product-ready flag.
- If an empty A or retiring A receives no packet, its right bits may capture an unused incoming value. A's valid bit is clear on that edge. A replacement that coincides with a branch redirect captures exactly the original new value, and the original `o_redirect` and `i_flush` sequencing kills the younger record. Retirement flags, compound register shift, redirect, SWP and CP15 still follow their current control edges.

`space` carries the real live A-finish dependency. `a_ready_hit/nohit` depends on A's latched producer match, its load owner and hit/trust inputs. `i_ready` is the core's `backend_ready`, which includes RUN memory state and `!wb_flush`. Product phase and flush/redirect can stop finish. The revised data mux also carries the existing W operand select, source tag grants, direct register shift and same-edge S return. Their path into A-right remains active, as do completion paths into other A fields and the check record. There is one A-right destination mux selected by A-space. Routed setup, hold and the additional vacant-edge switching cost are unmeasured.

## Invalid payload consumers with S-AGU enabled

The direct miter compares all controls, all non-right packet bits, the valid right operand, shift/held state, and DSP state. Six raw combinational outputs can derive from vacant A-right: result, ALU address, CPSR-next, PSR source, SWP write data and BX mode. The core loads those legitimate payloads with `input_record[541] = a_valid && backend_ready`, qualifies register write and load ownership with that bit, and qualifies memory access with record validity and the original request strobes. M/W may carry unchecked bytes when they carry an invalid record. The fast data address uses saved S-AGU output, which the miter compares on every edge. SUFFIX uses the A ALU result for the recorded return target when that instruction retires. The raw `ex_result` alias has only the unused sink in the generated core. The architectural fixture logs `wb_complete`, dbg data done and acknowledged MMIO, while the write trace requires the Wishbone transfer qualifier. Raw waveform inspection can show longer toggling of invalid-slot payload.

## Standalone replay

- The direct two-state miter compiles the actual paired execute modules with their standalone S-AGU default enabled. It runs 50,000 clocks in each mode with 6,967 admissions, 614 same-edge replacements, 29,484 valid input clocks blocked in free A, 11,568 prepared clocks, 395 dual S return overrides, 1,109 held A returns, 393 early SMULL launches and 853 owned product-phase clocks per mode. Both hit admission arms, both MEM immediate formats, all instruction-specific right selections, flush and redirect ran. Enabled mode changed the raw right bits on 30,566 invalid-slot samples. Default mode matched every observed bit, including invalid payload.
- Eight burst/wait board profiles match exact traces, including the SWP pair, page walks, clean write and prefetch abort. The four extended profiles also cover CP15 alignment, uncached external abort, preserved destination and the younger load to the same destination.
- All 105 fixed windows, 15 repeat results and 15 expected wrong-output rejections agree. Four native frames match at 14,391,395, 14,467,552, 14,346,201 and 14,303,223 clocks, with identical guest output and architectural and Wishbone digests.
- All four mixed pin modes agree byte for byte. The normal trace has 171,496 records over 1,201,547 clocks. Timer/MMC/LCD has 171,497 over 1,201,528. CPU block eviction has 172,060 over 1,204,706 and verifies full masks and guest readback. Warm CPU Hold during active MMC/HPS has 171,518 over 1,203,504, including the PCM reference and persisted CMD24 write. Verilator's compile manifests for native, fixed, board and pin executions identify the exact generated CPU. Board and pin replays in the asserted build exercise the inactive production setting.

## Archived private preflight with the opt-in disabled

Both histories descend from the exact W experiment tip `e2249e46c0bd47ab85539cff9416a51214c1ea05`.

| Former W contingency | Archived reference | Inactive private candidate |
| --- | --- | --- |
| PARK | Exact two-cut tree via restore `5a30e26583f81c4cd2415672f9f8bbfb6ed767d6` | `9f5d322f14efbd906e4b3cad512d7cb818538b01` |
| KEEP | W completion `e2249e46c0bd47ab85539cff9416a51214c1ea05` | `9bbdf13109412e0eadb7b39bc58ab1cecf777d8b` |

The stacked tree is `b32b59a09459101b98b75d762e5a7d53ab1eb50c`. In the generator the two independent transforms share a nearby definition and call site. The staged generator includes both complete functions with just two adjacent calls. Its execute module exactly matches A-only. Its core module matches W-only after eliding the single A opt-in connection. Both inactive replacement histories pass the 133-input production source manifests in all three 104 MHz DDR-debug-off seeds. In each case the only compiled-source difference from its selected reference is the generated CPU. The stage uses private object storage and indexes.

[Design patch](patches/a-right-payload.patch) · [Replay patch](patches/a-right-payload-replay.patch) · [Qualification receipt](../../evidence/v5-104-a-right-payload.json) · [Route census](../../evidence/v5-104-a-right-payload-routes.json)

## Reproduction

Run from the repository root with the cached Jotego ARM64 image. The pinned donor is `build/arm9v2-assoc/stock-pinned.v`. The frozen inputs are under `build/sim/{payload-clocks,polycount}/v5-104-all-four-ram-candidate` and use the compile deck `scratch/refill-issue-739d3bd/leg`. The archived `build/sim/v5-104-refill-payload-combined` experiment supplies exact workload rows and pin and guest fixtures. Guest overlays come from `build/sim/v5-104-sdram-block-payload`. Put both saved patches into the trial area before reconstructing the state.

```sh
set -eu
area=scratch/v5-fit-loop/a-right-payload
prior=scratch/v5-fit-loop/refill-payload-after-a-only/dispatch-20261126
base=ab75a622a80a5aedae347f63ae195f3da965815a
patches=docs/experiments/v5-performance/patches
git apply "$patches/a-right-payload-replay.patch"
cp "$patches/a-right-payload.patch" "$patches/a-right-payload-replay.patch" "$area"
mkdir -p "$area/objects" "$area/reference" "$area/source"
printf '%s:%s\n' "$PWD/$prior/objects" "$(cat "$prior/alternate-objects.txt")" > "$area/alternate-objects.txt"
(
    export GIT_INDEX_FILE="$PWD/$area/design.index"
    export GIT_OBJECT_DIRECTORY="$PWD/$area/objects"
    export GIT_ALTERNATE_OBJECT_DIRECTORIES="$(cat "$area/alternate-objects.txt")"
    test "$(git rev-parse "$base^{tree}")" = 57cc1a796acc9b15a61522ccf2397230f38e9799
    git read-tree "$base"
    git apply --cached "$area/a-right-payload.patch"
    git write-tree > "$area/design-tree.sha"
    test "$(cat "$area/design-tree.sha")" = 3cda36842d97f591bd9f46513e98cecdfe6d4cad
    for leg in reference source; do
        tree="$base"
        if [ "$leg" = source ]; then tree="$(cat "$area/design-tree.sha")"; fi
        git archive "$tree" Template.sv rtl tools files.qip .rules.verible_format tests sim/programs/link.ld \
            | tar -x -C "$area/$leg"
    done
)
cp "$area/source/rtl/ngage_cpu.sv" "$area/ngage_cpu.sv"

qualify () {
    name="$1"
    trial="scratch/v5-fit-loop/$name"
    out="build/sim/v5-104-$name"
    mkdir -p "$out"
    docker image inspect -f '{{.Id}} {{.Os}}/{{.Architecture}}' jotego/simulator:arm64 > "$out/image.id"
    sh "$trial/check-generator.sh"
    sh "$trial/proof.sh"
    sh "$trial/board.sh"
    sh "$trial/board-phase.sh"
    python3 -B "$trial/replay.py" fixed --output qualification
    python3 -B "$trial/replay.py" native --output qualification
    sh "$trial/pins.sh"
    sh "$trial/hold.sh"
}
qualify a-right-payload
sh "$area/non-agu-witness.sh"
python3 -B "$area/routes.py"
python3 -B "$area/record.py"

# The upstream W qualification and dispatch objects supply this variant's control.
python3 -B "$area/prepare-fit.py"
sh "$area/prepare-stack-replay.sh"
qualify a-right-w-completion
python3 -B "$area/record-stack.py"
```
