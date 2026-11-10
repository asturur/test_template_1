# D1 DDR ownership and stream transport candidate

P0/S1/S2 are committed as `b232f1e` on `codex/ngage2-integration`. D1 implements
and locally tests an **opt-in transport candidate** below the existing NOR,
physical-address mapping, scalar arbitration and ROM cache. The shipped default
in `Template.sv` remains `D1_STREAM_TRANSPORT = 0`. No general flash cache,
bulk-save consumer migration, autosave or CPU/NOS/peripheral port is included.

## Sources and integration seam

Donor audit: read-only `ngage2` commit
`e3d2bf778319bdf4ef2bf21a4fc7376186b00a63`, `rtl/mem/ddram_flash.sv`.
Useful ideas are captured/held DDR commands, one outstanding read, ordered
64-beat bulk access and alternating service. New local Verilog-2001 modules
implement these transport contracts independently; donor QD chip geometry,
cache, beat-hit shortcuts, blank-C formatting and halfword address map were
not copied. Original NEM-4 backing decode and NOR command/status ownership
remain in their existing modules.

`ngage_ddr_stream.v` owns one descriptor through its complete transfer.
`ngage_ddr_stream_legacy.v` adapts the maintained 32-bit word/cache/32-byte line
interface, preserving lane mapping and pulse completion. `ngage_ddr_adapter.v`
selects the new backend with `STREAM_TRANSPORT=1`; the default selects the
original scalar backend. Existing outer arbiters retain response ownership,
CPU SWP reservation and round-robin grants. New modules are in `files.qip`.

To qualify the candidate at the top level, set the named Template localparam to
one and repeat the documented checks before hardware use. Existing ROM cache
selection/capacity/eligibility remain independent and unchanged. The refined candidate overlaps registered prefix delivery with physical read
reception while retaining full-burst capacity. This removes the initial D1
full-buffer wait; the current default production path remains a separate
legacy implementation. No performance, fitted BRAM usage, Fmax, timing
closure or default-enablement benefit is asserted without later measurement.

The wrapper changes instance hierarchy even in default mode. This does **not**
establish checkpoint binary or serialization compatibility. Old simulations
remain frozen on their original executable/source lineage; no checkpoint was
migrated and the other checkout's simulations/checkpoints remain untouched.

## Descriptor and transfer contract

Descriptors use `req_valid && req_ready` acceptance. Capture owner tag,
phone-cancel policy, read/write/stream operation, byte address, beat count,
inline data and byte mask. Live descriptor pins may change immediately after
acceptance. A producer retaining valid through another ready handshake submits
another request; valid is not a level-triggered completion acknowledgement.

| Operation | Descriptor | Data and completion |
| --- | --- | --- |
| Scalar read | Read, count1, 8-byte aligned address | One 64-bit beat; wrapper selects the original 32-bit half |
| Line read | Read, count4 | Four ordered beats, 32 bytes |
| Sector snapshot | Read, count64 | Sixty-four ordered beats, 512 bytes |
| Inline masked write | Write, stream0, count1 | Captured 64-bit data/eight lane enables; done after physical acceptance |
| Streaming restore | Write, stream1, count1..64 | Per-beat valid/ready data, eight lane enables and exact last marker; done after final physical acceptance |

Read lengths1..64 are supported, including boundary-crossing spans. Addresses
must be 8-byte aligned; the complete span must fit in the 32-bit byte-address
space. Count0/>64, misalignment, overflow and inline write count other than1
are rejected with owner-tagged `done/error`, without a DDR command. The legacy
wrapper retains its existing 32-bit-word alignment/lane convention and checks
that read count fits its configured line width.

Every stream mask is legal, including zero; inline descriptor mask/data apply
only to inline writes. The descriptor mask is ignored for reads/stream writes.
`write_last` must equal the final count position. A mismatch reports error
before issuing that beat. Any previously committed prefix remains committed;
neither error nor cancellation is reported as full transaction success.

