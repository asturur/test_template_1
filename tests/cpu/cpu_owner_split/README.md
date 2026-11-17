# Step5B private owner payload split

Exact control is published5A `6ac7a9d`. Four isolated RTL files preselect the
next payload with registered completion validity, keep P2 SWP identity and carry
a private direction class into cache readiness. No state or cycle is added.

`bench.py --name UNIQUE --case matrix4 --case transpose4` and
`jpeg.py --name UNIQUE` retain original guest/oracle/negative checks. `--control`
selects exact5A; snapshots assert byte identity against its published commit.
`run.py UNIQUE --safety` reuses the existing load/store/IRQ/abort fixtures;
`--arg +i_wait=2 --arg +d_wait=9` selects delayed memory. `owner.vh` asserts
qualified packet identity while separately observing private idle selection.
`diagnostics.py UNIQUE --build BUILD` reuses ARM/Thumb/FCSE/fetch-fault checks.
`core_cases.py UNIQUE --build BUILD` freezes all CPU/cache modules into a
container-visible reference and checks completion plus cached/uncached SWP,
abort and IRQ cases at both memory delays. Sources, executable and logs remain
under build/sim; no shared fixture output or phone is touched.

The `.v`/`.vh` fixture copies retain5A's existing independent memory/ordering
oracles. `old_dma.v` adds an accepted RAM DMA held across CPU lock to the existing
route response oracle. It runs with `iverilog -g2001 -s response_tb`, against
`rtl/ngage_dma_route.v`, then `vvp` in a unique build output.

[Report and audit](../../../docs/cpu-owner-split.md).
