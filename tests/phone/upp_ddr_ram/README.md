# Production UPP DDR endpoint checks

Run from the project root with the local ARM assembler and the existing offline
simulator image. The mixed case reuses the adapted Micron model documented in
[the retained latency replay](../../../docs/upp-ddr3-rtl-replay.md#reproduction).

```sh
sh tests/phone/upp_ddr_ram/run.sh
```

The registered board test checks authorization, held completions, every legal
byte mask, invalid-mask rejection, distinct addresses and 32-bit lanes, and
MDI, auxiliary and NOS4K ownership. It replaces an in-flight read with a read
to the other bank and verifies that the first result cannot complete the
second. A warm reset drains an accepted write without clearing memory. The
next cold reset clears both banks again and keeps initialization incomplete
until the DDR peer and local RAM sweep finish.

The mixed case runs ARM9V2 with both production UPP DDR windows enabled.
The guest checks raw reads and masked writes, executes an ARM `SWP` in each
window with LCD DMA waiting and fetches instructions from each window. It also
checks a full pin-level LCD transfer, an MMC write and readback, and the
128-sample signed PCM hash and cadence. The tests use a byte-enabled delayed
DDR endpoint peer. The
[transport regression](../upp_ddr_transport/) exercises the production HPS
transport and arbiter separately.

Logs and the mixed source manifest are under `build/sim/upp-ddr-ram/`.
