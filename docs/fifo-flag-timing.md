# Instruction FIFO flag timing

The a745119 build has three negative setup endpoints at78MHz, all from the
instruction-cache prefetch P_ISSUE state through cache ACK/code_stall into
instruction FIFO empty/full flags. Worst slack is−0.280ns, data delay12.375ns,
11logic levels;61% of data delay is routing. This identifies the routed path,
not proof that a particular optimization caused it.

Patch0064 changes only the FIFO's combinational pointer/flag calculation. The
old flags compare both next pointers after late write/read enables select their
increments. The new implementation computes incremented pointers and the
one-item/one-free comparisons from registered pointers independently of those
enables. A final transfer selector chooses the next flags. The pointer updates
also select precomputed increments. Simultaneous accepted transfers retain
occupancy; existing guards retain the full/empty boundary rules. Reset and
clear keep priority, data ordering and write acceptance are unchanged.

There are **no added registers, RAM, FIFO capacity, clock or pipeline stages**.
This removes dependent add/compare work after the late ACK, while retaining
the same cycle interface. Actual mapped area, routing and closure require a
new Quartus result; no MHz improvement is inferred from Verilator. PLL remains
78MHz and104MHz stays the design objective.

Qualification:

- Exhaustive equation comparison covers2,812,480 reachable pointer/occupancy/
  control combinations, depths2 through256, including reset/clear and guards.
  This is enumeration, not an HDL formal proof.
- Independent queue/data model passes100,000clocks at each of depths2/4/8/16/
  32/64: boundaries, simultaneous transfers, over/under requests, wraps, clear
  and reset. A broken last-word empty flag fails the test as expected.
- 62CPU runs pass at waits0/3, including ARMv4 profile, Thumb LDM, IRQ/FIQ/SWP,
  refill/writeback, privilege, MMU, CP15 prefetch and instruction invalidation.
- Full original-payload suite passes12groups/84windows per repeat, two exact
  repeats, six wrong-output controls. **Every raw window and total counter
  matches F1**, including payload retirements. Original baseline indices remain
  **154.4752 /144.5781**; no throughput gain is claimed for this timing rewrite.
- All83pristine upstream hashes and37patched ZAP token streams reconstruct
  through0064; preexisting imported formatting/comment differences remain.

[Qualification](evidence/fifo-flags-20261115.json),
[payload counters](evidence/spmark-payload-fifo-flags-20261115.json).
Reproduce the dedicated check with `sh tests/cpu/fifo_flags/run.sh`; all local
new outputs use isolated fifo-flags-20261115 directories. Existing long-running
simulations/checkpoints remain untouched.

The earlier read-only F1 frontend observer still suggests investigating decoded
instruction ownership of BTB updates. An ALU result-valid bit alone cannot
distinguish a bubble from a failed condition. Preserve failed conditional-branch
feedback, aliases, clear-under-hold and exception recovery before measuring
that candidate. This is unimplemented investigation, separate from0064 and the
larger F2 request-credit/ordered-completion work.
