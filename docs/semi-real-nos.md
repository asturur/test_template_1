# NEM-4 NOS runtime and compatibility boundaries

The semi-real profile keeps the NEM-4 `nosstarter.ext`, original `gsmstuff`
initialization and original service registrations. The existing driver-only
compatibility overlay is useful as a comparison. It replaces two LDD imports
and the endpoint allocation, so its behavior cannot establish that original
channels or handlers ran. The experimental fake bootstrap remains a separate
diagnostic variant that previously failed the hardware logo test.

## Verified NEM-4 ABI

The retained application ROM dump confirms `nosdriver.ldd` imports at
`0x511b4028` and `0x511b4030`. They point to original `gsmstuff` ordinals 4
and 6 at `0x514a0a50` and `0x514a13cc`. The `gsmstuff` export table and
endpoint vtable agree with those imports and the published disassembly.
The saved DLL has a 96-byte header. After accounting for it, 2,186,624 bytes
of the executable image match the decoded flash window. The app ROM also
confirms the original `nosstarter.ext` branch at `0x50350504`.

Original channels keep an 8-byte endpoint at channel offset `0x38`.
The vtable at `0x5171103c` has Close, Cancel, Request and Control entries
at `+0x08`, `+0x0c`, `+0x10`, and `+0x14`. Registration writes the original
channel table at `0x8000c724`. The NOS work ring, scheduler and mailbox pump
own asynchronous requests. The original pump copies through kernel thread
descriptor APIs and completes through kernel ordinal 64.

The retained bounded instruction trace at the 2B checkpoint contains six
entries to the original DFC at `0x514a18d4` and ten to the mailbox pump at
`0x514a10cc`. It contains no sampled entry to the Phonet router or the energy,
SIM and phone-info handlers. The ROM supports the static routing analysis.
Per-resource ownership at runtime still needs targeted send/reply traces.

## Resource ownership for N2 and N3

| Path | Retain or adapt | Test before substitution |
| --- | --- | --- |
| `nosstarter.ext`, `gsmstuff`, kernel DFCs | Retain original startup, channel registration and scheduling | Trace original registration, receive wait, cancellation and close under the same firmware identity. |
| `0x17` energy and `0x1b` phone info | Retain original handlers when they answer. The local C and HDL responders provide a narrow fixture for specific missing request IDs. | Capture request and response around the original handler and check length, transaction ID, status and subblocks. |
| `0x09` logical SIM | Retain original server/state transitions where available. Use the local cardless/starting/serving protocol fixtures for the identified gaps. | Replay cardless, starting, ready, repeated queries and removal through the actual client. Trace physical SIMIF separately. |
| `0x1c` accessory and unrecognized messages | Leave original dispatch in charge. The donor couples one accessory reply to a synthetic SIM-ready indication. | Determine whether the actual accessory request needs any substitution and trace its completion. |
| `0x1f` tones, PCM `0xe8`, audio `0xf0..0xf3` | Keep MCU tone routing. The observed ADSP mailbox is a separate integration seam for PCM/audio. | Capture mailbox requests and completion before assigning audio ownership. |

The donor has useful descriptor decoding, per-channel queues and DFC delivery
patterns. Its fixed QD kernel export directory and replacement channel object
are specific to the donor. It handles request 0 and leaves other requests
pending. The NEM-4 ABI also tracks additional request slots, connection-state
notifications, teardown and original completion paths. The N2 splice should
delegate each untouched request to the original owner and transfer ownership
only for an identified request class, with one terminal completion across
receive, cancel, close and reset races.

The existing isolated `ngage_modem.v` and C reference agreed on 2,022
byte-exact frame vectors, including cardless and cached-IMSI cases. This
exercises the protocol responder. Channel ownership, original-handler
delegation and EKA1 DFC execution remain open. A new MMIO mailbox for
on-ARM NOS services would bypass the verified call path. Any transport to
an external responder needs an explicitly identified compatibility boundary.

## N2 cancellation ABI and first service probe

The original NEM-4 kernel consumes the cancel mask at `0x503350e4`. For
each enabled pending slot, `0x5033511c..0x50335128` calls
`DLogicalChannel::Complete` at `0x50334fcc` with `-3`. The completion helper
clears `channel+0x18+4*request` before updating the client and signalling.
`0x5033512c..0x5033513c` then calls the LDD with the **request number** in
`r1`. The LDD thunk at `0x511b41e8` forwards it to endpoint `0x514a183c`,
which validates channel state. The donor treats the endpoint argument as a
mask and completes again. For request 0 its `mask & 1` check skips cleanup,
leaving a stale receive that can outlive the kernel status slot.

