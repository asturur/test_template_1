# CP15 AP=0 permission predecode

The [portable RTL, generator and test patch](patches/cp15-ap0.patch)
applies to the retained execute-ready control `c492853`. The isolated
candidate is `85f65c8`. The targeted path ran from CP15 `o_sr[0]`
to D-side TLB fault status `o_fsr[3]` at −2.666 ns on seed 31337.

CP15 emits two AP=0 permission bits on the existing S/R update edge.
With the S/R value written as `{S,R}`, those bits distinguish `10`
(privileged reads) and `01` (read-only access in either mode).
`00` and the reserved `11` grant neither. The TLB checks compute their
four AP permissions in parallel with descriptor matching and domain
selection. The original `!write` and `privileged && read` conditions
remain separate for simultaneous read/write inputs. AP=1, 2 and 3,
manager bypass, descriptor and domain fault precedence, and FSR/FAR
capture stay on the existing access edge. The TLB modules retain the
plain S/R interface for standalone use. The production I and D caches
select the registered permission bits.

## Reapply and verify

From the repository root, use a disposable copy of the exact execute
control and the already-pinned stock netlist.

```sh
area=scratch/recheck-cp15-ap0
mkdir -p "$area/source"
git archive c492853 | tar -x -C "$area/source"
git show c492853:rtl/arm9v2/arm925t_phone.v > "$area/reference.v"
git apply --directory="$area/source" docs/experiments/v5-performance/patches/cp15-ap0.patch
python3 -B "$area/source/tools/gen_arm9v2_phone.py" \
  --stock build/arm9v2-assoc/stock-pinned.v --check
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$area:/stage" -w /stage/source --entrypoint sh jotego/simulator:arm64 -ec \
  'sh tests/cpu/arm9v2_board/run-cp15-ap0.sh /stage/reference.v'
```

The differential compared every registered TLB output on every checked
edge. The two cases completed 262,205 I-side and 524,349 D-side
lookups at production TLB geometry. An independent fault scoreboard
checked section, small, large and fine-page descriptors, AP and S/R
combinations, all 16 domains and their four mode values, access type
and privilege. The two original/candidate CP15 callback instances
received real MCR command words. Checks included the first lookup after
each S/R change, blocked user-mode writes, reset, missing descriptors,
and held check stages across a CP15 update. The test also covered the
legacy raw-S/R interface with the new port deliberately poisoned.

All 15 fixed workloads matched every checked window. The four native
PolyCount frame windows matched 57,508,371 clocks, the final output
SHA-256 and the ordered retire/data/MMIO digests. The four board modes
matched clock counts and ordered side effects. The mixed LCD, PCM
and MMC replay matched 1,201,547 clocks, 18,304 LCD words, PCM hash
`175ee178` and the MMC write/readback. [Full qualification and source hashes](cp15-ap0-replay.json)

For the fixed and native comparisons, prepare the
[execute-ready reference decks](execute-ready.md#reapply-and-verify)
first. The replay below reads their result JSONs and the original
all-four workload inputs.

```sh
area=scratch/v5-fit-loop/cp15-ap0
mkdir -p "$area/source" "$area/replay"
git apply docs/experiments/v5-performance/patches/cp15-ap0-replay.patch
git archive c492853 | tar -x -C "$area/source"
git apply --directory="$area/source" docs/experiments/v5-performance/patches/cp15-ap0.patch
git show c492853:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
python3 -B "$area/replay.py" fixed
python3 -B "$area/replay.py" native
```

The production 104 MHz, DDR-debug-off triplet uses the same QSF and
constraints as the execute control. The only changed synthesis input
is the generated CPU netlist. Each run is pinned to `85f65c8`.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45350186792) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45350190478) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45350194113)

## Routed results

The targeted seed 31337 CP15-to-FSR family dropped from four named
paths to zero in the detailed hot top 1,000. The worst listed FSR
endpoint improved 0.980 ns at 100 °C and 0.628 ns at −40 °C.
Median ALMs fell from 37,297 to 37,011, with 321 M10Ks on every seed.
Whole-core setup regressed on all three seeds and the median moved
from −2.668 to −2.919 ns. Park the patch as an area option for
recombination. The public forward revert `2c9d1ff` restores `c492853`.
[Per-seed fits, paths and bitstream SHA-256](../../evidence/v5-104-cp15-permission-fits.json)
