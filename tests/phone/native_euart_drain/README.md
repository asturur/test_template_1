# Original UART TX drain with no responding DSP

Run `sh tests/phone/native_euart_drain/run.sh` from the repository root.
The existing jotego/simulator:arm64 image and local ARM binutils are required.
Original firmware is hash-checked; copied code is private build output.

An authored ARM caller queues one55 byte then calls unchanged510E89CC with real
HAL/IAT/poll code and the board's UART. No DSP RX is delivered. A negative
control ties TX acceptance low and requires the actual one-byte/indices10
native polling deadlock. Positive cases admit TX only after its first index
read; the original function must drain and return without a receiver reply.
78/104MHz schedules and waits0/3 pass in17478/17958 cycles. This is not FPGA
routed timing or a completed D550 protocol test.
