/*  N-Gage ISI/Phonet modem responder — pure frame-in/frame-out library.
    Byte-exact model of the NEM-4 v4.03 NOS servers' boot-gating replies,
    reversed from the real NOS code: see docs/modem-model.md (every byte
    below cites a disassembly address there).

    This is deliberately transport-agnostic: hand it a complete Phonet
    frame, it hands back the complete response frame (or none). The caller
    owns the wire/mailbox/queue. The same tables drive rtl/ngage_modem.v.

    Made with Claude, 2026-10-31.
*/
#ifndef NGAGE_MODEM_H
#define NGAGE_MODEM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Phonet resources we model (docs/modem-model.md section 3/4) */
#define NGM_RES_SIM        0x09
#define NGM_RES_ENERGY     0x17
#define NGM_RES_PHONE_INFO 0x1b
#define NGM_RES_ACCESSORY  0x1c

#define NGM_MAX_FRAME 64   /* longest modeled reply is the IMEI frame (32B) */

typedef struct {
    /* configuration */
    uint8_t own_dev;        /* this end's Phonet device id (0x00 on NEM-4) */
    uint8_t imei[16];       /* 15 ASCII digits + NUL (sb 0x41 payload)     */
    /* world state the replies report */
    uint8_t charger_status; /* sb 0x13 byte0: 1=not connected .. 5 (0x515c1dc0) */
    uint8_t charger_raw;    /* sb 0x14 byte0: raw UEM charger byte         */
    uint8_t batt_status;    /* sb 0x15 byte0: 1=ok 2/3/4 per 0x515c49e8    */
    uint8_t batt_bars;      /* sb 0x16 byte1: level 0..7 (byte0 is cst 7)  */
    uint16_t batt_mv;       /* sb 0x17 u16be                               */
    uint16_t batt_aux;      /* sb 0x18 u16be                               */
    uint8_t sim_registered; /* 0: SIM object unroutable -> router 0xF0 0x14 */
} ngm_state;

/* Fill s with the boot defaults (charger absent, battery full, IMEI zeros) */
void ngm_init(ngm_state *s);

/* Handle one complete Phonet frame req[0..req_len).
   Writes the full response frame into resp (capacity NGM_MAX_FRAME) and
   returns its length, or 0 when the real device sends nothing. */
unsigned ngm_handle(const ngm_state *s, const uint8_t *req, unsigned req_len,
                    uint8_t *resp);

#ifdef __cplusplus
}
#endif
#endif
