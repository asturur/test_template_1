# Shared CTSI bus and interrupt ownership

Run `sh tests/phone/ctsi_board/run.sh` from the repository root.

Two real board instances compare immediate and registered responses. A native
SIMIF ATR and externally supplied UART RX byte coexist on status word0C1500B8:
SIM low halfword, EUART high halfword. Tests cover independent masks and ACKs,
shared ICU FIQ26, early RX acknowledgement, exact-once destructive reads and TX
writes under held results, TX-idle/backpressure/drain, and warm reset. No NOS
readiness or DSP firmware completion is simulated by this fixture.
