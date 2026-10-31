/*  Unit tests for the ISI/Phonet modem responder. Expected bytes come from
    docs/modem-model.md (disassembly-read), not from ngvm. Run:
        cc -Wall -Wextra -o test_modem ngage_modem.c test_modem.c && ./test_modem
    Made with Claude, 2026-10-31.
*/
#include "ngage_modem.h"
#include <stdio.h>
#include <string.h>

static int fails;

static void expect(const char *name, const uint8_t *got, unsigned got_len,
                   const uint8_t *want, unsigned want_len)
{
    if (got_len == want_len && memcmp(got, want, want_len) == 0) {
        printf("PASS %s\n", name);
        return;
    }
    unsigned i;
    printf("FAIL %s\n  want(%u):", name, want_len);
    for (i = 0; i < want_len; i++) printf(" %02x", want[i]);
    printf("\n  got (%u):", got_len);
    for (i = 0; i < got_len; i++) printf(" %02x", got[i]);
    printf("\n");
    fails++;
}

/* build a request: media 0, rxdev 0 (us), txdev 0x6c, resource, len LE,
   rxobj, txobj 0x01, then body */
static unsigned mkreq(uint8_t *f, uint8_t res, uint8_t rxobj,
                      const uint8_t *body, unsigned blen)
{
    f[0] = 0x00; f[1] = 0x00; f[2] = 0x6c; f[3] = res;
    f[4] = (uint8_t)(blen + 2); f[5] = 0x00;
    f[6] = rxobj; f[7] = 0x01;
    memcpy(f + 8, body, blen);
    return 8 + blen;
}

