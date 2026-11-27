# D2 coherent flash backing cache

## 2026-11-19 — v5 updates resident data on committed writes

The v5 build's 32 KiB D2 cache updates the enabled bytes of a resident
64-bit beat when the backing write completes. The hit is captured at
lookup. A write miss leaves the resident tag and data alone. The data
RAM uses native byte enables. D3 restore still clears the affected
indices, and transport reset clears tags through the existing sweep.

At 78 MHz the production RTL matches every interval and counter of the
six earlier update-on-hit runs across three host delays and two autosave
settings. The 25-file NOR proxy falls from 175,437 to 116,936 clocks,
with 5,625 to 375 DDR reads during create and write. The final host ACK
and cold reopen match the baseline with autosave off. The 32 KiB cache
contract passes 3,994 transactions, including a held masked write. The
actual-HPS NOR save/reload and D3 ownership checks pass, as do the
v5 CPU delayed-refill guest and MiSTer top elaboration. FPGA fitting
and on-board Disk Access are unmeasured.

To replay the same cache source as the MiSTer build, run:

```sh
python3 tests/phone/disk_access/run.py --name d2-production-new --policy production --autosave
```

[Disk Access comparison](spmark-disk-access-v5.md).

## 2026-11-18 — 8 KiB v5 with full-rate MMC

