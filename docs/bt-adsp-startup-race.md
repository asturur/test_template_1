# Native Bluetooth/ADSP startup ordering

The462ba08 RBF contains the small D550 peer. One board run with UART/dispatcher
observation reaches the original NOS ADSP36 result00; another with completion/
assertion observation consumes late59/02 and asserts before8B completion.
The difference is scheduling-sensitive. Stable untouched firmware is not yet
qualified. Neither response filtering nor deadline extension is an HDL fix.

## Original-client reproduction

`tests/tools/test_native_startup_interleaving.py` executes immutable original
NOS instructions. The LPRF interface client516A5BE4 sends resource59/body
080103 and requests timeout1000. Its timeout-state branch reports0D. The next
ADSP client516A6218 sends resource82/body0E2B00070042 and requests3000. The
original generic response-pointer setter5164AB1C accepts the captured late
BT payload08020100 without a resource argument. Resuming the pending ADSP
client reproduces St_product.c/DF2, LR516A629B, exactly as on hardware.

The fixture explicitly supplies the timeout-state transition and message order;
it does not run the RTOS timer, Bluetooth process or prove the live trigger.
The original generic dispatcher5159192E calls that setter. The corrected ADSP
reply passes the separate original-client/transport and production CPU tests.
Thus the late-result ordering is sufficient to explain this assertion without
RAM corruption. The hardware reason for missing the earlier deadline remains
open. No production firmware, registry, replies or deadlines were changed.

Run in the existing offline simulator image with Linux Unicorn on PYTHONPATH:
`python3 tests/tools/test_native_startup_interleaving.py`. It writes compact
results under build/sim/unit-native-startup-interleaving. Local research and
captured-transfer extraction are in scratch/bt-adsp-race-20261114/.

## Native LRB2 transport evidence and next measurement

Use NEM-4 retail files, not firmware/disk_dump's different image. NEM-4
BTTestServer.exe SHA29bf8605... matches original core bytes at5036CEF0;
btldd.ldd matches503F0AB0 and is ARM code. The old preliminary503F20E4/2144
notes point into literal pools in this version, not valid function entries.

Original BTLDD503F2584/25E4 wrap CBUS write/read: device5, logical register,
width16, with the original virtual controller. Its constructor503F1190 writes
logical27=0 then1; the actual board's broad HAL capture positively sees repeated
wireA6=0/1. It has one reader gap: do not infer complete absence of other traffic.
Native routines refer to logical25/26/27/28/2A; read27 tests low handshake bits
and F0 events. Byte reception reads25 and consumes the upper byte first. Exact
reset/status/event/interrupt semantics still need a native-driver replay and
physical-model proof before selecting an LRB2 responder. Isolated HCI/HLE byte
responses must not be wired directly into CBUS. No LRB2 HDL change yet.

The constructor's callback registration argument24 is a CBUS event-table index:
entry50383BDC+24*12 is type2, not proof of ICU IRQ24. Do not wire a guessed IRQ.
Its registration calls through controller virtual method503826D8. Next trace
that event's provider and native status callback before defining a minimal
LRB2 reset/sync/CBUS transport. Keep the peer bounded and return unsupported
for application behavior that has not been established.

## SIM dependency

The production card selection is in7e893c8/build43552422501. The native SIM
subsystem still owns readiness. Older MTC READY/state8 is consistent with fatal
self-test rejection, rather than evidence that READY never occurs. Nokia's
later oFono definitions name state08 SELFTEST_FAIL,01 NORMAL,03 ALARM,04 TEST
and action04 READY; these are cross-generation corroboration, not independent
qualification of every NEM-4 enum. Primary source:
https://kernel.googlesource.com/pub/scm/network/ofono/ofono/+/refs/tags/2.14/drivers/isimodem/mtc.h
Cached read-only under scratch/bt-adsp-race-20261114/mtc.h. Establish the native
state transition on the new board run; do not force it to NORMAL/ready.

All volatile probes were removed and full original88fd.../Run/save-Off plus
unchanged C4a75.../PMM71189... were verified.78MHz PLL/104MHz design objective,
other simulations and user card data remain unchanged. No SD backups.
