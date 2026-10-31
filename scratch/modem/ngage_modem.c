/*  N-Gage ISI/Phonet modem responder — implementation.
    Every reply byte is read from the real NOS disassembly; the citation
    comments are the addresses in docs/modem-model.md. Differences from the
    ngvm oracle are deliberate and listed in that doc's section 5:
      - length field is a LITTLE-endian u16 at offset 4 (router 0x514bce46)
      - battery subblock 0x16 carries {7, bars}, not {0, 7}
      - unroutable object -> router 0xF0 0x14; unknown id on a live server
        -> that server's 0xF0 0x01
      - status byte is per-server: energy 1=OK/2=FAIL, phone-info 0=OK

    Made with Claude, 2026-10-31.
*/
#include "ngage_modem.h"
#include <string.h>

void ngm_init(ngm_state *s)
{
    memset(s, 0, sizeof *s);
    s->own_dev        = 0x00;
    s->charger_status = 1;      /* 0x515c1dc0 default: not connected */
    s->charger_raw    = 0;
    s->batt_status    = 1;      /* 0x515c49e8 default path */
    s->batt_bars      = 7;      /* full */
    s->batt_mv        = 0x0fa0; /* 4000: plausible, not boot-gating */
    s->batt_aux       = 0;
    s->sim_registered = 0;      /* SIM server registers late (runtime, 0x515305c4) */
    memcpy(s->imei, "004400012345678", 16);
}

/* ---- frame building helpers -------------------------------------------- */

/* Start a reply to req: media 0, devices and objects swapped, same resource.
   Body length is patched in by fin(). (router error builder 0x51530fa0;
   normal replies go out the same header path 0x514ba352) */
static uint8_t *beg(const uint8_t *req, uint8_t *r)
{
    r[0] = 0x00;        /* media */
    r[1] = req[2];      /* rx dev <- req sender */
    r[2] = req[1];      /* tx dev <- req receiver */
    r[3] = req[3];      /* resource */
    r[6] = req[7];      /* rx obj <- req sender obj */
    r[7] = req[6];      /* tx obj <- req receiver obj */
    return r + 8;       /* body starts here */
}

/* Close the frame: length = bytes after offset 6, LITTLE-endian u16 @4
   (strh [r4,#4] at 0x51530fce; read back ldrh [r5,#4] at 0x514bce46). */
static unsigned fin(uint8_t *r, uint8_t *end)
{
    unsigned blen = (unsigned)(end - (r + 6));
    r[4] = (uint8_t)blen;
    r[5] = (uint8_t)(blen >> 8);
    return (unsigned)(end - r);
}

static unsigned popcount8(uint8_t v)
{
    unsigned n = 0;
    while (v) { n++; v &= (uint8_t)(v - 1); }
    return n;
}

/* ---- shared error replies ---------------------------------------------- */

/* Router: no object matched (error 6). 16-byte frame, body
   {utid, 0xF0, 0x14, req_id, 0x01, 0,0,0}, length 0x000A. (0x51530fa0) */
static unsigned reply_not_reachable(const uint8_t *req, uint8_t *r)
{
    uint8_t *b = beg(req, r);
    b[0] = req[8];  /* utid */
    b[1] = 0xf0;    /* COMMON_MESSAGE */
    b[2] = 0x14;    /* COMM_ISA_ENTITY_NOT_REACHABLE_RESP */
    b[3] = req[9];  /* the request's message id */
    b[4] = 0x01;
    b[5] = b[6] = b[7] = 0;   /* memset of 8 at r[8..15] first */
    return fin(r, b + 8);
}

/* Live server, unknown message id: {utid, 0xF0, 0x01, req_id, 0,0,0,0}
   (per-server builder 0x51594c44 / 0x51504658) */
static unsigned reply_not_identified(const uint8_t *req, uint8_t *r)
{
    uint8_t *b = beg(req, r);
    b[0] = req[8];
    b[1] = 0xf0;    /* COMMON_MESSAGE */
    b[2] = 0x01;    /* COMM_SERVICE_NOT_IDENTIFIED_RESP */
    b[3] = req[9];
    b[4] = b[5] = b[6] = b[7] = 0;
    return fin(r, b + 8);
}

