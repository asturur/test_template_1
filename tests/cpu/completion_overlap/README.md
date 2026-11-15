# Owned completion overlap

Run `sh tests/cpu/completion_overlap/sim.sh` in the existing simulator image.
This uses an isolated output directory, including the guest program loaded by
the copied core fixture. Default scalar waits are 0 and 3.

The ARM guest checks adjacent independent loads, mixed-width stores and loads,
force-user reads, STM/LDM stack values, and a load-to-PC followed by stores that
must never execute. The monitor compares every offered P1 field with the actual
P2 packet one clock later, and rejects unsafe admission or mismatched outgoing
address/data/privilege/format/destination. Coverage requires reads, writes,
narrow accesses and force-user handoffs. The shared core fixture also runs
these ownership assertions during ordinary CPU regressions.

The completion-owner unit separately checks immediate/waited replacement,
fault payloads, reset and kill against an independent scoreboard. Architectural
abort, SWP, CP15 and IRQ/FIQ regressions remain required. These tests do not
establish routed timing, physical area or whole-phone speed.
