# D3 bulk DDR persistence

`D3_BULK_PERSISTENCE=1` selects the new persistence transport in the MiSTer
top. The default build selects the scalar bridge. Both paths use the same
raw C:/PMM images, dirty tracker, save manager and 512-byte HPS protocol.
The D3 sector port uses the D1 stream engine. Scalar and line transport and
the D2 cache have independent build settings.

A save submits one aligned 64-beat DDR read for a 512-byte sector. The shared
arbiters grant the descriptor under the usual SWP and ownership rules.
Another client may queue while it runs. Physical read beats enter the
stream buffer and the bridge copies each beat into four 16-bit words in
the HPS sector buffer. The bridge asserts the HPS write after it has copied
the full sector and received the DDR completion.

A restore validates the entire HPS sector before submitting a DDR write
descriptor. The bridge assembles four consecutive halfwords into each
64-bit write. The engine holds each physical write through DDR busy and
reports completion after all 64 writes have been accepted. Each physical
write uses burst count one.

## Ordering and reset

The sector port waits for both the scalar/line transport and D2 to become
idle. This includes the tail of a D2 fill after the caller has received
its scalar word. Once granted, the sector port owns the physical mux until
its terminal completion. Mutations accepted before the snapshot are in the
copy. A mutation that waits behind it can commit after the snapshot and
leaves the corresponding sector dirty for the next save pass.

Reads of a snapshot leave D2 tags in place. A bulk restore conservatively
invalidates the sixteen cache indices covered by the sector before the
scalar path can reopen. This includes any alias at those indices. The
instruction-only ROM cache covers addresses outside the persistence spans.

A transport reset keeps the mux attached to any accepted bulk read until
its physical tail drains. A terminal media change cancels the active bulk
descriptor. A physical write already offered through DDR busy can still
commit, and later stream beats stop. The existing save manager keeps the
phone held after an unsafe replacement. The DDR interface requires each
accepted read to return its declared beat count. The test stalls beats and
releases them to check the drain.

## Measured results

The four-slot HPS/NOR fixture used the same D1 transport with the cache off
for the scalar and bulk comparison. Its initial mount restores two C:
and two PMM sectors.

| Measure | Scalar | Bulk |
| --- | ---: | ---: |
| DDR writes during the four-sector restore | 512 | 256 |
| Simulation clock at restore completion | 7,993 | 5,950 |
| DDR read commands through six saves and the surrounding NOR operations | 775 | 13 |
| Simulation clock at save completion | 22,630 | 16,084 |

The read counts include seven scalar NOR operations in each mode. The six
sector snapshots account for 768 scalar commands or six bulk commands.
These clocks describe the modeled HPS/DDR schedule. FPGA resource fit,
board timing and physical persistence remain open.

The full-size fixture compares every word in the 4 MiB C: and 64 KiB PMM
images on both initial restore and reload. Each mode writes and checks the
last sector of both disks. Across the two restores, bulk uses 1,064,960
64-bit DDR writes and scalar uses 2,129,920 32-bit writes. The bulk path
uses exactly two 64-beat reads for the boundary saves.

## 4 KiB HPS restore assessment

The local `hps_io` encodes the count as blocks minus one. Eight 512-byte
blocks use count seven and 2,048 WIDE halfwords. The retained MiSTer Main
source decodes the block count, calculates the byte length and sends the
selected span from its host read-ahead buffer. A 4 KiB request can cut the
number of HPS acknowledgments by eight at the same byte count. The host
already reads ahead, so the effect on backing-file reads depends on the
host buffer. The installed Main build still needs qualification.

The current sector buffer and length checks accept 256 halfwords. A 4 KiB
implementation needs 2,048 checked halfwords and must validate the whole
host transaction before releasing data for eight ordered DDR descriptors.
The current implementation retains one-sector HPS requests while delivering
the measured reduction in DDR commands.

## Reproduction

Run `tests/phone/ddr_bulk/run.sh` in the existing simulator image to check
ownership, SWP, the D2 fill tail, a stalled sector, a queued mutation and
reset drain. Set `BULK_PERSISTENCE=1 STREAM_TRANSPORT=1` when running
`tests/phone/raw_save/run-nor.sh` for the actual HPS/NOR test. Add
`FLASH_CACHE_BYTES=8192` for the cache integration check. Set
`BULK_PERSISTENCE=1` for the full-size `tests/phone/raw_save/run-full.sh`
fixture. Logs and source identities are under
`scratch/ngage2-integration/d3/`.
