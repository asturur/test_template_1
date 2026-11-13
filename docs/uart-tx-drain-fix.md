2026-11-13 follow-up: the new3ab8e10/seed43 board image fails earlier with a
bad RAM pointer. Bounded native simulations pass; a concrete SDRAM output IO
packing defect is corrected separately. Physical qualification of that change
and on-board qualification of UART TX progress remain pending. No rollback of
dbe5bc6 or firmware patches. See [current investigation](sdram-early-boot-2026-11-13.md).

# First a413b1e hardware stopper: UART TX drain — 2026-11-13

**Confirmed root cause; one connection corrected in HDL. Hardware retest requires
another RBF.** No firmware patch, SIM state change, DSP reply, timeout extension,
PLL change, disk save or PMM modification.

## Observed board baseline

Autonomously launched installed _Console/ngage1 through Zaparoo from MENU, waited
for fresh CPU Hold and restored media, started read-only DDR capture, then used
F12/sevenDown/Enter/F12 to select Run. Autosave remained Off. The user confirmed
latest commit; artifact hash independently agrees:

* Source a413b1edf4fe961134edef94237af2b197ea0039; run43384167054, seed44.
* Installed/artifact RBF SHA256:
  b9752a43a405d02a800a7d3a5b7b979c1abdcc21c14d0d7169c051966705aa82.
* Live original ROM SHA256:
  88fd596a23269ecb0d9f7544d540c59010d276574dbe3d0262c870c429e58329.
  This was read with O_RDONLY/mmap.ACCESS_READ; it matches original firmware.
* C: af5017dcc0d4979ae9c7313a3a77295922009f08e26fbb559bd90d9539190a47;
  PMM71189f7fb6aed638640078fba3a35fda6c39c8962e74dcc75935aac948da9063.

The RBF's timestamp misleadingly predates the source commit; timestamps alone
must not identify it. Comparison against both completed artifacts settled this
without changing the board or monitoring/building CI.

Kernel text first reports repeated BTLDD/HCI -33, then iChannelCount=1. Those
errors do not themselves establish the hard stopper. Screenshot is the Nokia
logo. Later1065 retained snapshots spanning404 seconds all show the last bus
read0C15055C returning10; fetch/last PCs remain in original EUART driver/HAL,
including510E89EC,510E8F14 and503245FC. CPSR200000DB has IRQ/FIQ masked. Bus
ACKs keep advancing, errors stay13, reset generation0 and panic mask0. This is
an executing drain loop, not a DDR bus hang, kernel panic, reset or ViewSrv11.

Original ARM function510E89CC..510E89F4 reads the TX FIFO index twice, extracts
producer upper nibble and consumer lower nibble, and loops until equal.10 means
producer1/consumer0. One byte never leaves the controller.

## Root cause and exact correction

The previous integration tied ngage_mister.board.adsp_tx_ready permanently0
because the external DSP peer was absent. That conflated device response with
TX delivery and created an infinite stop/drain wait while interrupts were
masked. The earlier policy to backpressure an absent peer was wrong here.

Only this connection changes to1: the transaction-level serial output accepts
TX delivery even with no responding D550. adsp_rx_valid/data remain0. The DSP
may still time out or fail diagnostics normally; this does not fabricate an
ACK, reply, SIM-ready indication or successful self-test. Physical serial/baud
and future D550 ingress buffering remain separate unqualified behavior. No new
counter, queue, BRAM or timing-path stage is added.

## Reproduction and validation

New tests/phone/native_euart_drain executes the actual unchanged510E89CC drain/
stop function, driver/HAL/IAT/poll pages on the HDL CPU through the real board
bus. An authored caller queues one synthetic55 sync byte; DSP RX is absent.
The test sink waits until the first index read before accepting TX, so the
native wait must genuinely observe and drain an occupied FIFO.

* Negative control with TX ready permanently0 reproduces indices10, one owned
  byte and repeated native polls through the bounded60000-cycle fixture.
* TX-only delivery returns through the native routine:78/104MHz scheduling,
  waits0/3 pass in17478/17958 cycles including board initialization.
* Existing EUART FIFO/saturation/wrap/masks/ACK/reset, simultaneous SIM/UART
  immediate/registered CTSI ownership and full MiSTer CPU/board LCD/DMA/IRQ/FIQ/
  SDRAM integration pass. Verilog source manifest and formatting checked.

The synthetic55 test byte is not a claim about the unreadable byte value on
hardware. Allocation/firmware files and executable instructions are unchanged.
This proves the mechanism and HDL correction locally; it does not prove the
next RBF passes this point or boots Phone. No new FPGA fit/timing result.

Raw capture, ROM identity, media/RBF hashes, screenshots and original disassembly
are retained under scratch/board-debug-20261113. The read-only capture process
was stopped after preserving the stall; the phone was left running unchanged.
Maintained compact evidence: evidence/uart-tx-drain-2026-11-13.json.

## Next board comparison

Build the correction and repeat the same unmodified firmware/disks/autosave-Off
start. Confirm TX index progress and return from510E89CC first. Capture the next
native failure only after that comparison; do not add unrelated DSP/SIM/BT fixes
or restore the previous firmware-patch sequence.
