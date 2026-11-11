# Original NEM-4 DMA ISR fixture

Run from the repository root with the private original ROM:

```sh
sh tests/phone/dma_isr/run.sh /path/to/ngage-rom-0x50000000.dmp
```

The runner verifies ROM SHA-256
`26ca1dd937e299fd4ec3ad65a25d395743ae2149311c3d753cbeb5437673dbc5`
and extracts the exact `50320000..503d0000` instruction window. ZAP executes
original ISR `5032ca14`, status provider `50321860`, stop/ACK `503212c0`,
remaining getter `50330c7c`, next chunk `50330d10`, zero provider `50321868`,
IRQ-disable wrapper `50331c08` and its kernel/MMIO callees without replacing
any instruction.

Both cases use DMA channel 1, whose original handler ID is `0x64` and ICU
bit is 7. The byte transfer remains SDRAM-to-SDRAM to isolate ISR behavior:

- Remaining `0`: the original ISR acknowledges the completed channel, calls
  original interrupt disable and invokes exactly one callback through the
  channel's synthetic vtable.
- Remaining `16`: the original ISR acknowledges the completed channel before
  executing the original next-chunk routine. That routine updates remaining
  bytes and source/destination pointers and starts one exact 16-byte copy.
  No callback occurs for the first chunk. After its completion another original
  ISR invocation disables the handler and invokes exactly one callback.

The fixture checks all 4 KiB of backing SDRAM, including both source ranges
and every unwritten guard byte. It checks three original ISR/status/getter
entries, one next-chunk entry and two original VA-to-physical entries; zero
model errors, no duplicate callbacks, per-channel IRQ acknowledgment before
restart/callback, original channel stop/disable ordering and pointer updates.
It runs with zero and three memory-wait cycles.

Explicit boundaries:

- The harness calls the original ISR as a function after the pending channel
  completes. It does not claim full kernel vector entry, interrupt dispatch,
  scheduling or DFC execution. The CPU IRQ input is held low.
- ISR wrapper, channel and callback-vtable objects are synthetic kernel RAM
  objects. The callback itself is a fixture marker function. It checks the
  channel argument, disabled wrapper, cleared pending IRQ and zero remaining.
- Kernel interrupt limit/table globals at `800066e4/e0` are synthetic. The
  handler-table slot is empty. The original wrapper executes its real mask
  write `5812010c=80`, checked by the fixture; no production ICU is instantiated.
- The original VA-to-physical routine reads a synthetic identity section
  descriptor at `41000280` for `0a000000..0a0fffff`. The CPU MMU remains off.
- Original virtual `5812xxxx` DMA register accesses map to physical
  `0c12xxxx`. The candidate frontend, engine and production DMA route perform
  the actual copy against a delayed bounded SDRAM endpoint.
- This does not establish LCD scanout timing, production LCD handover or real
  phone electrical behavior. Production handover has a separate board fixture.

Private extracted instructions, build files, compact logs and manifests stay
under `scratch/ngage2-integration/lcd-handover/isr/`. No phone checkpoint or
other checkout is opened or changed.

Observed locally on 2026-11-11: zero waits passed in 11,067 cycles and three
waits passed in 16,449 cycles. Both completed three original ISR invocations,
two callbacks and one original next chunk with no instruction substitutions.
`results.json` records source/input/executable/log hashes and the local image
identity; the runner rejects source changes during its build/run.