/* ---- energy management server, resource 0x17 (section 3.1) ------------- */

/* status-fail variant 0x51594c00: {utid, id+1, 0x02, 0} */
static unsigned energy_fail(const uint8_t *req, uint8_t *r)
{
    uint8_t *b = beg(req, r);
    b[0] = req[8];
    b[1] = (uint8_t)(req[9] + 1);
    b[2] = 0x02;
    b[3] = 0x00;
    return fin(r, b + 4);
}

/* Charger status 0x08 -> 0x09 (handler 0x5159446c) */
static unsigned energy_charger(const ngm_state *s, const uint8_t *req,
                               uint8_t flags, uint8_t *r)
{
    if (flags == 0 || (flags & (uint8_t)~0x03))
        return energy_fail(req, r);
    uint8_t *b = beg(req, r);
    b[0] = req[8];
    b[1] = 0x09;
    b[2] = 0x01;                        /* energy server: 1 = OK (0x51594c7c) */
    b[3] = (uint8_t)popcount8(flags);
    uint8_t *p = b + 4;
    if (flags & 1) {                    /* {0x13, 4, charger_status, 0} */
        p[0] = 0x13; p[1] = 4; p[2] = s->charger_status; p[3] = 0; p += 4;
    }
    if (flags & 2) {                    /* {0x14, 4, raw UEM byte, 0} */
        p[0] = 0x14; p[1] = 4; p[2] = s->charger_raw; p[3] = 0; p += 4;
    }
    return fin(r, p);
}

/* Battery status 0x0A -> 0x0B (handler 0x515944ec) */
static unsigned energy_battery(const ngm_state *s, const uint8_t *req,
                               uint8_t flags, uint8_t *r)
{
    if (flags == 0 || (flags & (uint8_t)~0x1f))
        return energy_fail(req, r);
    uint8_t *b = beg(req, r);
    b[0] = req[8];
    b[1] = 0x0b;
    b[2] = 0x01;
    b[3] = (uint8_t)popcount8(flags);
    uint8_t *p = b + 4;
    if (flags & 0x01) {                 /* {0x15, 4, batt_status, 0} */
        p[0] = 0x15; p[1] = 4; p[2] = s->batt_status; p[3] = 0; p += 4;
    }
    if (flags & 0x02) {                 /* {0x16, 4, 7, bars} - cst 7 first! */
        p[0] = 0x16; p[1] = 4; p[2] = 0x07; p[3] = s->batt_bars; p += 4;
    }
    if (flags & 0x04) {                 /* {0x17, 4, u16be} (0x51594d54) */
        p[0] = 0x17; p[1] = 4;
        p[2] = (uint8_t)(s->batt_mv >> 8); p[3] = (uint8_t)s->batt_mv; p += 4;
    }
    if (flags & 0x08) {                 /* {0x18, 4, u16be} */
        p[0] = 0x18; p[1] = 4;
        p[2] = (uint8_t)(s->batt_aux >> 8); p[3] = (uint8_t)s->batt_aux; p += 4;
    }
    if (flags & 0x10) {                 /* {0x25, 4, 0xFF, 0xFF} */
        p[0] = 0x25; p[1] = 4; p[2] = 0xff; p[3] = 0xff; p += 4;
    }
    return fin(r, p);
}

/* Message ids the dispatcher 0x515937ac accepts (even req ids; the odd
   resp/indication ids are outbound only). Handlers beyond 0x08/0x0A are
   not byte-walked yet: answer the structural empty-OK {utid,id+1,1,0}
   (builder 0x51594bdc) so the client's state machine advances. */
static const uint8_t k_energy_ids[] = {
    0x00, 0x02, 0x04, 0x06, 0x0c, 0x0f, 0x11, 0x13, 0x15, 0x17, 0x19,
    0x1b, 0x1d, 0x1f, 0x22, 0x24, 0x26, 0xe0, 0xe2, 0xe4, 0xf0
};

