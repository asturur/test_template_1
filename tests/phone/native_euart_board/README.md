# Native ADSP UART through the production board

Run `sh tests/phone/native_euart_board/run.sh` from the repository root.
Requires the existing jotego/simulator:arm64 image and local ARM binutils.
Original EUART/HAL/IAT/poll instructions are extracted by prepare.py with the
same audited service-ROM hash as the isolated native_euart fixture.

The authored ARM caller enables FIQ26 and installs an exception wrapper. The
actual HDL CPU takes that interrupt and calls original RX ISR510E8D58; FIFO,
byte lanes, status acknowledgement and logical-channel callback remain native.
The board uses its external CPU bus profile; ctsi_board separately verifies the
production registered-response profile against the immediate profile, including
held accesses and simultaneous SIM/UART ownership. The fixture's device-side
byte loopback is not a D550 packet responder and is never enabled in production.

Four runs cover78/104MHz scheduling and memory waits0/3. They pass in27001 and
31140 cycles respectively, including the board's initialization. Clock scheduling
is not a routed FPGA timing result. The operating PLL remains78MHz.
