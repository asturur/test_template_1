# Peripheral master and interrupt integration

The current production path and verification limits are described in
[LCD DMA handover](lcd-dma-handover.md). Earlier standalone checkpoints below
are retained with their original scope; the frontend now owns production
registers and IRQs, with a dedicated fast LCD stream.

## B1 SDRAM contract

The current word arbiter captures address, direction, data and byte enables
when it grants a request. An owner holds the port through the terminal ACK.
When both clients keep presenting work, the next word grant alternates. A
client can keep its request asserted and replace its fields after ACK, as the
LCD DMA already does. An asserted CPU SWP lock blocks new DMA grants through
the read/write gap. A previously granted word completes before the CPU can
use the port. Warm reset cancels client ownership while the SDRAM adapter
drains the physical operation and discards its old response.

The bench checks 32 alternating CPU/DMA grants, changing live fields while
owned, masked write payloads, exact response ownership, the SWP gap and
reset/ACK coincidence. The existing controller and Micron model also pass
DMA write/readback, reset drain, line traffic and refresh at 78 and 104 MHz.
The LCD fixture passes all 18,304 words through the real arbiter. The optional
retained-firmware frame replay was skipped because its trace was unavailable
in the integration worktree.

## B1 captured DMA word route

`ngage_dma_route.v` captures one aligned physical word and its direction,
payload and byte enables. A command transfers ownership at `cmd_valid &&
cmd_ready`. The terminal `rsp_valid` returns data or an error. An unsupported
address, misalignment or empty byte mask returns an error without accessing
either bus. The response belongs to the captured command. Reset cancels the
client response. The downstream adapter must drain any accepted physical work
before admitting another request that could receive its response.

| Destination | Admitted words |
| --- | --- |
| SDRAM | `0x0a000000..0x0afffffc`, reads and masked writes |
| Shared NOS4K RAM | `0x0c004000..0x0c004ffc`, excluding boot scratch `0x0c004748..0x0c0047f8` |
| LCD data FIFO | Full-word writes to `0x0c121208`, with the observed DMA alias `0x10121208` |

Local `ready` indicates both an arbitration grant and that the endpoint has
reserved capacity. A paced command can wait in the router while CPU traffic
uses the local bus. A CPU SWP reservation prevents new local grants. After
acceptance, the endpoint owns the word until its terminal response. The same
word arbiter supports 32-bit local addresses in the fixture. The initial
LCD reader used the router's SDRAM path. The local port is wired through the
MiSTer and board modules to the live UPP bus. The donor's `0x10120624` MMC
alias and broad `0x1xxxxxxx`
translation still need NEM-4 evidence. The SDRAM route sees backing RAM
directly. Cached writes become visible through firmware cache maintenance.

The scripted test shares byte-enabled BRAM with a CPU peer, reserves one
FIFO slot, injects a target error and checks that rejected words and reset
produce no endpoint writes. The routed LCD fixture matches the direct
baseline at 18,304 words, checksum `02b0e100`, and 366,390 ns completion
time. Physical-controller simulations at 78 and 104 MHz also pass with the
router in the DMA path. These runs establish the word interface for P2.

The UPP grants a local DMA request at the CPU bridge's idle boundary and
captures the packet. A waiting LCD word asks for the bus once the panel
queue has room and the legacy LCD stream is clear on that edge. Eligible
CPU and DMA requests alternate at the shared boundary. The CPU's direct
SDRAM path remains independent. The UPP routes a terminal ACK or error to
the selected owner and gives the peripheral response register one request-low
cycle before the next access.

The ARM board regression exercises the production local port through the
router. The guest writes NOS4K RAM, a scripted DMA client reads and masks
it, and the guest sees the merged result while polling. The same client
gets an error for an LCD word sent before the header and commits one valid
word after the guest sets the header. DMA IRQ, CPU fault handling, SIMIF,
keypad and the other board checks pass. Guest channel programming and new
FIFO devices are P2/P3 work.

## P1 interrupt ownership

The follow-up [flow corrections](irq-timer-keypad-flow.md) replace the retained
raw-status/FIQ and timer-script assumptions after the first P1 checkpoint.


The NEM-4 kernel dispatcher at `0x5032287c` reads virtual `0x58120114`
and tries the other banks at `+0x40` and `+0x80` when earlier banks report
zero. It adds `0x5c` and the bank stride to the reported number before
calling the handler. ICU IRQ current now returns the lowest enabled pending
source as a one-based number in each bank, including 32 for the highest bit.
Raw status exposes all routed sources; both IRQ and FIQ current select only
enabled pending sources. Six timer levels feed both independently enabled planes.
The original boot explicitly masks IRQ0, and timer1 owns its separate ACK. Source 4 in IRQ bank 0 is special to the guest dispatcher
and needs its own evidence before routing a device there.