static unsigned energy_dispatch(const ngm_state *s, const uint8_t *req,
                                uint8_t b2, uint8_t *r)
{
    uint8_t id = req[9];
    unsigned i;
    if (id == 0x08) return energy_charger(s, req, b2, r);
    if (id == 0x0a) return energy_battery(s, req, b2, r);
    for (i = 0; i < sizeof k_energy_ids; i++)
        if (k_energy_ids[i] == id) {
            uint8_t *b = beg(req, r);   /* empty-OK 0x51594bdc */
            b[0] = req[8];
            b[1] = (uint8_t)(id + 1);
            b[2] = 0x01;
            b[3] = 0x00;
            return fin(r, b + 4);
        }
    return reply_not_identified(req, r); /* default 0x51593a3c path */
}

/* ---- phone-info server, resource 0x1B (section 3.5) --------------------- */

static unsigned info_dispatch(const ngm_state *s, const uint8_t *req,
                              uint8_t b2, uint8_t *r)
{
    if (req[9] == 0x00 && b2 == 0x41) {        /* serial-number read, IMEI */
        uint8_t *b = beg(req, r);              /* handler 0x5164bc80 */
        b[0] = req[8];
        b[1] = 0x01;
        b[2] = 0x00;                           /* INFO server: 0 = OK */
        b[3] = 0x01;                           /* one subblock */
        b[4] = 0x41;                           /* sb id */
        b[5] = 0x14;                           /* sb len 20 */
        b[6] = 0x00;                           /* filler */
        b[7] = 0x10;                           /* string length 16 */
        memcpy(b + 8, s->imei, 16);            /* 15 digits + NUL */
        return fin(r, b + 24);
    }
    /* other targets / version reads (0x1B01..0x1B15) not walked yet */
    return reply_not_identified(req, r);
}

/* ---- accessory server, resource 0x1C (section 3.6, body INFERRED) ------- */

static unsigned acc_dispatch(const uint8_t *req, uint8_t *r)
{
    uint8_t id = req[9];
    if (id == 0x10 || id == 0x12) {
        /* startup manager consumes 0x1C11/0x1C12; one zero byte payload is
           ngvm's guess - handlers 0x516544xx not byte-walked. */
        uint8_t *b = beg(req, r);
        b[0] = req[8];
        b[1] = (uint8_t)(id + 1);
        b[2] = 0x01;
        b[3] = 0x00;
        return fin(r, b + 4);
    }
    return reply_not_identified(req, r);
}

/* ---- SIM server, resource 0x09 (section 3.4, partial) ------------------- */

static unsigned sim_dispatch(const ngm_state *s, const uint8_t *req, uint8_t *r)
{
    if (!s->sim_registered)
        return reply_not_reachable(req, r);    /* registers at runtime */
    if (req[9] == 0x1d) {
        /* read SIM data (svc byte req[10], 0x2D = IMSI). Resp 0x1E body is
           NOT yet extracted from the SIM task; send status-fail-shaped
           {utid, 0x1E, 0x02, 0} so clients see "no SIM" rather than a
           fabricated IMSI. */
        uint8_t *b = beg(req, r);
        b[0] = req[8];
        b[1] = 0x1e;
        b[2] = 0x02;
        b[3] = 0x00;
        return fin(r, b + 4);
    }
    return reply_not_identified(req, r);
}

/* ---- top-level router (section 2) --------------------------------------- */

unsigned ngm_handle(const ngm_state *s, const uint8_t *req, unsigned req_len,
                    uint8_t *resp)
{
    /* header + utid + msgid is the minimum the router itself dereferences */
    if (req_len < 10)
        return 0;
    /* receiver-device check: rxdev & 0xFC == own_dev (0x514bce96) */
    if ((uint8_t)(req[1] & 0xfc) != s->own_dev)
        return 0;
    /* body[2] (flags / target type) only exists in frames of 11+ bytes;
       model an absent byte as 0, never read past the frame */
    {
    uint8_t b2 = req_len > 10 ? req[10] : 0;
    switch (req[3]) {
    case NGM_RES_ENERGY:     return energy_dispatch(s, req, b2, resp);
    case NGM_RES_PHONE_INFO: return info_dispatch(s, req, b2, resp);
    case NGM_RES_ACCESSORY:  return acc_dispatch(req, resp);
    case NGM_RES_SIM:        return sim_dispatch(s, req, resp);
    default:                 return reply_not_reachable(req, resp);
    }
    }
}
