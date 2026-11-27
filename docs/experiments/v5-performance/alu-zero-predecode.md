# Predecode ALU zero-flag comparisons

The [design patch](patches/alu-zero-predecode.patch) is independent of
the D-cache lock trial. It starts at `81fa768`, the exact retained
`e9552bd` tree. A parked fit's worst seed-43 path went from the
D-cache's `tr_cache_word[13]` through the execute operand mux and ALU
logic into CPSR Z. The retained `FAST_Z` arithmetic calculation
already avoids waiting for the sum, while logical operations first
choose a 32-bit value and then test for zero.

Capture the one-hot Z operation on the existing A-packet admission
edge. Each candidate produces one bit. The registered class selects
between the bits. SUB, RSB, CMP, EOR and TEQ share the operand equality
check. AND and TST share a reduction. The remaining logical operations
have direct tests. ADD, ADC, SBC, RSC and CMN reuse the retained
arithmetic predicate. NZCV forwarding, result generation and pipeline
edges follow the existing design. An assertion checks Z against the
architectural ALU result while the execute packet is valid.

## Local qualification

The directed test compares the retained and proposed implementations
on 197,376 combinations, with both zero and nonzero cases for each
of the 16 operations. It checks the full result and all four flags,
including the alternate `FAST_Z=0` path. The four directed board
profiles and all 171,496 mixed events match the retained tree.
All 105 windows across the 15 fixed workloads and all four native
PolyCount frames match cycle for cycle, with exact output, ordered
architectural events and Wishbone write traces.
[Local qualification evidence](../../evidence/v5-104-alu-zero-predecode.json)

## Routed comparison

Commit `3d57ba3` uses only the ALU patch relative to `e9552bd`. The
production fits use 104 MHz, DDR debug disabled, and three matched
seeds. The D-cache lock fits remain pinned to their own commit.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45721887638) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45721884840) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45721887917)

| Seed | Retained setup slack (ns) | Candidate setup slack (ns) | Candidate ALMs |
| ---: | ---: | ---: | ---: |
| 43 | −2.508 | −3.019 | 36,089 |
| 13 | −2.061 | −2.812 | 36,082 |
| 31337 | −2.471 | −2.983 | 36,083 |

The per-seed QSFs match exactly and the generated CPU netlist is the
only changed compiled input. Named load-to-Z paths fall from three to
zero in seed 43's hot top 1,000 and rise from zero to one and three on
seeds 13 and 31337. The worst path on seeds 43 and 13 ends at D-cache
`o_lock_any`. The seed 31337 limit ends at the Wishbone address.
Median worst setup moves from −2.471 to −2.983 ns, median core setup
TNS worsens 1,169.896 ns, and median area saves 363 ALMs. All three
use 321 M10Ks, meet hold, recovery, removal and minimum pulse width,
and miss setup. Keep the patch for later area comparisons. The best
candidate RBF is seed 13 at −2.812 ns. Public `bbed9e4` restores the
exact retained tree.
[Matched timing evidence](../../evidence/v5-104-alu-zero-predecode-fits.json)

## Replay

Apply the [fixture patch](patches/alu-zero-predecode-replay.patch).
Prepare reference decks using the [live shift-count replay](live-rs-prep.md#reproduce).
The normal workload runner compares full window counters, ordered
architectural traces and valid Wishbone writes.

```sh
catalog=docs/experiments/v5-performance
fit=scratch/v5-fit-loop
area=$fit/alu-zero-predecode
git apply "$catalog/patches/alu-zero-predecode-replay.patch"
mkdir -p "$area/source"
git archive 81fa768 | tar -x -C "$area/source"
cp "$area/source/rtl/arm9v2/arm925t_phone.v" "$area/reference.v"
git apply --directory="$area/source" "$catalog/patches/alu-zero-predecode.patch"
python3 -B "$area/source/tools/gen_arm9v2_phone.py" --stock build/arm9v2-assoc/stock-pinned.v --check
sh "$area/run-zero.sh"
cp "$area/source/rtl/ngage_cpu.sv" "$area/"
cp "$fit/live-rs-prep/architectural_trace.vh" "$area/"
cp "$fit/live-rs-prep/wb-write-trace.vh" "$area/"
sed 's|/live-rs-prep/source/|/alu-zero-predecode/source/|g' \
  "$fit/live-rs-prep/replay.py" > "$area/replay.py"
for measure in fixed native; do
  python3 -B "$area/replay.py" "$measure" --output qualification
done
```

Use the [focused ARM board fixture](early-shift-select.md#reapply-and-verify)
with the retained and candidate netlists. For the physical-pin replay,
prepare the [write-data reference](prepared-wb-write-data.md#reapply-and-verify),
run `python3 -B "$area/mixed.py"` and repeat its build and trace commands
in `build/sim/v5-104-alu-zero-predecode-pin-mixed/mixed`.
