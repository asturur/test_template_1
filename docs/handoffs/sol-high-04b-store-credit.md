# Step 4B — Remove the bubble after two resident ARM stores

Work in the existing integration checkout. Read AGENTS.md, docs/status.md and
docs/cpu-store-overlap.md. Start from the final isolated 4A candidate. Keep it
as the fixed control. Use fresh offline outputs, the existing simulator image,
and the same CPU entry point, instruction binaries, warm-up, wait profiles and
output oracles.

The 64-store ARM loop went from 197 cycles (3C) to 102 (4A). Its 63 acceptance
gaps are now 32 one-clock gaps and 31 two-clock gaps. Trace a pair and the
following bubble through count, physical write, registered return and next
CPU issue. Prototype the smallest change that covers this return latency;
try one spare credit with local registered state first. Keep 4A's eligibility
class. Preserve ordered ownership and exactly-once writes and completion. Keep
physical response feedback out of the same-cycle global stall/fast-ACK path.

Use the same first-issue-through-last-physical-write window. Show the full gap
histogram, cycles, peak occupancy and an edge trace for three consecutive
distinct stores. Account for simultaneous allocation/return, full pressure,
drain on an ineligible access, reset, a following same-address load and
fault/interrupt ordering at peak occupancy. Exercise active credits when
checking interaction with a following probed load. Reuse the 4A independent
byte/dirty/retirement checks and wrong-byte control.

Run the original transpose on both existing profiles against 4A's 4,676-cycle
result and show checksums or oracle outcomes and qualifying-store coverage.
If the store loop improves but transpose plateaus, trace the first remaining
stall in the real workload. Keep the simpler control if the experiment buys
no cycles. Report a concise before/after table and the next limiting dependency.
Timing and area observations inform the design; there is no fit gate here.
Leave production RTL, PLL, hardware, other chats' work and simulations untouched.
