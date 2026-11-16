# Deferred erase and independent cache refill

Run `python3 tests/phone/flash_refill_suspend/run.py`, or add
`--negative-control` to recreate the old admission gate in a generated source.
Add `--reset-overlap` to cancel an accepted cold RAM refill during a deferred
erase and require drained restart before the complete eight-erase test.
Add `--bulk-competition` for backpressured64beat C: sector snapshots competing
with CPU progress instead of scalar diagnostic reads. Every returned beat is
checked against independently modeled backing bytes. This covers DDR snapshot
transport, not HPS disk writeback or dirty-queue persistence.
Requires the existing `jotego/simulator:arm64` image and local ARM GCC.
Outputs are private to `build/sim/unit-flash-refill-suspend/`.

The actual CPU/MMU/cache, NEM-4 router, C: NOR, D1 stream/D2 flash cache and
outer DDR arbiter execute eight64KiB erases. ARM software alternates buffered
and unbuffered NOR mappings and uses both B0 suspend and first-busy/second-done
polling. It crosses cold instruction/data cache lines between the erase command
and its progress command. Competing diagnostic reads, variable DDR BUSY/latency,
scalar SDRAM and streamed SDRAM lines exercise the production boundaries.

The memory devices are bounded synthetic models, not fitted DDR/SDRAM or physical
NOR verification. Programmed first/last cells must be erased; every loop checks
native status/struct data. Failure cannot be masked by changing firmware
instructions or deadlines. A separate watchdog recognizes the exact passive-
erase/refill circular wait; the negative control must hit that reason.

The local fix changes refill admission from C: reset-drained idle to transport
ready. Reset still uses the stronger idle predicate. Existing reset program/
erase/drain qualification remains required. Hardware installation/JPEG results
and fitted78MHz/104MHz timing remain separate gates.
