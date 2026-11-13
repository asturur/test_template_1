## 2026-11-14: RF passes on hardware; ADSP assertion identified

Installed646ac68 nativeRF1E=00 is verified, with receiverF1/A1/body20A10103.
Later original-firmware boot can assert St_product.c/0xDF2 because the native
ADSP waiter expects ST_ADSP_RUN_RESP. Minimal assertion-only capture hasRF00,
ADSP pending03; an earlier successful capture completed ADSP with failed01.
The actual unexpected ID remains unmeasured. Older5902 cross-delivery evidence
is a specific follow-up lead, not today's proved sender. SIM remains non-serving5.
See [RF board evidence](rf-native-media.md) before repeating native startup work.

## 2026-11-13: donor-author checklist checked against native NOS

The author's supplied explanation confirms state5/no-card can leave Startup
waiting behind Insert SIM, without a crash. His stand-in bypasses native NOS
and PMM checks. System Agent ready-status7, internal SIM_Server serving-state8,
and MTC state8 are distinct fields/protocols; never substitute their numbers.

New tests execute the original NEM-4 handlers, getters and status mapper with
invalid cache inputs. Allocation/memory utilities/transport are fixture leaves;
native code, header creation and failure decisions are original. All five
optional reads send exactly once, free the request once and return24:

| Request/service | Native handler | Reply |
| --- | --- | --- |
|21/2C provider|51660384|22/2C/24|
|13/11 service table|5166042C|14/11/24|
|31/3B ALS/CSP|51661290|32/3B/24|
|33/3E operator|51661340|34/3E/24|
|29/37 dynamic flags|51661634|2A/37/24|

Cipher60/FA uses native asynchronous registration/getter/completion. Separate
original-code tests verify getter notification0/1/2 maps to reply61/FA status
24/30/31, respectively; registration/consumption and notification delivery are
explicit fixture leaves. Donor's actual header uses31 for not-required, so the
author's prose shorthand "all24" is not the exact cipher contract. No missing
native handler is demonstrated; production SIM5 still takes its own fallback,
and these direct handler fixtures do not prove serving initialization, real
queue delivery or application-level consumption.

INFO1B/02 is product-feature configuration, separate from Phone profile DB
rows and from SIM EF files. Static native dispatch reaches515B6FF4 (non1 target)
or515B74CC (target1), reads cached product data through514BFDA4/800C88A0 and
forms03 responses. No end-to-end INFO_PP hardware qualification or valid factory
profile is claimed. Do not return zero in HDL merely because the donor stub does.

Reproduce tests/tools/test_native_sim_optional_queries.py and
 tests/tools/test_native_sim_ciphering.py using the existing offline simulator
image/Linux Unicorn environment. ROM SHA e5870e91... remains unchanged in every
case. Board91045a6 independently reports DOS startup failure: RF1E/0D and
ADSP36/01 have fatal severity0C; see [current board evidence](board-boot-91045a6.md).
Original native SIM and RF/ADSP device behavior remain the required fixes.

## Subsequent completed boundary

Production EUART/CTSI integration and unchanged-driver CPU FIQ tests are now
complete; see [euart-production-integration.md](euart-production-integration.md).
The checkpoint below predates that wiring. D550 peer/SIM-ready remain open.

# Native SIM and ADSP implementation — 2026-11-13

Requirement: original NOS/firmware, HDL-only device behavior. Boot is **not
complete**. This checkpoint implements the diagnostic operation and verifies
native SIM optional-data completion; transport and native SIM-ready remain.
No firmware patches, board access, FPGA build, clock changes or CPU edits.

## SIM: use the existing original service, not a replacement stub

Donor SIM29/service37 already exists in NEM-4's service table at516E0758:
`29 37 2A 00 75 33 00 00 00 A7 0C 80`. Method3375 maps at516FB8C0 to51661635
(Thumb). The handler allocates8, builds2A with the original transaction and
service, calls getter515FD884, uses original status mapper5165EA98/context4,
sends once and frees the request once.

