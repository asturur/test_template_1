# Original EUART1 driver on the HDL CPU

Run `sh tests/phone/native_euart/run.sh`. The existing simulator image runs
unchanged native transmit510E8BE8, receive-interrupt510E8D58, HAL load/store
and RTOS poll instructions copied from hash-checked original ROM pages.

The authored caller supplies logical-channel callbacks, the RTOS-running flag
and an interrupt invocation. UART TX bytes loop back into UART RX at the test
boundary; this exercises controller transport and interrupts, not a D550 DSP
response. Immediate and three-cycle memory waits must pass. Byte order, FIFO
ownership, count-minus-one, receive callbacks and original instruction pages
are checked. No production firmware instruction or IAT is rewritten.

The original interrupt handler also reaches its normal TX-idle path after
servicing RX; the fixture retains clock-control5814F008 for that HAL RMW.
It does not implement a real clock gate or physical UART timing. Production
UPP/shared-CTSI and external DSP protocol wiring are separate remaining gates.
Outputs live in build/sim/unit-native-euart; no old boot run is resumed.
