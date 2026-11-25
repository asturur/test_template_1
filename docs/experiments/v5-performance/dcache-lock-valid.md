# Update the D-cache load lock as one valid bit

The [design patch](patches/dcache-lock-valid.patch) applies to `81fa768`,
the exact retained 104 MHz tree. The D-cache already records the tag of
its single outstanding background load. The prototype sets the valid
bit on miss admission. It otherwise clears the valid bit when a
registered return writes the held tag. If both events occur on one
edge, the newly admitted miss owns the tag. The legacy bitmap and its
consumers still run on their existing edges. The checker compares the
registered bitmap with the valid bit and tag in simulation.

The old set decision goes through the variable-index bitmap write and
a 64-bit nonempty reduction. A path starting at the TLB physical
address reaches `o_lock_any` at hot rank 17 (−2.137 ns) on retained seed
43 and rank 526 (−1.387 ns) on seed 13. The same family was the worst
path in the parked SDRAM-capacity seed 31337 run. This prototype removes
the bitmap write and reduction from the set path into `o_lock_any`.
The return side still selects its own bit from the registered return
mask. The setup, routing and area effects require a fit.

## Local qualification

The independent [fixture patch](patches/dcache-lock-valid-replay.patch)
checks 1,064,960 transitions over all old and new tags, all single-tag
returns and no-return, including simultaneous return and installation.
Valid matches the bitmap reduction in every case. The reconstructed tag
matches the bitmap for every transition with at most one live owner.
The four directed board profiles have the same cycle counts and
cache, fault, SWP and line results as the exact retained netlist. The
mixed replay matches all 171,496 events, including LCD, PCM, MMC and
SDRAM pins. Timing and the 15 fixed workloads and four native frames
remain to be measured on this prototype.
[Local verification receipt](../../evidence/v5-104-dcache-lock-valid.json)

## Another CPU path to try

The SDRAM-capacity seed 43 worst path runs from `tr_cache_word[13]`
through the execute operand mux and ALU logic into the CPSR Z flag.
Arithmetic already enables `FAST_Z`. Test predecoding the zero-flag
operation into the execute packet so the returning value can feed
simple flag candidates directly. Start with equality for CMP/TEQ
and the AND reduction for TST. Keep existing NZCV forwarding and
measure the same workloads before fitting. Prior census counted
126,086 flag-setting data-processing completions using a live load
in one steady Sega scan window. A blanket stall would hit a much
broader path. [Previous operand census](live-rs-prep.md)

## Replay

```sh
catalog=docs/experiments/v5-performance
area=scratch/v5-fit-loop/dcache-lock-valid
git apply "$catalog/patches/dcache-lock-valid-replay.patch"
mkdir -p "$area/source"
git archive 81fa768 | tar -x -C "$area/source"
git apply --directory="$area/source" "$catalog/patches/dcache-lock-valid.patch"
python3 -B "$area/source/tools/gen_arm9v2_phone.py" --stock build/arm9v2-assoc/stock-pinned.v --check
iverilog -g2012 -s check_lock_update -o "$area/check-lock-update" "$area/check-lock-update.v"
vvp "$area/check-lock-update"
```

Use the [focused board fixture](early-shift-select.md#reapply-and-verify)
with the retained and candidate netlists. For the mixed pin replay,
prepare the [write-data reference](prepared-wb-write-data.md#reapply-and-verify),
run `python3 -B "$area/mixed.py"` and repeat its build and trace commands
in `build/sim/v5-104-dcache-lock-valid-pin-mixed/mixed`.
