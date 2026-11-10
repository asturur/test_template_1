# D2 coherent flash backing cache

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
restore, and NOR program/erase on the same request path. An accepted masked
write invalidates its matching resident tag during lookup, before the DDR
write is offered. The next request waits for DDR acceptance and completion.
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
