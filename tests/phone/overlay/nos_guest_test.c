// SPDX-License-Identifier: GPL-3.0-or-later
// Exercise the maintained guest payload with checked host-backed guest pointers.
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static uint32_t ram[0x10000 / 4];
static volatile uint8_t *guest(uint32_t address)
{
    assert(address >= 0x80000000u && address < 0x80010000u);
    return (volatile uint8_t *)ram + (address - 0x80000000u);
}
#define NOS_MEM(a) guest(a)
#include "../../../firmware_overlays/nos/nos_isi.c"
const uint32_t nos_vtbl[6] = {0};
static unsigned completions, deletes;
static int32_t reason;
void nos_complete(uint32_t chan, uint32_t request, int32_t result)
{
    assert(chan == 0x80001200 && request == 0);
    completions++;
    reason = result;
}
void nos_delete(uint32_t object)
{
    assert(object == 0x80001000);
    deletes++;
}
static void receive(unsigned capacity)
{
    WR32(0x80003000, 0x30000000);
    WR32(0x80003004, capacity);
    nos_request(0x80001000, NOS_REQ_RECV, 0x80003000, 0);
}
static void send_message(unsigned resource, unsigned command, unsigned value)
{
    uint8_t request[11] = {0, 1, 2, 0, 5, 0, 3, 4, 9, 0, 0};
    request[3] = resource;
    request[9] = command;
    request[10] = value;
    WR32(0x80002000, sizeof request);
    memcpy((void *)guest(0x80002004), request, sizeof request);
    nos_control(0x80001000, NOS_FN_SEND, 0x80002000, 0);
}
int main(void)
{
    assert(nos_ctor(0x80001000, 7) == 0x80001000);
    WR32(0x80001200 + NOS_CHAN_OBJ, 0x80001000);
    nos_attach(0x80001200, 7);
    assert(glob()->v.vib == NOS_VIB_LEVEL_INIT);
    receive(64);
    send_message(NOS_RES_ACC, NOS_MSG_ONOFF, 1);
    assert(completions == 1 && reason == 0);
    assert(RD32(0x80003000) == (0x30000000 | NOS_REPLY_LEN));
    assert(guest(0x80003008)[3] == NOS_RES_ACC);
    assert(guest(0x80003008)[9] == NOS_MSG_ONOFF + 1);
    assert(NOS_VIB_IS_ON(glob()->v.vib));
    // A send before receive queues exactly one response.
    send_message(NOS_RES_ACC, NOS_MSG_LEVEL, 255);
    assert(completions == 1 && chst(0x80001000)->queued);
    receive(64);
    assert(completions == 2 && reason == 0);
    assert(NOS_VIB_LEVEL(glob()->v.vib) == 100);
    // Cancel suppresses completion until another receive is posted.
    receive(64);
    nos_cancel(0x80001000, NOS_REQ_RECV);
    send_message(NOS_RES_ACC, NOS_MSG_ONOFF, 0);
    assert(completions == 2 && !NOS_VIB_IS_ON(glob()->v.vib));
    receive(8);
    assert(completions == 3 && reason == NOS_ERR_OVF);
    receive(64);
    assert(completions == 4 && reason == 0);
    // Unknown resources remain unimplemented, including cellular/SIM replies.
    receive(64);
    send_message(0x99, 1, 0);
    assert(completions == 4);
    nos_dtor(0x80001000, 1);
    assert(deletes == 1 && !chst(0x80001000)->rx_pend);
    puts("PASS NOS guest: attach, asynchronous receive, queue, cancel, overflow, vibration and unsupported-resource boundary");
    return 0;
}