| Source | Current model owner | Evidence and integration limits |
| --- | --- | --- |
| IRQ 0 | Timer 0 | NEM-4 handler and 406,250 reload at the modeled 26 MHz tick. Existing rearm/mask behavior is staged. |
| IRQ 1 | Timer unit `0x20` and UEM/CBUS | Shared modeled line. ICU clear reaches both producers. Existing traces cover UEM wake/status and timer events. |
| IRQ 7 | DMA channel 1, commonly LCD | NEM-4 LCD programming and handler value 8. Completion waits for the accepted panel tail. |
| IRQ 21, 23, 24 | Production MMC host | Original NEM-4 kernel names/EPBUS bindings corroborate these sources. Host idle/response levels are transaction-model behavior, not verified phone pin timing. |
| IRQ 22 | Unconnected | Original kernel names this MMCDataRdy, but this EPBUS does not bind it. Its asserted-level meaning remains open; production keeps it low. |
| IRQ 25 | NOS compare and keypad | Independent pending bits feed one line. Each producer has its own acknowledgment. A legacy NEM-4 census identifies a shared CBUS handler here. |
| IRQ 46 | Unconnected | Retained NEM-4 census registered CBUS class 3, handler `0x8b`, with no clients at that stop. |
| FIQ 3 | Timer unit `0x60` | Retained NEM-4 medint DFC path and current value 4. |
| FIQ 26 | Diagnostic SIMIF and injected test input | Staged SIM interrupt route. Physical UEM/SIM signaling still needs validation. |
| IRQ 6, 8..13 | General DMA channels 0, 2..7 | Original NEM-4 name-index and enable path map channel `n` to bit `6+n`; all eight sources are wired in production. |
| Audio sources | Unconnected | The donor's HLE audio interrupt needs independent evidence. |

`ngage_icu_extra` retains storage for unclaimed DMA and EPBUS registers.
The production frontend overrides implemented `0x0c120300..04ff` channel
registers. The production MMC host now overrides implemented `0x0c120600`
registers and its FIFO, merging retained bits with captured side effects.
Known NEM-4 accesses include `0604`, `0614`, `0618` and `0624`.
Production DMA owns `0x0c120064/68` using the original helper's
clear-mask/set-value sequence and captured LCD request line 7. Physical
polarity remains unverified. Legacy comparison profiles retain the old ICU
diagnostic latches; the two owners do not commit the same access.

P3.3 adds selector-2 byte TX/RX with atomic FIFO admission, all-channel
stop/reset/ACK ownership and read-only slot-2 backing. See
[MMC production details](mmc-port.md) and
[final evidence](evidence/mmc-production-2026-11-11.json). Original EPBUS and
firmware mount acceptance remain separate; physical D550/AMA is unimplemented.

The ICU test checks all 96 source positions and all 1,584 within-bank
one- and two-source combinations. Timer, NOS, keypad, LCD and CBUS tests
exercise the connected owners. The production profile still uses the 26 MHz
timer clock and the experimental 64 Hz NOS counter at 78 MHz system clock.
Per-device ACK behavior and production routing for new DMA, MMC and audio
engines remain part of their device integration gates.

## P2 transfer engine and channel scheduler

The standalone Verilog-2001 engine and channel frontend are implemented as
`ngage_dma_engine.v` and `ngage_dma_channels.v`. Eight immutable queued
descriptors share three engines by default. The frontend dispatches channels
and engine words round-robin, retains one response owner and holds a selected
packet stable under backpressure. Register writes during a transfer affect
future starts. Restart cancels the old descriptor, drains its accepted word
and then dispatches the captured replacement. Stop keeps busy nonzero until
that drain completes. Reset requires the shared downstream cancellation/drain
boundary; completed write prefixes are not rolled back.

The engine consumes a literal 35-bit byte extent. It converts 8/16/32-bit
fixed or incrementing accesses into ordered bytes, with a partial final read
and write when necessary. An invalid width, zero extent, native-width
misalignment or address overflow produces an error before a bus request.
Target errors terminate rather than supply zero data or report success.

### Original driver count contract

The donor's universal source-width count rule is incompatible with the
original NEM-4 code. The public memory-copy path at `0x50330b88` passes a
byte-addressed contiguous chunk through `0x50330d10` to `0x503213c4` without
converting to halfwords. The low-level start at `0x50321424` programs
`(byte_length >> 1) - 1` even when setup selected 32-bit SDRAM widths.
For paced transfers, the original peripheral table determines the count
shift. MMC transmit has a 32-bit memory source and an 8-bit fixed destination,
with `count = byte_length - 1`. LCD uses 32-bit peripheral units.

