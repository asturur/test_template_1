# Cache probe selection timing recovery

The user-supplied timing export matches b3131b5/run43821270521/seed43 exactly.
The exported1,000 setup paths contain31violations;27start at reset_drain.
The worst is reset_drain→D-cache probe_owner_way at-1.722ns:13.812ns data,
12logic levels,5.071ns cells,8.740ns routing and-0.430ns clock skew. This is
a real synchronous path, not a justified false/multicycle path. PLL stays78MHz;
104MHz remains the design target. Full constraints and physical timing remain
mandatory. This endpoint export does not enumerate every path to every endpoint.

| Failing destination family | Count | Worst ns |
| --- | ---: | ---: |
| Probe owner way |15|-1.722|
| Probe owner tag |2|-0.732|
| Memory-route Equal0 |2|-0.587|
| Post-ALU to issue operands |2|-0.458|
| Admission probe owner |3|-0.441|
| Snapshot RAM input |3|-0.359|
| Operand read to issue |1|-0.294|
| Probe owner valid |1|-0.117|
| Demand indexed way |1|-0.082|
| TLB hit vector |1|-0.028|

The former probe first priority-encoded eight matches into a slot number, then
used that number for a second variable-index six-bit way selection. Owner and
result payload registers also had synchronous reset clears; owner capture sat
behind the full reset/revocation cone.

The rewrite selects payload with parallel match/prefix qualification and masked
OR reduction. Lowest-slot priority is preserved even for duplicate tags, with
no dependence on an assumed uniqueness invariant. Reset/revocation still clear
both valid bits.66payload bits no longer require reset clears; owner payload
may update while invalid, and only the unchanged valid/read/permission/collision
conditions can publish or consume it. Result payload still transfers on its
owned read. No register, RAM, queue, pipeline stage or execution cycle is added.
The eight records and current permission checks remain intact.

Verification passes402real probe requests,164fast reads,8parallel A/B clocks,
122blocked collisions; fresh backing data after reset and all eight learned
records with high physical-way bits. Three randomized startup seeds also pass
(121blocked collision clocks, no output difference). Resident94, certificate146
with8short revisits, admission256 and absence44requests pass. A supplemental
standalone check uses the actual selector fragment with16,384 combinations of
match sets and six-bit ways, including duplicates, against lowest-index priority.
The full-cache four-state Icarus attempt fails on pre-existing forward-declaration
and enum limitations; it supplies no X-propagation evidence. Do not repair the
production RTL merely to make that optional tool elaborate.

All12original six-kernel groups and8JPEG converter groups pass2exact repetitions,
original output oracles and bad-output controls. Every measured raw window,
whole-run counter and JPEG occupancy bucket matches the prior eight-record CPU.
Original100 indices therefore remain233.2707/196.1981, JPEG121.2488. Frozen
benchmark sources differ from the final file only in explanatory comments;
noncomment tokens match. This is a timing restructuring, not another speedup.

No build of this rewrite has been started. A new Quartus placement must measure
actual slack/area; do not claim the-1.722ns violation is closed from simulation.
Other reset/admission/snapshot and operand paths remain separate in the old
export. The already-running80373af Calendar-fix build predates this rewrite.
[Machine evidence](evidence/cache-probe-timing-20261116.json).

During this investigation the user confirms native b3131b5 JPEG and Contacts
pass. Disk Access is still only reported progressing, official scores unavailable.
The user has taken over uninstall/full-version installation. Do not send phone
input, reload or deploy a build during that handoff. The current timing rewrite
preserves the passing candidate's exact synthetic counters; new routed timing
and subsequent native qualification remain required.
