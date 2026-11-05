#include "profile.h"
#include <stdio.h>
#include <string.h>
int main(void)
{
    ngm_state cardless, present;
    uint8_t reply[NGM_MAX_FRAME];
    const uint8_t request[] = {0,0,0x6c,0x09,5,0,0x25,1,0xe4,0x1d,0x2d};
    const uint8_t expected[] = {0,0x6c,0,9,0x12,0,1,0x25,0xe4,0x1e,0x2d,1,8,0x09,0x10,0x10,0x10,0x32,0x54,0x76,0x98,0,0,0};
    ngm_init(&cardless);
    present = cardless;
    ngage_test_sim_present(&present);
    if (!present.sim_registered || present.sim_state != 8 || !present.imsi_valid) return 1;
    unsigned n = ngm_handle(&present, request, sizeof request, reply);
    if (n != sizeof expected || memcmp(reply, expected, n)) {
        fprintf(stderr,"SIM IMSI reply mismatch, length %u\n",n); return 1;
    }
    /* Expose the remaining gap: 0x64 still returns not-serving even for
       a present card. Do not claim this diagnostic profile boots a SIM. */
    const uint8_t status_request[] = {0,0,0x6c,9,5,0,0x25,1,0xe5,0x64,0x61};
    n = ngm_handle(&present, status_request, sizeof status_request, reply);
    if (n != 16 || reply[9] != 0x65 || reply[11] != 0xfc) return 1;
    if (cardless.sim_registered || cardless.sim_state != 6 || cardless.imsi_valid) return 1;
    puts("PASS: diagnostic IMSI response; startup-status gap detected");
    return 0;
}
