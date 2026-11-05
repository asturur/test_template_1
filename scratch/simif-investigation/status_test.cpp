#include "../simif-board/board/simif_status.h"
#include <cassert>
#include <cstdio>
int main() {
    static_assert(sizeof(simif_status_reply) == 18);
    assert(simif_status_reply[0] == 0x60);
    assert(simif_status_reply[5] == 0x7f && simif_status_reply[6] == 0x20);
    assert(simif_status_reply[7] == 2);
    assert(simif_status_reply[16] == 0x90 && simif_status_reply[17] == 0x00);
    std::puts("PASS: synthetic DF GSM STATUS response shape");
}