| Start | Byte extent used by the frontend |
| --- | --- |
| 1, memory | `2 * (raw_count + 1)` |
| 2, memory to fixed peripheral | destination-width bytes times `(raw_count + 1)` |
| 2, fixed peripheral to memory | source-width bytes times `(raw_count + 1)` |

This reproduces the original software's programmed extent. The physical
interpretation of the mode/width fields, timing and bursts is unverified.
The traced caller does not prove arbitrary zero, odd or unaligned requests
valid. Unknown paced configurations with both sides fixed or both sides
incrementing terminate with a model diagnostic. Native-width alignment is
still required by the engine. No broad donor peripheral alias is admitted.

The register helpers at `0x50324b8c..0x50324ce4` confirm the channel stride
and offsets. The peripheral width table is `0x5034614c`; its count-shift
table is `0x50346170`. A reproducible private-ROM static audit is in
`tests/phone/dma_channels/audit_rom.py`.

### Interrupt and error ownership

Original DMA name descriptors initialized at `0x50323340 + 12*n` occupy
kernel name-table indices `0x63+n`. The initialized-data image at
`0x50347a64` maps to `0x80000000`; name-table lookup at `0x5032242c`
returns the index. Enable at `0x5032281c` subtracts `0x5d`, yielding IRQ
bank-0 bit `6+n`, for channels 0..7. This independently confirms the LCD
channel-1/source-7 mapping.

The original DMA ISR at `0x5032ca14` uses `0x50321860`, which returns
constant completion status 3, then stops the channel before another chunk
or callback. It does not distinguish a bus error. Consequently the candidate
frontend does not raise a normal completion IRQ for failed transfers. It
latches channel-relative `error_pending` for model diagnostics, without
inventing a guest hardware error register. Successful completion IRQs remain
pending until channel `+0x04=0` or `+0x08=0` acknowledges them.

### Verification and production gate

The standalone engine passes 4,914 independent byte-oracle cases and 52,326
owned words, including all widths/modes/lanes, partial source and destination
units, stalled and immediate responses, immutable descriptors, errors,
stop/restart, byte-count/address boundaries and coordinated reset.

The frontend passes with one and three engines through the actual router.
Checks include eight queued channels, selective IRQ ACK, ten-byte memory
copies at 32-bit width, byte-peripheral TX/RX extents and untouched trailing
bytes, paced peers, accepted-word drain/restart, endpoint errors, lock and
reset. The byte FIFO under a shared-RAM address is a fixture endpoint, not
new production hardware. Strict Verilog-2001 lint, source graph, formatting,
the retained LCD fixture and structural top checks pass.

At the initial standalone checkpoint both modules were in `files.qip` while
the legacy LCD owner remained selected. Production now selects the frontend
and fast stream as described above. Original setup/start/stop routines pass on ZAP
without instruction substitutions at zero and three memory-wait cycles
(11,130 and 16,814 cycles). Four exact 16-byte transfers cover SDRAM copy,
MMC-style FIFO send/receive and on-chip RAM copy. All SDRAM/on-chip bytes,
trailing guards, original kernel start bookkeeping and request-selector
writes are checked. The original stop routine acknowledges each channel;
only that channel has an IRQ at completion and its IRQ is clear before the
next start and at the final marker. The MMC address is intercepted by a
test-only byte FIFO; the production router still rejects it. See
`tests/phone/dma_original/`.

Original ISR/callee execution and production ownership are now covered by
the handover fixtures. Final CPU phase-10, fresh 5M smoke, formatter and top
checks pass, including a repeat after retiring the slow LCD switch. See
[final handover evidence](evidence/lcd-dma-final-2026-11-11.json). Full kernel
interrupt dispatch, a completed phone/UI boot, physical timing and FPGA fit
are not established by these fixtures.

Source/log hashes, fixture boundaries and measured results are recorded in
[the P2 evidence manifest](evidence/dma-engine-2026-11-11.json).

The corresponding donor count bug is fixed in local donor commit `7be19cd`
on `codex/dma-byte-count-fix`. Its original `master` baseline is unchanged.
Both RTL and actual C transfer functions reproduced the overread before
the fix; each now passes 2,650 cases. The existing peripheral regression and
strict lint pass. The private game-card replay and full QEMU build remain
unverified. The [portable donor patch](evidence/donor-dma-count-fix-2026-11-11.patch)
and [donor evidence](evidence/donor-dma-count-fix-2026-11-11.json) are retained
with the integration plan. The donor's existing error handling and broad
address aliases are separate from this count fix.
