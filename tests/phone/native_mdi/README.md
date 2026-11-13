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

The caller consumes the link announcement, sends the native resourceF1/A0
RF-version request through the actual shared ring and checks every byte of
the reply produced by `ngage_upp_mdi` and `ngage_upp_dsp_peer`. Both immediate
and three-cycle memory waits must pass. The modeled revision03 is explicit
synthetic device data, not a firmware patch or injected self-test result.

Separate tests cover the original Info receiver -> INFO builder -> RF check
(`tests/tools/test_native_info_version.py`) and natural ring saturation,
wrap, backpressure, publication and reset (`tests/phone/upp_mdi/`). The external
D550 audio DSP is separate and remains unimplemented.
