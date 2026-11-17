# Step5E target delivery — rejected prototype

Fixed control: accepted5D `258eed3`. Production RTL remains at that baseline.
The one-file overlay routes the registered BTB target through the existing CPU
redirect handoff. It adds no state. It is **not accepted for production**:
matrix 45736→46932, transpose 3591→3537, original Thumb JPEG 84353→84014,
drained stores 71→71, both established memory profiles.

`bench.py --control` / default and `jpeg.py --control` / default select exact
control or isolated prototype. `timeline.vh` observes actual stage PCs before
the edge, accepted predecode and useful dequeue, surviving target requests,
ACK/F/decode/retirement and distinct frontend/backend conditions. Thumb BL
suffix packet PCs are normalized to original prefix PCs for the oracle.
`timeline.py` aligns real dynamic transfers; `analyze.py` verifies the named
final runs, exact source and guest identities, repeat traces, full retirement
order, canonical JPEG oracle, disjoint cycle deltas and qualification.

`redirect.py` runs 38 real-writeback hold/priority/ARM/Thumb/FCSE checks twice.
`diagnostics.py` reuses the existing eight CPU checks. `run.py --safety` reuses
the existing ordered memory/IRQ/abort/device/dirty-byte guest; the existing
store negative checker must still reject a wrong physical byte. No new timed
guest, donor RTL, cache size, predictor state, fit or hardware access.

Builds are serial with one compiler job and the installed offline simulator.
Unique run names refuse overwrites. Frozen sources/observer inputs and
executables live under `build/sim`; `storage.py` compresses completed Step5E
traces and removes only their rebuildable objects, retaining raw hashes.

[Full schedules, opportunity, rejection and replay](../../../docs/cpu-target-delivery.md).
