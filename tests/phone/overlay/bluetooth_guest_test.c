// SPDX-License-Identifier: GPL-3.0-or-later
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include "../../../firmware_overlays/bluetooth/bt_hci.h"

struct guarded {
    uint32_t before;
    struct bt_st state;
    uint32_t after;
};
static struct guarded box;
static unsigned command(unsigned op, const uint8_t *params, unsigned length)
{
    uint8_t pkt[260] = {1, 0, (uint8_t)op, (uint8_t)(op >> 8), (uint8_t)length};
    assert(length <= 255);
    if (length) memcpy(pkt + 5, params, length);
    unsigned n = bt_hci_cmd(&box.state, pkt, length + 5);
    assert(n <= BT_OUT_LEN && box.before == 0x12345678 && box.after == 0x87654321);
    return n;
}
int main(void)
{
    box.before = 0x12345678;
    box.after = 0x87654321;
    memset(&box.state, 0xa5, sizeof box.state);
    assert(command(0x0c03, 0, 0) == 8); // HCI reset initializes stale RAM.
    assert(box.state.magic == BT_MAGIC && box.state.out[2] == 0x0e && box.state.out[7] == 0);
    assert(command(0x0c14, 0, 0) == 8 + BT_NAME);
    assert(memcmp(box.state.out + 8, "N-Gage", 6) == 0);
    const uint8_t name[] = "Test Bluetooth";
    assert(command(0x0c13, name, sizeof name) == 8);
    command(0x0c14, 0, 0);
    assert(memcmp(box.state.out + 8, name, sizeof name) == 0);
    command(0x0c03, 0, 0);
    command(0x0c14, 0, 0);
    assert(memcmp(box.state.out + 8, "N-Gage", 6) == 0);
    assert(command(0x0401, 0, 0) == 13); // Inquiry completes with no peers.
    assert(box.state.out[2] == 0x0f && box.state.out[4] == 0);
    assert(box.state.out[10] == 1 && box.state.out[12] == 0);
    const uint8_t address[6] = {1, 2, 3, 4, 5, 6};
    assert(command(0x0405, address, 6) == 23);
    assert(box.state.out[10] == 3 && box.state.out[12] == 4); // Page timeout.
    assert(memcmp(box.state.out + 15, address, 6) == 0);
    assert(command(0x0419, address, 6) == 267); // Remote name timeout, no fictitious peer.
    assert(box.state.out[10] == 7 && box.state.out[12] == 4);
    assert(command(0x7bff, 0, 0) == 8 && box.state.out[7] == 1); // Unknown command.
    assert(command(0xfc01, 0, 0) == 8 && box.state.out[7] == 0); // Vendor no-op.
    uint32_t dropped = box.state.dropped;
    uint8_t bad[5] = {1, 0, 3, 12, 1};
    assert(bt_hci_cmd(&box.state, bad, sizeof bad) == 0 && box.state.dropped == dropped + 1);
    uint8_t acl[1] = {2};
    uint32_t acl_count = box.state.acl;
    assert(bt_hci_cmd(&box.state, acl, sizeof acl) == 0 && box.state.acl == acl_count + 1);
    // Exercise every opcode's zero/max-length framing and guard output bounds.
    uint8_t max_params[255] = {0};
    for (unsigned op = 0; op <= 0xffff; op++) {
        command(op, 0, 0);
        command(op, max_params, sizeof max_params);
    }
    puts("PASS Bluetooth guest: reset/name/settings, no-peer inquiry/timeouts, unknown/vendor commands, malformed/ACL handling and bounded output");
    return 0;
}