DDR reads cannot be backpressured. A full512-byte `ngage_bram` response buffer
is reserved before issuing one read command, but delivery begins as soon as the
first captured beat is available. Data arriving on the command acceptance edge
is captured. Independent7-bit received/consumed counters track availability;
only RAM addresses truncate to6bits. Synchronous portB reads the next logical
head, with registered forwarding for a same-edge write-to-head collision.
This handles empty-to-nonempty arrival and simultaneous capture/consume without
using undefined mixed-port data or a combinational DDR-to-consumer path.

The first beat becomes valid after its capture edge and can transfer at the
next rising edge. With continuous physical data and client ready, the pipeline
sustains one beat per clock. `read_valid/data/owner/last` remain stable under
backpressure even when forwarding switches back to BRAM. Full64beat stalls fit
without overrunning or wrapping a live logical index. Successful `done` waits
for **both** physical reception of every beat and logical consumption of the
last beat. There is one outstanding physical read/descriptor through both
phases. No giant register array implements the buffer.

Delivered prefixes are provisional. The legacy wrapper copies incoming beats
into its staging line while the physical tail still arrives. Its always-ready
line output uses the engine's already registered head directly, without a
second beat register. Full transaction completion still follows the final
staged beat; the outer arbiter retains ownership until that terminal pulse. Existing CPU/cache
valid publication still waits for complete success. This is transport overlap,
not critical-word CPU restart or a D2 cache-valid shortcut. A canceled fill must
discard any prefix it received.

Streaming writes use **independent burstcount1 commands**, not assumed MiSTer
multi-beat write-burst behavior. Each accepted input beat is registered, held
unchanged through DDR busy, then committed once. The transport owns its entire
stream descriptor; a stalled stream producer delays peers. Bounded fairness is
therefore conditional on finite CPU locks, finite producer response and actual
DDR/client progress. Existing outer arbitration alternates continuously pending
owners at completed transaction boundaries; it does not guarantee an absolute
wall-clock latency while another owner is stalled.

Snapshots and restores are ordered memory transactions, not filesystem-atomic
operations or durable host saves. D3 must separately connect the wider consumers
and preserve dirty-generation/snapshot ordering before using these interfaces.

## Phone and transport reset

The retained legacy backend gates ISSUE commands with reset and may withdraw
an offer that is still busy-held. The candidate deliberately strengthens that
policy by finishing a previously offered command before cancellation/drain.
Old/new equivalence covers normal ordered effects; it does **not** claim equal
reset trajectories. Candidate-specific directed tests establish its held-command
and reset-drain safety independently.

`req_cancel_on_phone` is captured per descriptor. Phone reset cancels only
transactions carrying that policy. Noncancellable loader transactions can read
and write while the phone remains held. `transport_reset` cancels every current
descriptor and blocks admission, but does **not** assert reset on DDR itself.

Once a physical command is offered, it remains asserted with stable address,
data, mask and count through busy, even during either reset. A canceled read
must first be accepted and then drain its exact remaining physical beats before
reuse; no logical beats or successful completion escape. A busy-held canceled
write still commits its current offered beat exactly once, then stops before
later stream beats. Before a physical offer (admission or waiting for a stream
beat), cancellation may terminate immediately. Prefix delivery stops immediately
on cancellation; if its physical tail is still arriving, every remaining beat
must drain before cancellation completes. Already delivered logical prefixes
are discarded by the canceled-fill consumer. If physical reception is already
finished, buffered delivery can be discarded immediately.

The terminal `done` pulse includes the captured owner and `cancelled/error`
status for internal release; consumers must test those flags. If DDR never
returns an accepted read, reuse remains blocked. A reset cannot safely invent
missing completion or prove a controller has forgotten its outstanding work.

Production NOR writes retain the existing board's warm-reset drain and dirty
bookkeeping. The legacy wrapper deliberately ties direct phone cancellation
inactive: phone reset is coordinated above it, while the adapter receives the
separate transport reset. No speculative CPU-tag cancellation drops an already
accepted NOR mutation. Opt-in wrapper physical mux/busy gating also preserves
held scalar/line commands during transport reset, including when reset remains
asserted through actual acceptance.