Keep the original endpoint, scheduler, mailbox pump and kernel completion.
Control 4 reaches the router through `0x516c7ab8` and is a trace point.
The router copies non-pool frames using the little-endian length at `+4`
plus six, normalizes sender fields using the media ownership bit, and
frees a copied frame on nonzero routing status. Control 6 builds a header
on a separate path. A replacement at this boundary would take ownership of
frame allocation, dispatch, freeing and completion.

The first candidate probe is charger status `0x17/0x08`. The original Thumb
handler `0x5159446c` validates the ISI body flags, allocates a response through
`0x51594c7c` and reads charger state from `0x515c1dc0` / `0x515c1e4c` at
`0x515944a8` / `0x515944c4`. Trace the send, leaf call, reply enqueue and
ordinal 64. If the original path reaches a missing state value, replace
only that value and let the original handler own the response. No retained
trace has yet shown a charger request requiring this substitution.

The host Unicorn 2.1.4 trial failed in its native `init_cache_info` on a
one-instruction control as well as the NOS fixture. The execution fixture
now uses the existing HDL ARM simulator.

## Original-instruction fixtures

`tests/phone/nos_abi/run.sh` executes the original NEM-4 routines on ZAP with
zero and three memory-wait cycles. The fixture checks private input hashes,
maps the decoded NOS window and saved DLL body, and leaves the source files
untouched. Generated instruction images stay under `build/sim/unit-nos-abi`.

The cancellation cases execute the real kernel loop, completion and signal
helpers, LDD thunk and endpoint. A fixture callback records the request
number before delegating to the original thunk. Four mask/enable/pending
combinations check the cleared status slot before callback, client result
`-3`, one signal per cancelled request, untouched other slots and repeated
cancellation without another completion.

The receive case calls the original mailbox pump for object 5. It checks a
short descriptor receives numeric `-4` and a two-byte required length through
the auxiliary descriptor. The original pending message stays queued. It then
cancels a newly armed receive through the real kernel and confirms a pump
cannot complete that cleared status again. A sufficiently large retry copies
the same twelve message bytes, completes once and clears pending. Another
pump leaves the completed status and signal count intact.

The fixture substitutes the three thread-descriptor kernel leaves with
checked, single-address-space copies. It retains the original TPtr8/16
constructors and actual kernel completion. It exercises the calling ABI and
mailbox lifetime. Cross-process address translation, descriptor faults and
concurrent DFC scheduling remain integration tests.

The charger cases invoke the original Thumb handler for flags 0 through 4.
They retain the original response allocator, builders, subblock appender and
state providers. The pool allocator alone uses a fixed fixture buffer. A
modeled zero byte at virtual `0x58004049` produces charger status 1 and raw
value 0. The captured map places this at physical `0x0c004049`, in shared
NOS4K RAM. The byte's real producer still needs tracing. Each handler result
checks transaction ID, reply ID, status, block count, subblock bytes and
allocated frame length. The fixture also counts five allocations and four
provider reads across the cases.

Run from the integration repository root with private fixture paths.

```sh
sh tests/phone/nos_abi/run.sh /path/to/ngage-rom-0x50000000.dmp \
    /path/to/ngage-gsmstuff-0x5149D280.dll /path/to/window-dec.bin
```

`stub-boundaries.json` records every test-only redirection and original byte
sequence. No compatibility payload is changed by this test.

## Bounded original-runtime observations

Two separate two-million-cycle replays from stable 6.1B and 8.2B checkpoints
used the exact saved model archive. The original checkout was mounted
read-only. The 6.1B sample observed one original NOS DFC and one mailbox pump.
Neither sample observed the watched send, router, charger-handler or completion
entry. The data-fault count stayed zero and the backing-bus error count stayed
unchanged within the samples. These are sampled windows of a previously
audited model continuation. They do not establish a missing charger request.

Keep the original service owners while collecting the send, state-provider
write, handler, reply-enqueue and completion observations around an actual
request. A leaf substitution needs evidence of that specific gap. The
retained DFC/pump execution and original-instruction fixtures establish
which original paths the selective integration must preserve.
