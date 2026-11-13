# Native NEM-4 CBUS client against HDL

Run `sh tests/phone/native_cbus/run.sh` from the repository root. Requires the
existing jotego/simulator:arm64 image, ARM binutils and the audited private
service backing at build/firmware/nem4-factory/core.bin. No image is downloaded.

Executes unchanged503822BC low-level CBUS write and503245FC/50324608 native HAL
helpers on ngage_cpu against ngage_cbus_uem. An authored caller writes logical
UEM register27 (wire3B). Checks reset-idle and completion polling, original
register encoding, payload, function success and immediate/three-wait bus cases.

ROM instructions are extracted without replacements; original SHA and boundary
are recorded in build/sim/unit-native-cbus/inputs.json. The testbench maps the
observed native HAL peripheral alias to the physical CBUS register bus. This is
not an MMU, serial CBUS, LRB2, full phone or factory self-test qualification.
