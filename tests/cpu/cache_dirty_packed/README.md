# Packed dirty metadata regression

The production cache is compared cycle by cycle against the cache at commit
`eb5e7afc6fd704c3ab2c7d0706037596e7ca1973`, before dirty/tag RAM packing.
The four `reference_*.sv` files freeze that implementation with module names
renamed; shared unchanged line RAM, refill, transfer and write-buffer modules
still come from production. The test exercises minimum-spaced serialized
requests, both dirty halves, WB/WT, clean/invalidate, 65th-way dirty eviction,
physical aliases, backpressure, cancellation and admission ownership.

Run `sh tests/cpu/cache_dirty_packed/sim.sh` in the existing simulator image.
Run `sh tests/cpu/cache_dirty_packed/run-four-state.sh /path/to/altera_mf.v`
with the existing Intel library to check real primitives and explicitly
X-poisoned mixed-port read/write collisions. Icarus-only copies lower enum
ternaries and move a forward declaration; production sources are not rewritten.
The architectural comparison includes every ready/valid, memory transaction,
response and completion cycle, rather than undefined internal collision data.

Expected: 11,025 equivalent cycles in each RAM configuration. This does not
measure Cyclone V area, routing or timing. No firmware image is required.
