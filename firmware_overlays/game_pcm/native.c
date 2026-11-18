/* NEM-4 4.03. The installer checks the exact service image before linking
 * this to the original DoControl(4) router thunk. */
#include <stddef.h>
#include "stream.h"

#define PCM_MMIO ((volatile uint32_t *)0x581f0000u)
#define PCM_CONTEXT  (0x30 / 4)
#define NOS_CHANNELS ((void *const volatile *)0x8000c724u)
#define NOS_DEVICE   (*(volatile uint8_t *)0x800c828cu)
#define TIMER5_STATUS (*(volatile uint32_t *)0x58120aa8u)
#define IRQ_DISABLE   (*(volatile uint32_t *)0x5812010cu)
#define FIQ_ENABLE    (*(volatile uint32_t *)0x581201c8u)
#define TIMER5_MASK   (1u << 5)

#define NOS_ROUTE    ((unsigned (*)(const uint8_t *))0x514bce39u)
#define NOS_ALLOC    ((void *(*)(unsigned, const char *, unsigned))0x516c750du)
#define NOS_FREE     ((void (*)(void *, const char *, unsigned))0x516c7505u)
#define NOS_WAKE     ((void (*)(void))0x514a1880u)

typedef void (*nos_callback)(void *, unsigned, unsigned, unsigned);
#define NOS_POST     ((void (*)(nos_callback, void *, unsigned, unsigned, unsigned))0x514a2724u)

#define IRQ_NEW      ((void (*)(void *))0x50331be0u)
#define IRQ_BIND     ((int (*)(void *, const uint32_t *))0x50331c2cu)
#define IRQ_ENABLE   ((void (*)(void *))0x50331bf8u)
#define DFC_ADD      ((void (*)(void *))0x503451f4u)

struct native_pcm {
    uint32_t irq[5];
    uint32_t dfc[4];
    struct pcm_stream stream;
    volatile uint32_t events;
    void *channel;
    unsigned unit;
    unsigned queued;
    volatile unsigned irq_suppressed;
};

static const char owner[] = "GamePcm";

static unsigned lock_irqs(void)
{
    unsigned old, masked;
    __asm__ volatile("mrs %0, cpsr\n"
                     "orr %1, %0, #0x80\n"
                     "msr cpsr_c, %1"
                     : "=&r"(old), "=&r"(masked) :: "memory");
    return old;
}

static void unlock_irqs(unsigned old)
{
    __asm__ volatile("msr cpsr_c, %0" :: "r"(old) : "memory");
}

static void reply(void *client, const uint8_t *source)
{
    struct native_pcm *pcm = client;
    if (NOS_CHANNELS[pcm->unit] != pcm->channel)
        return;

    uint8_t frame[PCM_FRAME_BYTES] __attribute__((aligned(4)));
    for (unsigned i = 0; i < sizeof(frame); ++i)
        frame[i] = source[i];
    frame[0] |= 0x80; /* Sender already describes the off-device DSP. */
    frame[1] = (NOS_DEVICE & 0xfc) | (frame[1] & 3);
    frame[2] = 0x7c;
    frame[4] = sizeof(frame) - 6;
    frame[7] = 1;
    NOS_ROUTE(frame); /* The router takes a stock pool copy of this frame. */
}

static void complete_in_nos(void *context, unsigned unused1,
                            unsigned unused2, unsigned unused3)
{
    (void)unused1;
    (void)unused2;
    (void)unused3;
    struct native_pcm *pcm = context;
    unsigned old = lock_irqs();
    unsigned done = pcm->events;
    pcm->events = 0;
    pcm->queued = 0;
    unlock_irqs(old);

    if (NOS_CHANNELS[pcm->unit] != pcm->channel) {
        PCM_MMIO[PCM_CONTROL] = 0;
        PCM_MMIO[PCM_STATUS] = PCM_DONE;
        pcm->stream.open = 0;
        return;
    }
    pcm_completed(&pcm->stream, done);
}

static void defer_to_nos(void *context)
{
    struct native_pcm *pcm = context;
    if (!pcm->queued) {
        pcm->queued = 1;
        NOS_POST(complete_in_nos, pcm, 0, 0, 0);
        NOS_WAKE();
    }
}

