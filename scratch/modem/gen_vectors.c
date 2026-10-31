/*  Vector generator: runs frames through the C modem model and emits a
    $readmemh stream for tb_modem.v:  req_len, req bytes..., resp_len,
    resp bytes...  (one hex byte per line). The RTL must match byte-exactly.
    Usage: ./gen_vectors > vectors.hex
    Made with Claude, 2026-10-31.
*/
#include "ngage_modem.h"
#include <stdio.h>
#include <stdlib.h>

static ngm_state s;

static void emit(const uint8_t *req, unsigned n)
{
    uint8_t resp[NGM_MAX_FRAME];
    unsigned rl = ngm_handle(&s, req, n, resp), i;
    printf("%02x\n", n);
    for (i = 0; i < n; i++) printf("%02x\n", req[i]);
    printf("%02x\n", rl);
    for (i = 0; i < rl; i++) printf("%02x\n", resp[i]);
}

/* coherent frame: length field = body bytes + 2 (objects count from off 6) */
static unsigned mk(uint8_t *f, uint8_t rxdev, uint8_t res,
                   const uint8_t *body, unsigned blen)
{
    f[0] = 0x00; f[1] = rxdev; f[2] = 0x6c; f[3] = res;
    f[4] = (uint8_t)(blen + 2); f[5] = 0x00;
    f[6] = 0x1f; f[7] = 0x01;
    for (unsigned i = 0; i < blen; i++) f[8 + i] = body[i];
    return 8 + blen;
}

int main(void)
{
    uint8_t f[NGM_MAX_FRAME], body[48];
    unsigned i, t;

    ngm_init(&s);
    srand(12345);

    /* directed: the test_modem.c set */
    { const uint8_t b[] = {0xa1,0x08,0x01}; emit(f, mk(f,0,0x17,b,3)); }
    { const uint8_t b[] = {0xa2,0x08,0x00}; emit(f, mk(f,0,0x17,b,3)); }
    { const uint8_t b[] = {0xa3,0x08,0x05}; emit(f, mk(f,0,0x17,b,3)); }
    { const uint8_t b[] = {0xb1,0x0a,0x03}; emit(f, mk(f,0,0x17,b,3)); }
    { const uint8_t b[] = {0xb2,0x0a,0x1f}; emit(f, mk(f,0,0x17,b,3)); }
    { const uint8_t b[] = {0xc1,0x33};      emit(f, mk(f,0,0x17,b,2)); }
    { const uint8_t b[] = {0xd1,0x00,0x41}; emit(f, mk(f,0,0x1b,b,3)); }
    { const uint8_t b[] = {0xe1,0x1d,0x2d}; emit(f, mk(f,0,0x09,b,3)); }
    { const uint8_t b[] = {0xe2,0x07};      emit(f, mk(f,0,0x55,b,2)); }
    { const uint8_t b[] = {0xf1,0x10};      emit(f, mk(f,0,0x1c,b,2)); }
    { const uint8_t b[] = {0xf2,0x08,0x01}; emit(f, mk(f,0x6c,0x17,b,3)); } /* silence */

    /* random sweep */
    for (t = 0; t < 2000; t++) {
        static const uint8_t resv[] = {0x09,0x17,0x17,0x17,0x1b,0x1c,0x10,0x3e};
        uint8_t res = resv[rand() & 7];
        unsigned blen = 2 + (rand() % 20);
        for (i = 0; i < blen; i++) body[i] = (uint8_t)rand();
        /* bias message ids toward the interesting ones */
        switch (rand() % 5) {
        case 0: body[1] = 0x08; break;
        case 1: body[1] = 0x0a; break;
        case 2: body[1] = 0x00; if (blen > 2 && !(rand() & 1)) body[2] = 0x41; break;
        case 3: { static const uint8_t k[] = {0x02,0x0f,0x22,0xe0,0xf0,0x10,0x12,0x1d};
                  body[1] = k[rand() & 7]; break; }
        default: break;
        }
        if (!(rand() % 10)) { /* wrong device -> silence */
            emit(f, mk(f, 0x6c, res, body, blen));
        } else {
            emit(f, mk(f, 0x00, res, body, blen));
        }
    }

    /* runts: total 7..9 -> silence both sides (len field 1..3) */
    for (t = 7; t <= 9; t++) {
        for (i = 0; i < t; i++) f[i] = (uint8_t)rand();
        f[1] = 0x00; f[4] = (uint8_t)(t - 6); f[5] = 0;
        emit(f, t);
    }

    printf("ff\n"); /* terminator: req_len 0xff */
    return 0;
}
