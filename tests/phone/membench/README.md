# membench: whole-board memory benchmark without firmware

`membench.S` is a bare-metal guest that is the flash image itself. It builds
its page tables, switches the MMU and both caches on and runs 31 loops:
register-only code, SDRAM reads and writes of several shapes, working sets
around the cache sizes, two TLB conflict cases, a peripheral write, and
straight-line code fetched from flash and from RAM. Around each run it writes
the byte `0x01` to the STI text window; the testbench prints its clock count
and memory traffic counters there, so a loop's cost is the difference of two
stamps. `memtest.S` checks data integrity through the same paths.

Both run on `tests/phone/hardware_boot/tb.v` with the phone CPU netlist, the
SDRAM service and chip model, and the production DDR flash adapter and cache.
`bench_tb.py` makes the testbench copy: the DDR3 port answers a read after
144 ns (a DE10-Nano's f2sdram bridge) instead of three clocks.

```sh
PHONE_SDRAM_MODEL=/path/to/mt48lc16m16a2.v sh tests/phone/membench/run.sh
MHZ=104 FLASH_CACHE=131072 PHONE_SDRAM_MODEL=... sh tests/phone/membench/run.sh
```

The same `membench.S` runs unchanged on ngage2's whole-core bench (its flat
CS0 image is the program padded to 16 MB), which is how the two cores were
compared. The main program must stay below `0xA000`: flash reads from there
to `0x2B3000` are descrambled.
