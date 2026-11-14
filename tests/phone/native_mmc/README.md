# Original NEM-4 MMC long-response regression

Run `sh tests/phone/native_mmc/run.sh` from the repository root. Uses the
existing offline `jotego/simulator:arm64` image. Generated outputs, private ROM
bytes and input hashes remain under `build/sim/unit-native-mmc/`.

The real ZAP CPU executes unchanged original EPBUS transfer/event/status code
at503f4614,503f5574,503f52e4 and503f5550. The production native MMC host and ICU
handle an independent CRC-valid CID wire peer. An authored delayed-interrupt
envelope calls the original driver event routine for the actual ICU-selected
source, then resumes its original R2 state machine. Kernel scheduler/interrupt
exports are explicit no-op boundary spies; this is not a full Symbian boot.
Unused padding in their pages permits harmless speculative instruction fetch.

Before the host correction, delayed service selects source23/CmdIdle before
source24/CmdRdy. The original driver consumes only event2 and returns8000,
matching the MiSTer trace before any filesystem read. With the correction,
command-busy remains set until three R2 words have been consumed. The original
driver handles response-ready first, then command-idle and the fourth word.
All128 CID bits and final native state are checked. Runs with0/3 bus-wait clocks
pass at11463/16661 clocks. No imported MMC instruction is modified.

The authored envelope begins at the state registered by a pending R2 operation;
it does not execute the entire native card-enumeration/kernel scheduler path.
Actual native filesystem mounting, FPGA timing and game execution remain
separate hardware gates.
