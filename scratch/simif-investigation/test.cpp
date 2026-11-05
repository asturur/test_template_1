#include "simif.h"
#include <cassert>
#include <cstdio>
int main() {
    SimIfProbe sim;
    uint8_t byte = 0;
    assert(!sim.status() && !sim.group_status() && !sim.fiq_pending());
    assert(!sim.pop(byte));
    sim.receive(0x3b); sim.receive(0x00); // synthetic minimal ATR, diagnostic only
    assert(sim.status() == 0x10 && sim.group_status() == 4 && !sim.fiq_pending());
    sim.set_group_enable(true);
    assert(sim.fiq_pending() == (1u << 26));
    sim.acknowledge(0x10);
    assert(!sim.status() && !sim.fiq_pending());
    assert(sim.pop(byte) && byte == 0x3b);
    assert(sim.pop(byte) && byte == 0x00);
    assert(!sim.pop(byte));
    sim.receive(0x90);
    sim.set_group_enable(false);
    assert(sim.status() == 0x10 && !sim.fiq_pending());
    std::puts("PASS: diagnostic SIMIF FIFO, status, masking and acknowledgement");
}
