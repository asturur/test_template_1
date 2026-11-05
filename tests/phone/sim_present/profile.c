#include "profile.h"
#include <string.h>
void ngage_test_sim_present(ngm_state *state)
{
    /* NGVM's explicitly fabricated MCC 001 / MNC 01 IMSI, 001010123456789. */
    static const uint8_t test_imsi[12] = {
        8, 0x09, 0x10, 0x10, 0x10, 0x32, 0x54, 0x76, 0x98, 0, 0, 0
    };
    state->sim_registered = 1;
    state->sim_state = 8;
    state->imsi_valid = 1;
    memcpy(state->imsi_ef, test_imsi, sizeof test_imsi);
}