int main(void)
{
    ngm_state s;
    uint8_t req[NGM_MAX_FRAME], resp[NGM_MAX_FRAME];
    unsigned n, rl;

    ngm_init(&s);

    /* 1. charger status, flags=1 (what Nokia.dsy asks): resp 0x09 OK,
          one subblock {0x13,4,1,0}  (0x5159446c + 0x515c1dc0 default) */
    {
        const uint8_t body[] = { 0xa1, 0x08, 0x01 };
        n = mkreq(req, 0x17, 0x1f, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want[] = { 0x00, 0x6c, 0x00, 0x17, 0x0a, 0x00, 0x01, 0x1f,
                                 0xa1, 0x09, 0x01, 0x01, 0x13, 0x04, 0x01, 0x00 };
        expect("energy charger flags=1", resp, rl, want, sizeof want);
    }

    /* 2. charger status, bad flags (0 and >3) -> {utid,0x09,0x02,0} */
    {
        const uint8_t body[] = { 0xa2, 0x08, 0x00 };
        n = mkreq(req, 0x17, 0x1f, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want[] = { 0x00, 0x6c, 0x00, 0x17, 0x06, 0x00, 0x01, 0x1f,
                                 0xa2, 0x09, 0x02, 0x00 };
        expect("energy charger flags=0 fail", resp, rl, want, sizeof want);

        const uint8_t body2[] = { 0xa3, 0x08, 0x05 };
        n = mkreq(req, 0x17, 0x1f, body2, sizeof body2);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want2[] = { 0x00, 0x6c, 0x00, 0x17, 0x06, 0x00, 0x01, 0x1f,
                                  0xa3, 0x09, 0x02, 0x00 };
        expect("energy charger flags=5 fail", resp, rl, want2, sizeof want2);
    }

    /* 3. battery status, flags=3: {0x15,4,1,0} + {0x16,4,7,bars} -
          byte0 of sb 0x16 is the CONSTANT 7, byte1 the level (doc s5.3) */
    {
        const uint8_t body[] = { 0xb1, 0x0a, 0x03 };
        n = mkreq(req, 0x17, 0x1f, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want[] = { 0x00, 0x6c, 0x00, 0x17, 0x0e, 0x00, 0x01, 0x1f,
                                 0xb1, 0x0b, 0x01, 0x02,
                                 0x15, 0x04, 0x01, 0x00,
                                 0x16, 0x04, 0x07, 0x07 };
        expect("energy battery flags=3", resp, rl, want, sizeof want);
    }

    /* 4. battery all five subblocks, flags=0x1F */
    {
        const uint8_t body[] = { 0xb2, 0x0a, 0x1f };
        n = mkreq(req, 0x17, 0x1f, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want[] = { 0x00, 0x6c, 0x00, 0x17, 0x1a, 0x00, 0x01, 0x1f,
                                 0xb2, 0x0b, 0x01, 0x05,
                                 0x15, 0x04, 0x01, 0x00,
                                 0x16, 0x04, 0x07, 0x07,
                                 0x17, 0x04, 0x0f, 0xa0,
                                 0x18, 0x04, 0x00, 0x00,
                                 0x25, 0x04, 0xff, 0xff };
        expect("energy battery flags=1F", resp, rl, want, sizeof want);
    }

    /* 5. energy unknown id 0x33 -> live-server {utid,0xF0,0x01,id,0,0,0,0} */
    {
        const uint8_t body[] = { 0xc1, 0x33 };
        n = mkreq(req, 0x17, 0x1f, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want[] = { 0x00, 0x6c, 0x00, 0x17, 0x0a, 0x00, 0x01, 0x1f,
                                 0xc1, 0xf0, 0x01, 0x33, 0x00, 0x00, 0x00, 0x00 };
        expect("energy unknown id", resp, rl, want, sizeof want);
    }

    /* 6. phone-info IMEI read: req 0x00 target 0x41 -> status 0 (INFO OK),
          sb {0x41, 0x14, 0x00, 0x10, 16 chars}  (0x5164bc80) */
    {
        const uint8_t body[] = { 0xd1, 0x00, 0x41 };
        n = mkreq(req, 0x1b, 0x0e, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        uint8_t want[32] = { 0x00, 0x6c, 0x00, 0x1b, 0x1a, 0x00, 0x01, 0x0e,
                             0xd1, 0x01, 0x00, 0x01, 0x41, 0x14, 0x00, 0x10 };
        memcpy(want + 16, "004400012345678", 16);
        expect("phone-info IMEI", resp, rl, want, sizeof want);
    }

    /* 7. SIM before registration -> ROUTER error 0xF0 0x14, 16-byte frame,
          length field 0x000A LE  (0x51530fa0) */
    {
        const uint8_t body[] = { 0xe1, 0x1d, 0x2d };
        n = mkreq(req, 0x09, 0x25, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want[] = { 0x00, 0x6c, 0x00, 0x09, 0x0a, 0x00, 0x01, 0x25,
                                 0xe1, 0xf0, 0x14, 0x1d, 0x01, 0x00, 0x00, 0x00 };
        expect("SIM unregistered -> not reachable", resp, rl, want, sizeof want);
    }

    /* 7b. SIM registered, cardless (state 6): 0x1D/0x2D -> not-serving
           {utid, 0x1E, 0x2D, 0xFC, state, 0x01, 0, 0}  (method 0x3114) */
    {
        s.sim_registered = 1;   /* state stays 6 from ngm_init */
        const uint8_t body[] = { 0xe2, 0x1d, 0x2d };
        n = mkreq(req, 0x09, 0x25, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want[] = { 0x00, 0x6c, 0x00, 0x09, 0x0a, 0x00, 0x01, 0x25,
                                 0xe2, 0x1e, 0x2d, 0xfc, 0x06, 0x01, 0x00, 0x00 };
        expect("SIM cardless -> 0xFC not serving", resp, rl, want, sizeof want);
    }

    /* 7c. SIM starting (state 1) -> 0xFB (method 0x3111) */
    {
        s.sim_state = 1;
        const uint8_t body[] = { 0xe3, 0x1d, 0x2d };
        n = mkreq(req, 0x09, 0x25, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want[] = { 0x00, 0x6c, 0x00, 0x09, 0x0a, 0x00, 0x01, 0x25,
                                 0xe3, 0x1e, 0x2d, 0xfb, 0x01, 0x01, 0x00, 0x00 };
        expect("SIM starting -> 0xFB", resp, rl, want, sizeof want);
    }

    /* 7d. SIM serving + IMSI cached: 16-byte body (builder 0x516601a8) */
    {
        s.sim_state = 8; s.imsi_valid = 1;
        memcpy(s.imsi_ef, "\x08\x29\x40\x02\x31\x57\x16\x92\x80\x00\x00\x00", 12);
        const uint8_t body[] = { 0xe4, 0x1d, 0x2d };
        n = mkreq(req, 0x09, 0x25, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        uint8_t want[24] = { 0x00, 0x6c, 0x00, 0x09, 0x12, 0x00, 0x01, 0x25,
                             0xe4, 0x1e, 0x2d, 0x01 };
        memcpy(want + 12, s.imsi_ef, 12);
        expect("SIM serving -> IMSI OK", resp, rl, want, sizeof want);
    }

    /* 7e. serving, cache invalid -> 0x24 + 12x 0xFF (0x515fc724) */
    {
        s.imsi_valid = 0;
        const uint8_t body[] = { 0xe5, 0x1d, 0x2d };
        n = mkreq(req, 0x09, 0x25, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        uint8_t want[24] = { 0x00, 0x6c, 0x00, 0x09, 0x12, 0x00, 0x01, 0x25,
                             0xe5, 0x1e, 0x2d, 0x24 };
        memset(want + 12, 0xff, 12);
        expect("SIM cache invalid -> 0x24", resp, rl, want, sizeof want);
    }

    /* 7f. unknown service under 0x1D -> 4-byte 0xFA (method 0x3110) */
    {
        const uint8_t body[] = { 0xe6, 0x1d, 0x55 };
        n = mkreq(req, 0x09, 0x25, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want[] = { 0x00, 0x6c, 0x00, 0x09, 0x06, 0x00, 0x01, 0x25,
                                 0xe6, 0x1e, 0x55, 0xfa };
        expect("SIM svc!=0x2D -> 0xFA", resp, rl, want, sizeof want);
    }

    /* 7g. req 0x64 -> 0x65 not-serving (INFERRED bytes) */
    {
        s.sim_state = 6;
        const uint8_t body[] = { 0xe7, 0x64, 0x2d };
        n = mkreq(req, 0x09, 0x25, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want[] = { 0x00, 0x6c, 0x00, 0x09, 0x0a, 0x00, 0x01, 0x25,
                                 0xe7, 0x65, 0x2d, 0xfc, 0x00, 0x00, 0x00, 0x00 };
        expect("SIM 0x64 -> 0x65 not serving", resp, rl, want, sizeof want);
        s.sim_registered = 0;   /* restore for later tests */
        s.sim_state = 6;
    }

    /* 8. unknown resource 0x55 -> same router error shape */
    {
        const uint8_t body[] = { 0xe2, 0x07 };
        n = mkreq(req, 0x55, 0x02, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want[] = { 0x00, 0x6c, 0x00, 0x55, 0x0a, 0x00, 0x01, 0x02,
                                 0xe2, 0xf0, 0x14, 0x07, 0x01, 0x00, 0x00, 0x00 };
        expect("unknown resource -> not reachable", resp, rl, want, sizeof want);
    }

    /* 9. accessory 0x10 -> 0x11 (inferred body) */
    {
        const uint8_t body[] = { 0xf1, 0x10 };
        n = mkreq(req, 0x1c, 0x2b, body, sizeof body);
        rl = ngm_handle(&s, req, n, resp);
        const uint8_t want[] = { 0x00, 0x6c, 0x00, 0x1c, 0x06, 0x00, 0x01, 0x2b,
                                 0xf1, 0x11, 0x01, 0x00 };
        expect("accessory 0x10->0x11", resp, rl, want, sizeof want);
    }

    /* 10. wrong receiver device -> silence (rxdev&0xFC != own_dev) */
    {
        const uint8_t body[] = { 0xf2, 0x08, 0x01 };
        n = mkreq(req, 0x17, 0x1f, body, sizeof body);
        req[1] = 0x6c;
        rl = ngm_handle(&s, req, n, resp);
        if (rl == 0) printf("PASS wrong rx device -> no reply\n");
        else { printf("FAIL wrong rx device: got %u bytes\n", rl); fails++; }
    }

    /* 11. runt frame -> silence */
    {
        rl = ngm_handle(&s, req, 9, resp);
        if (rl == 0) printf("PASS runt frame -> no reply\n");
        else { printf("FAIL runt frame: got %u bytes\n", rl); fails++; }
    }

    printf(fails ? "\n%d FAILURES\n" : "\nall tests passed\n", fails);
    return fails != 0;
}