The candidate `893b109` transfers one bit per 78 MHz clock between the
on-FPGA MMC host and the virtual card. Both endpoints sample the previous
registered bit and launch the next bit on the shared enable. At a byte
boundary the host suppresses that enable while its FIFO needs service.
The CPU, SDRAM, DDR bridge, 8 KiB D2 with 32-byte lines and stock PCM
match the 39 MHz control. V5 retains the 39 MHz profile from
[run 44370323925](https://github.com/asturur/test_template_1/actions/runs/44370323925)
with +0.096 ns of setup slack at 78 MHz. The full-rate results use RTL
simulation.

| Same-work simulation | 39 MHz MMC | 78 MHz MMC | Less time |
| --- | ---: | ---: | ---: |
| 4 KiB, eight CMD17 sectors | 74,904 clocks (0.960 ms) | 68,938 (0.884 ms) | 7.96% |
| 4 KiB, CMD18 with CMD12 | 68,833 clocks (0.882 ms) | 64,562 (0.828 ms) | 6.20% |
| 32 KiB, sustained CMD18 with CMD12 | 541,081 clocks (6.937 ms) | 509,202 (6.528 ms) | 5.89% |
| 32 KiB, with 250 µs extra per backing request | 560,581 clocks (7.187 ms) | 528,701 (6.778 ms) | 5.69% |
| CMD24, 512-byte write and PIO readback | 250,288 clocks | 247,478 clocks | 1.12% |

The read guest uses the card's original CID and starts at LBA 32. The
4 KiB CMD18 transfer uses the stock driver's sequence of types 8, six 9s
and 10. The 32 KiB row extends the sequence to 64 blocks to exercise
prefetch across 4 KiB boundaries. Both rates match all bytes and RAM
guards. The 4 KiB payload CRC32 is `98ac2258` and the 32 KiB CRC32 is
`71176477`. The latter issues nine aligned 4 KiB backing requests at
both rates, including one lookahead, plus the mount-time footer read.
The extra latency affects the data requests after identification. At
full rate the observed minimum bit spacing is one clock, and the long
read gains about 0.409 ms. FIFO waits, DMA and backing service also
contribute to the transfer time.

The independent MMC peer passes 28 cases at each of dividers 1, 2, 4
and 12. It checks corrupt CRCs, FIFO stalls, timeouts, reset, and final
block/stop ordering. The full-rate CMD24 result rejects deliberate
corruption of the last stored halfword. Its PCM/LCD coexistence variant
renders all 18,304 words, with 360 LCD writes and one signed PCM tick
during the acknowledged backing write, and zero audio underruns or
overwritten requests.
The MMC data/busy timeout still counts eligible serial bits, so its
continuous-clock window is 107.5 ms at 78 MHz versus 215.1 ms at 39 MHz.

The following full-rate replay uses the RTL from commit `893b109`.

```sh
python3 -B tests/phone/mmc_mister/read_original.py /path/to/sega-rally.mmc \
    --bytes 8192 --mmc-clk-div 1 --multiblock --sectors 64 --extra-ack-clocks 19500
```

Omit `--extra-ack-clocks` for the ordinary backing model. Use `--mmc-clk-div 2`
for the 39 MHz control and `--sectors 8` for the short CMD18 sequence. The
default CMD17 test reads eight sectors.
[NOS timing experiment](phone-clocks.md#2026-11-18--v5-nos-deadline-cadence) ·
[Combined run evidence](evidence/mmc-full-rate-v5-20261118.json).

## 2026-11-18 — v5 flash capacity and MMC divider

The two controls use the stock PCM path and the v5 CPU's 16 KiB I/D caches.
The D2 data line is 32 bytes in every build. The 32 KiB candidate changes
only the number of resident D2 lines from 256 to 1,024 for each MMC divider.
At reset these configurations take 256 and 1,024 clocks to clear the D2
valid tags. Full-capacity tests read every line twice and require zero DDR
requests on the second pass. They also check that one colliding tag evicts
only its own index.

The 78 MHz PLL output drives the CPU, SDRAM controller and flash DDR
arbiter/adapter. SDRAM uses the same-rate DDIO clock with rising edges on
the falling system clock and unchanged refresh at 5,100 system clocks.
The 64-bit FPGA-to-HPS DDR port uses `DDRAM_CLK = clk_sys` through
`sys_top` RAM1 and the HPS `f2h_sdram1_clk` input. Both CPU-to-SDRAM and
CPU-to-DDR-bridge clock ratios are 1:1. The board's HPS DDR3 controller
has its own memory-interface clock beyond this port. The FPGA sources
and SDC do not specify that clock's rate. The SDC's 100 MHz
`h2f_user0_clk` is a separate HPS fabric clock.

The MMC clock here is a modeled bit clock between the FPGA host and card.
The original divider is 4 (19.5 MHz) and the trial divider is 2 (39 MHz).
At divider 2 the rising-edge FIFO update coincides with the period-end
decision. The host now rechecks FIFO occupancy and engine state in the
next low phase before raising another bit clock. Before the fix, the
actual host/card/DMA fixture read incorrect bytes at stage 7, and the
pin fixture reproduced extra clocks at a full RX FIFO. The pin monitor
also now samples the coincident CMD/DAT enable and first rising edge.

### Refill trace

The real ARM9V2, NOR, flash bridge and D2 are traced in all four settings.
The model returns three consecutive 64-bit beats, then stalls the last
beat by 48 extra clocks. All rows check data against the assembled image.
Each cold scalar case tests both halves of its target beat and emits one
four-beat DDR read. Warm repeats use zero DDR reads. From D2 admission to
scalar response is 2 clocks, including 1 clock from lookup to registered
data. CPU scalar ACK is 4 clocks after warm D2 admission.

| Wanted 64-bit beat | D2 scalar data from admission | CPU scalar ACK | Physical tail |
| ---: | ---: | ---: | ---: |
| 0 | 9 | 11 | 58 |
| 1 | 10 | 12 | 58 |
| 2 | 11 | 13 | 58 |
| 3 | 60 | 62 | 58 |

The next table uses the physical DDR request as cycle zero. Physical
returns occur at +4, +5, +6 and +55. Upstream line data occurs at +5,
+6, +7 and +56. Donor bus ACKs arrive at +6 through +11 and then +57/+58.
The D2 tag commits at +57 and the CPU I-cache installs the full line at
+59. Each target retires twice with the expected result. The CPU accepts
an early fetch for offsets 0, 8 and 16. Execution reaches the backend
at +64 and retirement at +66 in every case. This trace establishes early
forwarding and fetch acceptance with retirement after the tail. The
donor fetch queue marks an accepted instruction pending until fill
completion, which can still mark it faulted. The production wrapper
keeps that late-abort contract. All four ARM9V2 fallback and refill-abort
control runs also passed.

| Instruction entry offset | Correct fetch accepted | Execute result accepted | Retired |
| ---: | ---: | ---: | ---: |
| 0 | 7 | 64 | 66 |
| 8 | 9 | 64 | 66 |
| 16 | 11 | 64 | 66 |
| 24 | 58 | 64 | 66 |

### Same-work simulation

The original factory stock ROM boots cold with the 78 MHz CPU, 26 MHz
timers, 64 Hz NOS counter, identical formatted C: and no card inserted.
The first complete Nokia-logo write milestone is 36,689 guest LCD words.
The framebuffer matches byte for byte and each run has zero data faults.
Three early instruction faults occur in all cases. The asynchronous boot
reaches the same output with slightly different retired totals. The hot
loop below supplies an equal dynamic-instruction control. Wall time in
this table comes from simulated clocks converted at 78 MHz.

| Logo milestone | D2 8 KiB | D2 32 KiB |
| --- | ---: | ---: |
| CPU clocks | 295,684,044 | 295,666,749 |
| Milliseconds | 3,790.821 | 3,790.599 |
| D2 hits | 57,813 | 73,757 |
| D2 misses and DDR reads | 670,833 | 655,012 |
| Physical returned beats | 2,683,332 | 2,620,048 |
| Scalar flash-bus wait clocks | 236,749 | 236,194 |
| Bundled flash refill wait clocks | 6,077,640 | 5,983,485 |

The hot delay-loop window covers 4,064 entries at guest PC `0x6150`, with
321,056 retired instructions and 349,504 clocks (4.481 ms) in both
capacities. DDR reads, D2 lookups and flash-bus waits in the window are all
zero. The 24 KiB scan below is 37.14% faster at 32 KiB. The original boot
logo improves by 0.222 ms (0.00585%).

The MMC test stages only the eight sectors starting at LBA 32 and the
original Sega Rally 16 MiB card's identity/footer. The authored ARM
caller reads exactly 4,096 bytes through the actual card, host and RX DMA
with both SRAM guards intact. The host checks wire CRC and the independent
oracle compares all bytes, SHA-256 and CRC32 `98ac2258`. Both D2 sizes give
the same counts at each divider. A rise-to-rise monitor observes minimum
periods of four and two system clocks.

| 4,096-byte MMC transfer | Divider 4 | Divider 2 |
| --- | ---: | ---: |
| CPU clocks | 141,176 | 74,904 |
| Milliseconds | 1.810 | 0.960 |
| Flash DDR reads and D2 misses | 4 | 4 |
| D2 hits | 11,715 | 4,995 |
| Scalar flash wait clocks | 58,615 | 25,015 |

The independent pin CRC/error fixtures pass all 28 cases at each divider.
The v5 writable-card probe passes the same 512-byte write and PIO readback
at 269,479 and 250,288 clocks, respectively. Both runs reject a corrupted
last stored halfword. The tests model card/HPS media service. No hardware
MMC or gameplay timing is measured.

### Replay

Run `tests/phone/ddr_flash_cache/run.sh` in the existing simulator image for
the capacity, reset, ordering and hit checks. From the v5 checkout:

```sh
python3 -B tests/phone/ddr_flash_cache/run_trace.py --bytes 32768 --mmc-clk-div 2
python3 -B tests/phone/mmc_mister/read_original.py /path/to/sega-rally.mmc \
    --bytes 32768 --mmc-clk-div 2
python3 -B tests/phone/hardware_boot/run-logo.py --name v5-d2-example \
    --cycles 340000000 --stop-after-lcd-words 36689 --sys-clk-hz 78000000 \
    --timer-clock 26mhz --nos-tick-hz 64 --production-ddr --flash-cache-bytes 32768 \
    --mmc-clk-div 2 --stock-game-pcm --line-refill --cdrive /path/to/cdrive.img
```

### Matched Quartus fits and decision

All four seed-43 fits use the 78 MHz physical PLL, DDR debugger off and
stock PCM enabled. The manifest audit verifies each exact commit and
135 selected inputs. Within a divider pair the only selected source
change is the D2 capacity in Template. The 104 MHz figures analyze the
same routed builds with an alternate constraint. All four fit and
pass the checks for input, output and OE registers on all 16 SDRAM pins.

| D2 and MMC | ALMs | Placed ALMs | Occupied LABs | M10Ks | 78 MHz setup | 104 MHz setup | Hold at either clock |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| [8 KiB, 19.5 MHz](https://github.com/asturur/test_template_1/actions/runs/44365561035) | 35,939 | 38,632 | 4,102 | 411 | +0.151 ns | −3.013 ns | +0.082 ns |
| [32 KiB, 19.5 MHz](https://github.com/asturur/test_template_1/actions/runs/44368077206) | 36,045 | 38,773 | 4,127 | 437 | −0.030 ns | −3.235 ns | +0.090 ns |
| [8 KiB, 39 MHz](https://github.com/asturur/test_template_1/actions/runs/44370323925) | 36,443 | 39,045 | 4,151 | 411 | +0.096 ns | −2.821 ns | +0.112 ns |
| [32 KiB, 39 MHz](https://github.com/asturur/test_template_1/actions/runs/44370497216) | 36,079 | 38,787 | 4,134 | 437 | −0.268 ns | −3.473 ns | +0.110 ns |

The 32 KiB builds spend 26 more M10Ks in both pairs and miss 78 MHz setup
on paths from the CPU Wishbone merger to the DMA engine. The boot gain
is 0.222 ms on this workload and the original-card timing is identical
at the two capacities. V5 retains 8 KiB D2 and the 39 MHz MMC scheduler
at `15d3cfe`. Its committed tree matches the passing `e047712` fit.
The retained RBF SHA-256 is
`dff9bb9582d2ca9134bdadb4ab3242e22d931c88b78f00d47c02f778106164c9`.
Physical runtime qualification remains open.
[Machine evidence](evidence/ddr-flash-cache-v5-20261118.json).

## Original D2 implementation and sizing probe

The optional shared cache runs after DDR arbitration in the MiSTer top. Build
with `D2_FLASH_CACHE_BYTES` set to 8192, 16384 or 32768. The default value 0
selects the existing instruction ROM cache and DDR adapter. The D1 transport
has its own build option. D2 can use either transport and shares one tag and
data array between scalar reads and eligible instruction/data line refills.

The cache uses raw bytes at backing addresses 0x30000000–0x313effff for
firmware, 0x31400000–0x317fffff for C: and 0x31800000–0x3180ffff for PMM.
All three spans are aligned to 32-byte lines. Guard space and other DDR
addresses pass through. Existing NOR modules decide when a command, status,
identification or array read needs DDR. Descrambling still uses the original
guest address in the NOR and line response paths.

On admission, the cache captures the request and reads the synchronous tag
RAM and requested 64-bit beat in parallel. A scalar hit returns a registered
word one clock after acceptance. A line hit returns four registered beats
on successive clocks. A miss fetches a 32-byte line and copies each returning
beat into RAM. Line reads forward the registered beats as they arrive. A
scalar miss returns its requested word on that beat and keeps the cache busy
until the full burst completes. The tag becomes valid on terminal completion
with all four beats received.

The shared arbiter places firmware loading, NOS/BT writes and undo, C:/PMM
restore, and NOR program/erase on the same request path. The original cache
invalidates the matching resident tag during a masked write's lookup, ahead
of the DDR write. The next request waits for DDR acceptance and completion.
A write to a different tag at the same index, a zero-byte mask, or an address
outside the cached spans leaves the existing entry valid. A read that has
returned its word early still holds the fill descriptor and blocks new
admission. Future bulk writers must preserve this ordering or invalidate the
affected entries through the same cache.

Transport reset clears valid tags in a sweep and the backend drains accepted
reads. The first new miss waits for backend readiness. Phone reset and NOR
command handling use their existing upstream contracts.

| Capacity | Lines | Data RAM bits | Tag and valid RAM bits |
| ---: | ---: | ---: | ---: |
| 8 KiB | 256 | 65,536 | 5,120 |
| 16 KiB | 512 | 131,072 | 9,728 |
| 32 KiB | 1,024 | 262,144 | 18,432 |

These are RTL array sizes. Fitted block counts and clock timing require a
Quartus build.

## Results

The controlled reuse probe alternates scalar and line reads over sixteen
32-byte lines. Across 256 requests, D1 alone used 256 DDR reads and 1,920
elapsed clocks. D1 with D2 used 16 DDR reads and 1,280 clocks at each capacity,
including admission waits. The 240 hits account for 93.75% of the requests.
With the legacy transport underneath, the equivalent probe took 1,664 clocks
with the shared cache off and 1,264 with 8 KiB enabled. Both baselines have the
instruction-only cache disabled for the comparison.

The scalar probe measured 1 clock for a hit and 6 for a first-word miss with
D2. Uncached scalar reads took 3 clocks through the legacy transport and 4
through D1. A cold word in a later beat waits for that beat. The test peer
runs without DDR busy during the reuse probe.

The scan makes two passes over a separate 24 KiB region, issuing 1,536 scalar
requests under a cycle-based DDR busy schedule. It exposes the cost of
four-beat fills on low-reuse accesses.

| D1 transport configuration | Scan DDR reads | Scan elapsed clocks |
| --- | ---: | ---: |
| Cache off | 1,536 | 10,754 |
| 8 KiB | 1,536 | 17,919 |
| 16 KiB | 1,280 | 15,700 |
| 32 KiB | 768 | 11,264 |

The reuse win and scan cost justify keeping the cache optional until
representative firmware traces and fitted timing can guide the size and
allocation policy. The scan uses a cycle-based busy schedule, so DDR
acceptance delays vary with the request schedule.

## Reproduction

Use the existing `jotego/simulator:arm64` image with the integration worktree
mounted at `/work`. `tests/phone/ddr_flash_cache/run.sh` exercises both
transports with the shared cache off and the three candidate capacities. The
test checks returned words and beats against an independent memory image,
both 32-bit halves with every byte mask, alias behavior, ordered writes,
boundary bypass, early word completion and reset during refill.

`FLASH_CACHE_BYTES=8192 STREAM_TRANSPORT=1 sh tests/phone/raw_save/run-nor.sh`
uses the real NOR modules and four-slot HPS path. It checks changed C:/PMM
images against warmed cache entries, compares code words at the descrambler
boundaries, and exercises program, C: erase, C: identification and PMM status.

The overlay test uses synthetic NOS and Bluetooth packages built from the
integration worktree's stock firmware fixture. The packages exercise the
actual HPS transport, shared checksum ownership, apply/undo and all four
overlay combinations. The fixture generator, exact inputs and logs are under
`scratch/ngage2-integration/d2/`.
