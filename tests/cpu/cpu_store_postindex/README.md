# Step5F post-indexed store admission

Pinned control: retained5D `258eed3`; 5E frontend prototype excluded.
One classification change, no new state or forwarding datapath. Existing
ALU/shifter feedback already gives the next store its correct updated base;
early resident completion removes the binding global holds.

Checked medians, both0:0/2:9: fill16_tail2078→1332, fill8_tail2172→1647.
Matrix45736/transpose3591/full-frame71259 or201302 remain unchanged; frame
body+first-empty201407 at2:9, warm64-store issue→last-RAM-write71 unchanged.

`bench.py --control` / default selects exact control / isolated candidate.
It reuses original payloads, oracles, repeats and wrong-output checks.
`post.vh` observes real dequeue, held/advancing address/base, admission, RAM
mutations, base writes, retirement and passive pending-write drain.
`classify.py` checks12288 real-predecode vectors plus118 existing controls.
`run.py --safety` composes18 untimed post cases with the existing memory guest;
it checks faults/base preservation, predication, offsets, late data, device
fallback and actual peak-pressure IRQ prefix/suffix. Original timed64-store
body remains unchanged. Physical expected ways come from valid tag RAM, never
an unqualified fallback result_way. `negative.py` rejects two wrong physical
byte oracles using the identical executable.

`analyze.py --production` verifies the named final results, original PC order,
group schedules, disjoint cycle accounting and normal patch replay. Unique
names refuse overwrite. Use the installed offline simulator, serial builds
with one job. `storage.py` compresses only completed5F runs; rebuildable compiler
files may be removed while retaining all frozen inputs/logs/executables.

Extra JPEG build was not simulated after environment ENOSPC/image I/O failure;
no new JPEG or additional diagnostic result is claimed. No donor/fit/CI/hardware.
[Results, limits, fixture repairs and replay](../../../docs/cpu-store-postindex.md).
