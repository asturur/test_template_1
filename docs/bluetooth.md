# N-Gage Bluetooth investigation

The N-Gage schematic `ser-no-n-gage-schematics.pdf`, page 17, identifies N430 as **LRB2_0630271**. The [FCC LRB-2 test report](https://fcc.report/FCC-ID/ppinpl1/183701.pdf) identifies Nokia's LRB-2 module and lists an Ollie2 baseband and Stan2 radio. The [Nokia LRB-1 preliminary manual](https://fcc.report/FCC-ID/OW3BT101/145450.pdf) describes a related module, including UART and Nokia-specific HCI commands; it is not an LRB-2 register specification. The related [6310i baseband manual](https://electronicsandbooks.com/edt/manual/Hardware/N/Nokia/Phone/6310I/03-npl-1%20%5B52%5D.pdf) describes a separately programmed BT102 with CBUS, UART and synchronization signals. Its exact protocol cannot be assumed identical to N-Gage.

On the N-Gage schematic, LRB-2 GPP0/1 (pins 38/37) connect to UPP GENIO21/22, labelled LPRFSync/LPRFInt; GPP6/7 (28/27) connect to GENIO19/20, labelled USARTRx/USARTTx. GPP10/11 and CENX (36/35/34) connect to CBUS clock, data and enable. RESETX is pin 44; SLEEPX 48; OSCON 31; EN26MHZ 18; SYSCLK 50; SLPCLK 26. Signal names are reproduced as labelled on the schematic; direction and reset levels still require verification.

The existing long-boot model returns assumed CBUS inputs or echoes written values, not responses from an LRB-2. Previous `BTLDD/HCI -33` timeout messages are consistent with an absent transport, but their cause is not proven. The emulator in `scratch/fresh-c-investigation/ngvm4/sw/kernel/chan.c` implements a high-level, no-radio HCI channel; its framing is an emulator interface, not evidence for the physical CBUS/UART protocol.

`rtl/ngage_bt_hci_stub.sv` is an isolated experimental no-radio HCI command responder based on that emulator. Run `tests/bluetooth/hci/sim.sh` for its directed tests. It is not connected to the phone model, and does not resolve the firmware timeout. Correct integration requires the real LRB-2 transport/register behavior, interrupt and reset sequencing; never substitute HLE channel bytes directly for physical CBUS transactions without evidence.

The matching NEM-4 retail BTLDD is ARM code at503F0AB0. Its original wrappers
503F2584/503F25E4 issue device5,16-bit logical register writes/reads; register27
maps physicalA6. A real capture positively shows reset writesA6=0/1. Older
preliminary20E4/2144 addresses from a different dump are literal pools in this
image and must not be used. Original CBUS callback503825EC tests GENIO status
150102/10 (full bit20), invokes BTLDD503F1298, W1C-acks it and queues503F12D4.
Twelve original-instruction cases qualify that callback; logical CBUS event24
is not ICU IRQ24. Production lacks the bit20 producer and proper W1C ownership.
Full LRB2 reset/sync/status semantics and HCI transport remain unimplemented;
see [bt-adsp-startup-race.md](bt-adsp-startup-race.md) for exact evidence/tests.
A complete LRB-2 register/pin protocol datasheet remains missing.