## Verification and limitations

Use the existing `jotego/simulator:arm64` image, network disabled, with this
worktree mounted as `/work`. D1 entry points:

```sh
sh tests/phone/ddr_stream/run-overlap.sh
sh tests/phone/ddr_stream/run.sh
sh tests/phone/ddr_stream/run-equivalence.sh
sh tests/phone/ddr_stream/run-fabric.sh
STREAM_TRANSPORT=1 sh tests/phone/raw_save/run-nor.sh
```

The C++ test has independent byte memory and captured descriptor oracles. It
checks physical read address/count against accepted descriptors, physical write
address/data/mask against a planned queue, response bytes/owner/last against
captured expectations, and held physical/logical stability. All256masks,
randomized busy/data-ready/client-ready, earliest response, 32/512-byte boundary
crossings, malformed descriptors/last markers, committed-prefix errors and
phone/transport reset phases are covered. Loader readback completes while phone
reset remains asserted. Inputs are poisoned after descriptor acceptance.

The dual-adapter test compares old/new cache-disabled ordered effects and
independent byte images, including all16scalar masks in both32-bit halves.
Existing ROM-cache configurations also run with the new backend. The integrated
arbiter test covers competing scalar/line CPU and loader requests, owner routing,
24alternating grants, a finite SWP idle gap, loader readback and busy-held
scalar/line reset drain. Actual raw NOR/DDR/four-slot HPS integration exercises
C:/PMM persistence and proves immutable firmware bytes remain unchanged.

### Deterministic engine latency comparison

The comparator is the **initial full-buffer D1 candidate**, frozen under
`scratch/ngage2-integration/d1/fullbuffer-baseline/`, not the legacy
current-production DDR path. Both candidates use the same current driver,
request address/count, always-ready consumer and prescribed physical beat
schedule. Numbers below are clocks from first physical capture to the indicated
logical transfer; delayed-tail tests insert20clocks before the remaining beats.

| Read schedule | First transfer, full-buffer → overlap | Final transfer, full-buffer → overlap |
| --- | --- | --- |
| Continuous4beats | 5 → 1 | 8 → 4 |
| Delayed tail,4beats | 25 → 1 | 28 → 24 |
| Continuous64beats | 65 → 1 | 128 → 64 |
| Delayed tail,64beats | 85 → 1 | 148 → 84 |

These are synthetic engine-clock measurements. A separate delayed4beat adapter
probe measures one clock from first physical capture to first refill-beat
transfer with **both** the retained legacy backend and the refined candidate.
The candidate exposes its already registered head without adding a beat stage;
its terminal completion remains separate from the final streaming beat. No
CPU restart, phone boot speed or FPGA clock-rate improvement follows from
these measurements. The first logical transfer
occurs before the final physical beat in every directed4/64beat comparison.
The randomized suite's returned beat total changes when timing changes because
its PRNG schedule depends on progress; those totals are coverage counts, not a
matched throughput comparison.

Directed overlap coverage additionally stalls before the first beat and mid
burst, drains a full64beat buffer, catches up to empty, injects gapped arrivals,
exercises same-edge forwarding/consume including final physical capture, and
cancels after delivering a prefix with63physical beats still pending. The
adapter test observes copied prefix bytes while a physical tail is delayed,
no premature line completion/release, canceled-tail drain and a fresh fill.

Results and exact counts are in `merge-plan.md` and
`docs/evidence/ddr-stream-2026-11-10.json`. Logs and source/fixture identities
are under `scratch/ngage2-integration/d1/`; generated outputs under
`build/sim/unit-ddr-stream/` and `unit-d1-raw-save-nor/`.

No new full-phone boot/UI run or CPU performance comparison was needed for this
opt-in stage. The unchanged default path is regression-tested, with the existing
180-PASS CPU baseline retained. FPGA resources/timing, installed Main behavior
and physical persistence remain separate future gates. No D1 commit, push,
CI dispatch, Quartus build/download or deployment was performed.
