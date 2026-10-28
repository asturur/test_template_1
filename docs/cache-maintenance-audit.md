# Cache and TLB operations observed during firmware startup

This is a partial audit of the CP15 trace in
`build/sim/runs/boot-cache-candidate-v3/cp15.tsv`, through the integrity failure.
It is not a complete Symbian or N-Gage hardware inventory.

The trace contains writes to control C1, translation table base C2, domain
access C3, I-cache invalidate `MCR p15,0,Rd,c7,c5,0`, data-cache operation
`c7,c10,0`, write-buffer drain `c7,c10,4`, and data-TLB invalidate
`c8,c6,0`. The ARM920T manual documents I-cache invalidate, drain write
buffer and D-TLB invalidation. The manual's cache-operation table does not list
`c7,c10,0`; treat the firmware's use and Nokia behavior as requiring further
investigation, rather than assuming the manual defines it. ZAP decodes
`c7,c10,0` as clean-all. In ZAP CP15's cache-control case, `c7,c10,4` has no
explicit matching case; whether that is functionally harmless depends on the
write path and ordering, and requires a separate proof. Do not claim this test
proves accurate ARM920T write-buffer semantics.

`scratch/cache-maintenance-control/test.S` and `overlap.S` exercise ZAP's
clean-all, drain encoding and invalidate D-cache using cached writes and an
uncached physical alias; the second variant issues back-to-back cache-line
reads before maintenance. Both the seven-patch baseline and the scratch v7
identity candidate pass at memory latencies 0 and 3. This confirms the tested
sequence only; it does not establish all clean/invalidate combinations, timing,
write-through behavior, locked entries, ARM920T conformance, or the actual
Nokia implementation. Fault-return control `scratch/cache-fault-return/test.S`
checks return from a denied store, followed by a successful cache read; both
baseline and v7 pass at 0/3.

Next: check write-buffer and write-through behaviors against an independent
model and ARM manual, use additional firmware traces after boot advances, and
verify all relevant CP15 operations under IRQ, flush and cache-dirty conditions.


`scratch/cache-remap-control/test.S` remaps the same cacheable virtual section
to a different physical section after overlapping reads, invalidates data cache
and D-TLB, then reads the new value. Baseline, V7 and V8 pass at latencies 0/3.
This is a post-request maintenance control, not proof of cancellation while a
TLB walk or refill is active.