static void pcm_irq(void *object)
{
    struct native_pcm *pcm = object; /* irq is the first member. */
    /* The fitted line also sees the legacy timer's pending latch. Keep
     * its pollable status and acknowledge only while FIQ 5 is masked. */
    if (FIQ_ENABLE & TIMER5_MASK) {
        IRQ_DISABLE = TIMER5_MASK;
        pcm->irq_suppressed = 1;
        return;
    }
    TIMER5_STATUS = TIMER5_STATUS;

    unsigned done = PCM_MMIO[PCM_STATUS] & PCM_DONE;
    PCM_MMIO[PCM_STATUS] = done;
    if (done) {
        pcm->events |= done;
        DFC_ADD(pcm->dfc);
    }
}

static void (*const irq_vtable[3])(void *) = { 0, 0, pcm_irq };

static struct native_pcm *bind_pcm(void)
{
    struct native_pcm *pcm = NOS_ALLOC(sizeof(*pcm), owner, 1);
    if (!pcm)
        return NULL;
    for (unsigned i = 0; i < sizeof(*pcm); ++i)
        ((uint8_t *)pcm)[i] = 0;

    pcm->stream.registers = PCM_MMIO;
    pcm->stream.client = pcm;
    pcm->stream.reply = reply;
    pcm->dfc[2] = (uintptr_t)defer_to_nos;
    pcm->dfc[3] = (uintptr_t)pcm;
    IRQ_NEW(pcm->irq);
    pcm->irq[4] = (uintptr_t)irq_vtable;

    const uint32_t name[] = { 0x10000009, (uintptr_t)"IrqTimer5" };
    if (IRQ_BIND(pcm->irq, name)) {
        NOS_FREE(pcm, owner, 2);
        return NULL;
    }
    PCM_MMIO[PCM_CONTEXT] = (uintptr_t)pcm;
    IRQ_ENABLE(pcm->irq);
    return pcm;
}

static unsigned reply_idle_stop(const uint8_t *frame, unsigned unit, void *channel)
{
    struct native_pcm idle;
    idle.channel = channel;
    idle.unit = unit;
    idle.stream.registers = PCM_MMIO;
    idle.stream.reply = reply;
    idle.stream.client = &idle;
    idle.stream.open = 0;
    pcm_request(&idle.stream, frame, 10);
    return 0;
}

/* Entry for the original ARM DoControl(4) router thunk. It passes the stock
 * receive unit in r2 and retains ownership of the outgoing descriptor. */
unsigned native_pcm_route(const uint8_t *frame, unsigned unused, unsigned unit)
{
    (void)unused;
    if (frame[3] != PCM_RESOURCE || unit >= 26)
        return NOS_ROUTE(frame);
    unsigned bytes = 6 + frame[4] + ((unsigned)frame[5] << 8);
    if (bytes < 10 || PCM_MMIO[PCM_ID] != 0x41554431u)
        return NOS_ROUTE(frame);

    void *channel = NOS_CHANNELS[unit];
    if (!channel)
        return NOS_ROUTE(frame);
    struct native_pcm *pcm = (void *)(uintptr_t)PCM_MMIO[PCM_CONTEXT];

    if (frame[9] == 0x2a && bytes == 10 && (!pcm || !pcm->stream.open))
        return reply_idle_stop(frame, unit, channel);

    if (pcm_accepts_start(frame, bytes)) {
        if (FIQ_ENABLE & TIMER5_MASK)
            return NOS_ROUTE(frame);
        if (pcm && pcm->stream.open && pcm->channel != channel &&
            NOS_CHANNELS[pcm->unit] == pcm->channel)
            return NOS_ROUTE(frame);
        if (!pcm)
            pcm = bind_pcm();
        if (!pcm)
            return NOS_ROUTE(frame);
        pcm->unit = unit;
        pcm->channel = channel;
    } else if (!pcm || pcm->unit != unit || pcm->channel != channel) {
        return NOS_ROUTE(frame);
    }

    if (!pcm_request(&pcm->stream, frame, bytes))
        return NOS_ROUTE(frame);
    if (frame[9] == 0x20 || frame[9] == 0x2a) {
        unsigned old = lock_irqs();
        pcm->events = 0;
        unlock_irqs(old);
    }
    if (frame[9] == 0x20 && pcm->irq_suppressed) {
        pcm->irq_suppressed = 0;
        IRQ_ENABLE(pcm->irq);
    }
    return 0;
}
