#include "../simif-board/board/boot_profile.h"
#include <cassert>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>
int main() {
    std::ifstream input("build/firmware/nem4-factory/core.bin", std::ios::binary);
    assert(input);
    std::vector<uint8_t> rom((std::istreambuf_iterator<char>(input)), {});
    BootProfile present(rom, rom.size(), "amd16");
    BootProfile absent(rom, rom.size(), "amd16");
    absent.set_simif_no_atr(true);
    uint32_t data = 0;
    std::string device;
    BootBusRequest setup{0x0c150808, 1, 3, true};
    present.access(setup, data, device);
    absent.access(setup, data, device);
    assert(present.simif_pending());
    assert(!absent.simif_pending());
    BootBusRequest fifo{0x0c15080c, 0, 3, false};
    assert(present.access(fifo, data, device) && data == 0x3b);
    assert(absent.access(fifo, data, device) && data == 0);
    assert(device == "probe_simif_no_atr");
    std::puts("PASS: diagnostic no-ATR switch preserves card-present default");
}
