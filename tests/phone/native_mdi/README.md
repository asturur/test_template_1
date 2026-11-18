# Original native MDI driver on the HDL CPU

Run `sh tests/phone/native_mdi/run.sh` from the project root. It uses the
existing `jotego/simulator:arm64` image and writes only
`build/sim/unit-native-mdi/`.

The authored caller executes unchanged service-ROM instructions for the native
MDI TX ring writer (515BF550), RX availability (515BF474), RX reader
(515BF65C) and byte-swap copy (515BF7D8). The input generator checks the
original ROM hash and records the copied ranges. The fixture aliases the
observed peripheral window, disables MMU/cache setup and supplies authored
initialization. It is not a complete native boot or MMU test.

The caller consumes the link announcement, sends the native resource F1/A0
RF-version request through the actual shared ring and checks each reply byte.
It then exercises the captured E8 PCM start format, first buffer, refill,
final-buffer completion and same-boot restart and stop. It rejects an
overlapping buffer pair and a refill from the wrong object. The player reads
two signed sample blocks through a fixture memory port. The test checks MDI
reply events, signed mono output and absence of the timer-5 IRQ. Both
immediate and three-cycle memory waits must pass. The modeled RF revision 03
is explicit synthetic device data.

Separate tests cover the original Info receiver -> INFO builder -> RF check
(`tests/tools/test_native_info_version.py`) and natural ring saturation,
wrap, backpressure, publication and reset (`tests/phone/upp_mdi/`). A separate
stock PCM fixture exercises the NOS dispatch to MDI task 4 and the return to
task 0x2c (`tests/phone/game_pcm/stock_route.py`).
