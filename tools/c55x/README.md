# Local C55x disassembly aid

Reference: XVilka/c55xde commit fe0630ce6592506b372d2c8bc1700fb16106394f
(https://github.com/XVilka/c55xde), GPL-3.0. Keep its checkout in scratch/.
The pinned TI instruction reference is docs/TMS320VC5509AGHHAU-Texas-Instruments.pdf
(actual document SPRU374G).

`decoder.patch` fixes compilation, gives the executable a bounded file/range/base
CLI, fixes big-endian multi-byte operands and RET/RETI selection, and replaces
recursive unbounded text substitution (which crashed on port operands). It
also avoids inventing zero bytes for a final partially selected instruction.
These fixes do NOT make the incomplete upstream instruction tables a qualified
full C55x decoder. Check critical operands against TI opcode tables; retain raw
bytes and distinguish data from instructions. Relative branch outputs are raw
encoded offsets, not resolved virtual targets. Some syntax remains incomplete.

Reproduce using an authenticated gh CLI and a fresh reference checkout:

    gh repo clone XVilka/c55xde scratch/c55xde -- --depth 1
    git -C scratch/c55xde rev-parse HEAD
    # Require the pinned commit above before applying:
    git -C scratch/c55xde apply ../../tools/c55x/decoder.patch
    clang++ -O2 -std=gnu++11 -Wno-format -Wno-c99-designator \
      -Wno-deprecated-declarations scratch/c55xde/c55xde_main.cpp \
      -o scratch/c55xde/c55xde
    python3 tools/ngage_adsp_image.py --out scratch/adsp-analysis
    scratch/c55xde/c55xde \
      firmware/MCU/extracted/products/NEM-4/E403A400H450.USB \
      0x41200 0x73 0x400000
    scratch/c55xde/c55xde scratch/adsp-analysis/loaded-ram.bin 0x460 0x60

CLI arguments are file, file-offset, requested byte span, optional display-base.
The last instruction may extend beyond the requested span using actual source
bytes. The original firmware file is read-only; output stays private/local.
The reconstructed RAM has a separate validity file: holes are not executable
code or verified reset contents. No flash tail, code or on-chip ROM is inferred
from absent bytes. Do not load these analysis buffers onto hardware as a fix.