The getter tests bit1 of800CE04E (800CDD2C+322). Valid cache copies four bytes
from800CE334; invalid cache returns raw0, which the native mapper translates
to24. Thus the original NOS already provides the donor's needed unsupported
completion. Copying the guest software stub is unnecessary and violates scope.
The invalid-cache path leaves the four payload bytes untouched; consumers must
honor status rather than assume zero-filled data. This fixture preserves that
behavior explicitly with an A5 allocation canary.

`tests/tools/test_native_sim_dynamic_flags.py` passes absent, present/all-zero,
and present/nonzero data, native table/method binding, header, length, send/free,
stack and original ROM immutability. Trace/lock/allocation/transport leaves are
fixture services. No native initialization or physical-card success is inferred.

Production still selects no synthetic card. Enabling the existing card alone
previously left native state1 awaiting MTC READY/NORMAL. Do not force native
state8, inject DOS events or enable a software SIM overlay. Trace the actual
MTC/SIM initialization producer next; this cache test does not settle that gate.

## DSP: implemented native test42 operation and codec reset boundary

New Verilog-2001 modules:

* `rtl/ngage_adsp_diagnostic.v`: bounded D550 transaction operation derived from
  original451944/451B41. Test42 snapshots clock lock and valid flash markerFFFC,
  issues codec reset1E00 to slave1A, and returns0 only after successful codec
  completion with both prerequisites true. Any failed prerequisite or codec
  error produces0C. Unknown tests set explicit unsupported, not generic success.
* `rtl/ngage_aic23.v`: distinct N501 control boundary, acknowledging exactly
  the modeled slave1A/register15/data0 reset. Other addresses/control words
  return error; their codec behavior is explicitly unimplemented. The word
  transaction replaces I2C pins; it does not claim physical bus/PCM timing.

`tests/phone/adsp_diagnostic/run.sh` passes at78/104MHz scheduling. Tests cover
wrong codec address/data, each clock/flash-valid/marker/codec failure separately,
held codec requests, held results, repeated tests, unknown test and reset of a
stalled operation. Existing EUART FIFO/mask/ACK/flush/wrap test also passes.
Original ADSP image analysis already establishes the marker at file160000;
its physical flash mapping is still not executed/qualified.

No new queue, array, interpreter, multiplier or RAM is introduced by these two
blocks. They are not selected in files.qip or connected to production yet, so
this checkpoint does not change fitted area or make test42 complete on a phone.
Keep78MHz PLL and104MHz objective. Actual timing/area are NOT_RUN.

## Native transport findings and remaining integration

`tests/tools/test_native_adsp_packets.py` executes unchanged Symbian ADSP server
packet primitives: framing510EE1F4, sequence510EE088, checksum write510EDC0C
and verifier510EDC6C, with descriptor/allocator leaves supplied by the fixture.
The input descriptor is deliberately synthetic, not a captured startup request.
All eight sequence values pass; corrupt data is rejected; ROM stays unchanged.

TX starts55/55 and checksum excludes that16-bit preamble. RX verification works
on the packet after stripping it. Mixing the two views incorrectly rejects a
valid packet (captured failed exploratory check). Checksum is XOR over16-bit
words with byte-swapped return/stored high byte first, not CRC. RX parser510EEE18
reads length bytes4/5 big-endian and validates resource82/D0/7F with a bounded
length. These primitives do not yet establish the exact full request/reply,
startup/control and retransmission sequence that the device must implement.
Private bounded disassembly/probe: scratch/native-sim-adsp-20261113/.

Before production wiring: qualify the actual ADSP server startup/request
builder, ACK/reset/retry and D550 receiver layout; connect the EUART byte
transport and shared CTSI source ownership; connect this diagnostic operation
and N501 at the board chip boundaries with real reset/clock/flash inputs. Then
exercise unchanged host driver plus peer, failure propagation and original NOS
startup test. Finish native SIM/MTC-ready and test Phone/Menu under original
deadlines without any SSH/loader firmware writes. An isolated passing operation
is not an unmodified-firmware boot fix.

## Execution notes

Host Unicorn crashes with SIGILL inside the restricted process even on a single
ARM instruction. The same installed engine passes outside it; the native tests
above were executed there, not skipped or treated as firmware faults. Existing
jotego/simulator:arm64 supplies the pinned Linux Verible formatter. No new tool
image or Quartus download. Existing other-chat CPU/SDRAM/DMA edits preserved.
