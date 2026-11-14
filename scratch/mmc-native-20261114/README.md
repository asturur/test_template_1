# Native MMC observer experiment

Goal: original firmware mounts the existing SPMark04 card.

The initial RDebug-based observer was invalid in kernel-driver context: native
ABT/recorded fault at503aec54, reason10000000 before MMC text reached output.
Do not infer any MMC failure from boot-trace.jsonl/probe-follow.jsonl.

Current trace.S uses only the existing privileged diagnostic byte port59000000,
no service/SWI, saves all GPRs and CPSR flags and replays displaced instructions.
128 randomized Unicorn cases verify exact output, state, stack and no mutation
of the observed driver object/request. Unicorn needs JIT permission outside
the sandbox. The logger is observation-only and not a production boot patch.

M B: command, argument, length, response kind, request pointer, object, wait mask.
M E: command, raw host status, driver errors, four little-endian response words.
The latter words are driver memory bytes; reverse bytes within each word to
recover the on-wire ordering. Original driver execution continues unchanged.

prepare_native_observer supplies fresh Hold/exact full image/saveOff guards and
retains the original firmware checksum check with diagnostic expected digest.
The generated apply report inherits an unused exit-tracer SHA label; the actual
MMC payload identity is in manifest.json and full instrumented image SHA is
verified by the remote guard. No exit tracer is installed. Reload undoes hooks.
