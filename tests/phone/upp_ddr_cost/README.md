# Cost of sharing the HPS DDR port with UPP RAM

Run `tests/phone/upp_ddr_cost/run.sh` from this checkout with Icarus
Verilog. It extracts the retained RTL at `53b707b` into
`build/sim/upp-ddr-cost/rtl/` and records the results in
`build/sim/upp-ddr-cost/results.txt`.

The bench drives the retained arbiter and flash adapter with the
`Template.sv` parameters of 32 KiB flash cache, line fills, streaming
transport and bulk persistence support. Candidate requests use its existing
scalar interface. The simulated endpoint checks the write payload, both
32-bit word lanes, individual byte enables, read data, and command counts.
Every candidate access produces one 64-bit physical command, including
adjacent byte and halfword writes to the same beat.

| Physical model | BUSY clocks per 32 | First read data after command | Further read beats |
| --- | ---: | ---: | ---: |
| Fast | 0 | 2 clocks | Each clock |
| Medium | 8 | 8 clocks | Every 2 clocks |
| Slow | 16 | 20 clocks | Every 4 clocks |

Each busy period is contiguous. Contention cases add a second always-ready
requester reading a new flash line on every grant. The retained flash cache
fetches four beats for each miss. This is a stress case for shared-port
interference. No physical DDR timings or real independent flash traffic
distribution are assumed.

## Elapsed clocks

Upload counts come from cold game launches in a separate MAME experiment.
Their sequential halfword addresses and the NOS transaction sequence are
synthetic. The mixed NOS case interleaves 32 halfword writes with 30 sparse
reads. Counts include one handoff clock per request and any admission wait.

| Case | Fast | Medium | Slow | Medium + misses | Slow + misses |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sega, 18,124 upload writes | 108,744 | 144,990 | 193,320 | 579,954 | 966,606 |
| Sonic, 18,904 upload writes | 113,424 | 151,232 | 201,638 | 604,928 | 1,008,218 |
| 2,048 upload byte writes | 12,288 | 16,384 | 21,850 | 65,536 | 109,222 |
| NOS, 32 writes + 30 reads | 462 | 733 | 1,049 | 1,984 | 3,934 |
| Cold clear upload, 16,384 word writes | 98,304 | 131,072 | 174,770 | | |
| Cold clear NOS, 16,384 word writes | 98,304 | 131,072 | 174,758 | | |

With no busy wait, offer to completion is 5 clocks for a write and 8
for a read. For an incremental estimate, assume the existing registered
UPP response costs one local clock per write and two per read after capture,
and that handoff and existing bridge costs remain common. Subtract the local
response and one handoff clock per request from the first three columns.
That projects 72,496–157,072 added clocks for Sega, 75,616–163,830
for Sonic and 308–895 for mixed NOS. At 104 MHz these are 0.70–1.51 ms,
0.73–1.58 ms and 3.0–8.6 µs respectively. A new UPP-to-DDR request
bridge could add stages. Measurement of total guest costs requires that
bridge and representative instruction, DMA, flash and persistence traffic.

## Placement and cold initialization

The seed 43 fit report for the retained LCD reservation at `5f8fae0` includes
64 M10Ks for `upload_ram` and 64 for `nosmem_ram`. The candidate
RAM, RAM primitive and top-level DDR sources are identical at `53b707b`.
This is a gross saving of 64 M10Ks for either move and 128 for both. Net
savings and timing depend on the integration and its fitted resources.

The guest windows stay at `0x0c030000–0x0c03ffff` and
`0x0c100000–0x0c10ffff`. Preserve the existing legal byte enables,
config gating, read masks and the MDI register claims inside the latter
window. Preserve contents through warm reset and clear them on cold init.
Both local RAMs currently clear in parallel with the remaining UPP
arrays in 16,384 clocks. The remaining arrays still need that interval.

The model uses hypothetical backing ranges `0x31a00000–0x31a0ffff` and
`0x31a10000–0x31a1ffff`. These fall outside the raw flash cache, persistence
and project diagnostic ranges. Any actual allocation needs confirmation
against the deployed MiSTer memory layout.

The measured scalar clear uses 16,384 32-bit writes per bank. With both
banks and no other clients it uses about 197,000–350,000 clocks, or
1.89–3.36 ms at 104 MHz. Some or all of that cost could overlap other
cold initialization, depending on shared-port scheduling. A dedicated
64-bit zero writer needs 8,192 beats per bank. The existing stream
engine stages each 64-bit beat and then issues a single write, taking
at least two clocks per beat plus descriptor handoffs. Its 64-beat
bulk entry in the flash adapter accepts C:/PMM addresses only. Any
dedicated zero writer would need a separate admission path. The existing
write path does not generate physical multi-beat write bursts.
