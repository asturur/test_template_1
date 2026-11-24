# D1 opcode class stored with the instruction

The [RTL, generator and regression patch](patches/d1-opcode-class.patch)
applies to the restored execute-readiness tree `c492853`. The public
fit parent is the byte-identical CP15 forward revert `2c9d1ff`.
The isolated trial is `4b2c114`.

Each D1 queue slot carries four extra bits from the existing opcode
classifier. They are written with the same expanded word, selected
Thumb halfword, processor mode and register list as the rest of the
slot. Checking the register list directly for zero lets the popcount
run in parallel. D2 reads the class from the original one-hot head.
The predecessor donor experiment `bc3e838` used one-hot selection
with combinational per-slot classification. This trial puts the
classifier on the input side of that storage boundary.

The D1 write enable still permits the original free-payload writes.
The valid, pop and push controls determine which packet can issue.
The branch shortcut keeps its direct path, and BL prefix/suffix,
undefined and privileged decode use the original classifier. Fault
fields, branch recovery, reset, flush and occupancy keep their
existing behavior. No queue or decode stage was added. The fit will
test whether the former D1-to-D2 classification route improves or the
constraint moves to the incoming Thumb expansion and class path.

## Reapply and verify

From the repository root, use a disposable source copy and the
existing pinned stock CPU netlist.

```sh
area=scratch/recheck-d1-opcode-class
mkdir -p "$area/source"
git archive c492853 | tar -x -C "$area/source"
git show c492853:rtl/arm9v2/arm925t_phone.v > "$area/reference.v"
git apply --directory="$area/source" docs/experiments/v5-performance/patches/d1-opcode-class.patch
python3 -B "$area/source/tools/gen_arm9v2_phone.py" \
  --stock build/arm9v2-assoc/stock-pinned.v --check
docker run --rm --pull=never --network none --platform linux/arm64 \
  -v "$PWD/$area:/stage" -w /stage/source --entrypoint sh jotego/simulator:arm64 -ec \
  'sh tests/cpu/arm9v2_board/run-d1-opcode.sh /stage/reference.v'
```

In each of four Thumb-half and payload-write configurations, the
differential covered all 65,536 register lists, all 65,536 Thumb
encodings in each halfword position and 30,014 queued clock cycles.
It compared all decoder outputs and the D1/D2 packet and control
state. The queue sequence reached all 15 classes, both slots, full
stalls, simultaneous pop and push, direct branch shortcuts, flushes
and faults. The workload and board runs also checked that each stored
valid head class matched the original on-the-fly decoder.

All 15 fixed workloads and four native PolyCount frames matched
`c492853` cycle for cycle, with the same output and ordered-event
digests. The four board profiles matched 293 branch events and 22
MMIO events each. The mixed LCD, PCM and MMC replay matched 1,201,547
clocks, PCM hash `175ee178` and MMC persistence.
[Full qualification and fit inputs](d1-opcode-class-replay.json)

For the workload reruns, prepare the
[execute-ready reference decks](execute-ready.md#reapply-and-verify).
The D1 replay reads their result JSONs and the checked all-four
workload inputs.

```sh
area=scratch/v5-fit-loop/d1-opcode-class
mkdir -p "$area/source" "$area/replay"
git apply docs/experiments/v5-performance/patches/d1-opcode-class-replay.patch
git archive c492853 | tar -x -C "$area/source"
git apply --directory="$area/source" docs/experiments/v5-performance/patches/d1-opcode-class.patch
git show c492853:rtl/ngage_cpu.sv > "$area/ngage_cpu.sv"
python3 -B "$area/replay.py" fixed
python3 -B "$area/replay.py" native
```

All three fit dispatches pin `4b2c114` at physical 104 MHz with DDR
debug disabled. Preflight matched the effective QSF to the control
for each seed. The generated CPU netlist is the only changed
synthesis input.
[Seed 43](https://github.com/asturur/test_template_1/actions/runs/45358057788) ·
[Seed 13](https://github.com/asturur/test_template_1/actions/runs/45358062079) ·
[Seed 31337](https://github.com/asturur/test_template_1/actions/runs/45358066185)
