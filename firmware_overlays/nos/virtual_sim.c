// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic SIM service at the native NEM-4 NOS boundary. Original NOS owns
// queues, envelopes, completions and every other service. Physical SIMIF stays
// absent; this profile owns native SIM_Server readiness and logical replies.
#include <stdint.h>

typedef uint32_t (*fallback_fn)(uint32_t,uint32_t,uint32_t,uint8_t *);
typedef uint8_t *(*allocate_fn)(uint32_t);
typedef void (*release_fn)(uint8_t *);
typedef uint32_t (*send_fn)(uint32_t,uint32_t,uint8_t *,uint32_t);
typedef uint32_t (*broadcast_fn)(uint32_t,uint8_t *);
typedef uint32_t (*response_id_fn)(uint32_t);
typedef void (*length_fn)(uint8_t *,uint32_t);
#define ALLOCATE ((allocate_fn)0x514b9a45)
#define RELEASE ((release_fn)0x514b9ab5)
#define SEND ((send_fn)0x5165eb51)
#define BROADCAST ((broadcast_fn)0x514ba2f9)
#define RESPONSE_ID ((response_id_fn)0x5159aff5)
#define SET_LENGTH ((length_fn)0x514b9b3d)
#define ORIGINAL ((fallback_fn)0x5165ed25)
#define SIM_STATE (*(volatile uint8_t *)0x800ca78c)

#ifdef VSIM_TRACE
static void trace(uint8_t kind,uint32_t value)
{
    volatile uint8_t *port=(volatile uint8_t *)0x59000000;
    int shift;
    *port='V'; *port=' '; *port=kind; *port=' ';
    for(shift=28;shift>=0;shift-=4) {
        unsigned digit=(value>>shift)&15;
        *port=(uint8_t)(digit<10?'0'+digit:'a'+digit-10);
    }
    *port='\n';
}
#else
#define trace(kind,value) ((void)0)
#endif

// Existing test-network identity001010123456789; not a physical SIM dump.
static const uint8_t imsi[12]={8,0x09,0x10,0x10,0x10,0x32,0x54,0x76,0x98,0,0,0};

static int publish_ready(void)
{
    uint8_t *body;
    unsigned i;
    if(SIM_STATE==8) return 1;
    body=ALLOCATE(8);
    if(!body) return 0;
    for(i=0;i<8;i++)body[i]=0;
    body[1]=0xef; body[2]=0x0d; body[3]=0x0b; body[4]=8; body[5]=1;
    SET_LENGTH(body,8);
    // The selected virtual profile owns state; native gate now uses its
    // serving table, whose audited getters below point back to this backend.
    SIM_STATE=8;
    trace('I',0x080b0def);
    BROADCAST(0x800ca784,body);
    return 1;
}

uint32_t virtual_sim_request(uint32_t object,uint32_t opaque,
                             uint32_t envelope,uint8_t *request)
{
    uint8_t *reply;
    unsigned length=4,i;
    uint8_t state=SIM_STATE;
    if (state!=5 && state!=6 && state!=8)
        return ORIGINAL(object,opaque,envelope,request);
    if(!publish_ready())
        return ORIGINAL(object,opaque,envelope,request);
    reply=ALLOCATE(16);
    if (!reply)
        return ORIGINAL(object,opaque,envelope,request);
    for(i=0;i<16;i++)reply[i]=0;
    reply[0]=request[0];
    reply[1]=(uint8_t)RESPONSE_ID(request[1]);
    reply[2]=request[2];
    reply[3]=0xfa; // Serving virtual SIM, unsupported request, not no-card.
    if(request[1]==0x60 && request[2]==0xfa) reply[3]=0x31;
    else if((request[1]==0x21 && request[2]==0x2c) ||
            (request[1]==0x33 && request[2]==0x3e) ||
            (request[1]==0x13 && request[2]==0x11) ||
            (request[1]==0x31 && request[2]==0x3b)) reply[3]=0x24;
    else if(request[1]==0x3b && request[2]==0xfa) reply[3]=0x2a;
    else if(request[1]==0x2d && request[2]==0x3a) {
        reply[3]=1; length=6;
    } else if(request[1]==0x2b && request[2]==0x3a) {
        reply[3]=1; reply[4]=1; length=8;
    } else if(request[1]==0x19 && request[2]==0x2f) {
        // Native Network method3360 returns three PLMN bytes plus filler.
        reply[3]=1; reply[4]=0x00; reply[5]=0xf1; reply[6]=0x10; length=8;
    } else if(request[1]==0x1d && request[2]==0x2d) {
        reply[3]=1; length=16;
        for(i=0;i<12;i++)reply[4+i]=imsi[i];
    }
    trace('R',((uint32_t)state<<24)|((uint32_t)reply[3]<<16)|
              ((uint32_t)request[2]<<8)|request[1]);
    // Match native ownership: free request exactly once, then native send.
    RELEASE(request);
    SEND(object,envelope,reply,length);
    return 0;
}

uint32_t virtual_sim_broadcast(uint32_t server,uint8_t *body)
{
    // Both native eight-byte SIM_IND builders call this exact two-arg API.
    // Leave initialization/removal events outside the selected absent states.
    if(server==0x800ca784 && body[1]==0xef && (body[4]==5 || body[4]==6)) {
        trace('I',((uint32_t)body[4]<<24)|((uint32_t)body[3]<<16)|
                  ((uint32_t)body[2]<<8)|body[1]);
        SIM_STATE=8;
        body[2]=0x0d; // SIM_ST_INFO
        body[3]=0x0b; // SIM_SERV_INIT_OK
        body[4]=8;    // Published logical SIM ready, no PIN.
        body[5]=1;
        body[6]=0;
        body[7]=0;
    }
    return BROADCAST(server,body);
}

// Observe original self-test packets; do not turn failures into successes.
typedef uint32_t (*dispatch5_fn)(uint32_t,uint32_t,uint32_t,uint32_t,uint8_t *);
typedef uint32_t (*get_length_fn)(uint8_t *);
uint32_t virtual_selftest_trace(uint32_t envelope,uint32_t method,
                               uint32_t server,uint32_t resource,uint8_t *body)
{
#ifdef VSIM_TRACE
    unsigned length,i,j;
    uint32_t word;
    if(resource==0x35 && body) {
        length=((get_length_fn)0x514b9b49)(body);
        trace('T',(length<<16)|resource);
        for(i=0;i<length && i<64;i+=4) {
            word=0;
            for(j=0;j<4 && i+j<length;j++)word|=(uint32_t)body[i+j]<<(8*j);
            trace('t',word);
        }
        // Original St_func initializer5164AAF0 owns this24byte result array.
        // Read current CPU-visible results, including the asynchronously run
        // group; no host-side dirty-cache assumption and no result mutation.
        for(i=0;i<24;i+=4) {
            volatile uint8_t *results=(volatile uint8_t *)0x80024388;
            word=0;
            for(j=0;j<4;j++)word|=(uint32_t)results[i+j]<<(8*j);
            trace('S',word);
        }
    }
#endif
    return ((dispatch5_fn)0x514bddf9)(envelope,method,server,resource,body);
}
