# Thumb prediction address regression

`sh tests/cpu/thumb_predict/alu.sh UNIQUE_OUTPUT` checks canonical fetch targets,
raw BX state transitions, failed conditions, real bit1 target differences,
ADD wrap and SPSR-restoring exception returns. ALU_FEEDBACK_RTL may select an
isolated same-interface candidate. No hardware, clock or phone images are changed.

`python3 tests/cpu/thumb_predict/micro.py --name UNIQUE --reference 2a04502`
compares current RTL with the pre-fix CPU using the same fixed32-call Thumb
programs and independent increment checks. Both BL alignments, memory profiles
0:0/2:9, warm-ups and two complete matching runs are required. It is separate
from the six original SPMark kernels and never changes their index weights.
`--candidate-alu PATH` freezes an isolated ALU override instead of editing RTL.
Sources/objects/results use new named directories; existing simulations and
checkpoints are untouched. Uses the existing jotego/simulator:arm64 image.

See docs/thumb-prediction-address.md for the original-code witness, qualification,
negative controls and remaining physical timing/native boot gates.
