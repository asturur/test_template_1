#include "stream.h"

/* audio.ldd maps these fifteen contiguous SDRAM pages at VA 0x5a000000. */
#define SHARED_START 0x0a061000u
#define SHARED_END   0x0a070000u

static unsigned be16(const uint8_t *field)
{
    return ((unsigned)field[0] << 8) | field[1];
}

static uint32_t be32(const uint8_t *field)
{
    return ((uint32_t)be16(field) << 16) | be16(field + 2);
}

int pcm_accepts_start(const uint8_t *frame, unsigned bytes)
{
    if (bytes < 24 || frame[3] != PCM_RESOURCE || frame[9] != 0x20 ||
        frame[10] != 0x82 || frame[11] != 2 || frame[22] != 0 ||
        (frame[23] != 0x32 && frame[23] != 0x46))
        return 0;

    unsigned length = 2 * be16(frame + 12);
    uint32_t a = be32(frame + 14);
    uint32_t b = be32(frame + 18);
    return length && !(a & 1) && !(b & 1) &&
           a >= SHARED_START && a <= SHARED_END &&
           b >= SHARED_START && b <= SHARED_END &&
           length <= SHARED_END - a && length <= SHARED_END - b &&
           (a + length <= b || b + length <= a);
}

static void send(struct pcm_stream *stream, uint8_t transaction,
                 uint8_t id, unsigned value)
{
    uint8_t frame[PCM_FRAME_BYTES] = {
        stream->media, stream->destination, 0, PCM_RESOURCE, 0, 0,
        stream->object, 0, transaction, id,
        (uint8_t)(value >> 8), (uint8_t)value, 0, 0
    };
    stream->reply(stream->client, frame);
}

static void stop(struct pcm_stream *stream)
{
    volatile uint32_t *reg = stream->registers;
    reg[PCM_CONTROL] = 0;
    reg[PCM_STATUS] = PCM_DONE;
    stream->open = 0;
    stream->first = 1;
    stream->last = PCM_NO_HALF;
    stream->requested = PCM_NO_HALF;
    stream->free_halves = 0;
}

static void request_half(struct pcm_stream *stream)
{
    if (stream->last == PCM_NO_HALF && stream->requested == PCM_NO_HALF &&
        stream->free_halves) {
        unsigned half = stream->free_halves & 1 ? 0 : 1;
        stream->requested = half;
        stream->free_halves &= ~(1u << half);
        send(stream, 0, 0x26, half);
    }
}

int pcm_request(struct pcm_stream *stream, const uint8_t *frame,
                unsigned bytes)
{
    if (bytes < 10 || frame[3] != PCM_RESOURCE)
        return 0;

    volatile uint32_t *reg = stream->registers;
    unsigned id = frame[9];
    if (id == 0x20) {
        if (!pcm_accepts_start(frame, bytes))
            return 0;
        stop(stream);
        stream->media = frame[0];
        stream->destination = frame[2];
        stream->object = frame[7];
        stream->capacity = be16(frame + 12);
        reg[PCM_FORMAT] = 0;
        reg[PCM_RATE] = frame[23] == 0x32 ? 8000 : 16000;
        reg[PCM_ADDRESS0] = be32(frame + 14);
        reg[PCM_ADDRESS1] = be32(frame + 18);
        stream->open = 1;
        send(stream, frame[8], 0x21, 0);
        return 1;
    }

    if (!stream->open || stream->object != frame[7] ||
        ((stream->destination ^ frame[2]) & 3))
        return 0;

    if (id == 0x2a) {
        unsigned bytes_played = reg[PCM_CONTROL] & PCM_RUN
                              ? reg[PCM_POSITION] * 2 : 0;
        stop(stream);
        send(stream, frame[8], 0x2b, bytes_played);
        return 1;
    }

    if ((id != 0x23 && id != 0x27) || bytes < 14)
        return 0;

    unsigned half = id == 0x23 ? frame[10] : stream->requested;
    unsigned frames = be16(frame + 12);
    if (half >= PCM_NO_HALF || frames > stream->capacity ||
        (frame[11] != 1 && frame[11] != 2))
        return 0;

    if (reg[PCM_STATUS] & (1u << (PCM_FULL_SHIFT + half)))
        return 0;
    if (half == stream->requested)
        stream->requested = PCM_NO_HALF;
    stream->free_halves &= ~(1u << half);
    if (frame[11] == 1) {
        stream->last = half;
        stream->last_frames = frames;
    }
    reg[PCM_FRAMES0 + half] = frames;
    if (!(reg[PCM_CONTROL] & PCM_RUN))
        reg[PCM_CONTROL] = PCM_RUN | PCM_INTERRUPT;
    send(stream, frame[8], id + 1, 0);

    if (stream->first) {
        stream->first = 0;
        stream->free_halves |= 1u << (half ^ 1);
    }
    request_half(stream);
    if (!frames)
        pcm_completed(stream, 0);
    return 1;
}

void pcm_completed(struct pcm_stream *stream, unsigned done)
{
    if (!stream->open)
        return;

    unsigned full = (stream->registers[PCM_STATUS] >> PCM_FULL_SHIFT) & 3;
    if (stream->last != PCM_NO_HALF) {
        if (done & (1u << stream->last) || (!stream->last_frames && !full)) {
            unsigned bytes_played = stream->last_frames * 2;
            stop(stream);
            send(stream, 0, 0x2b, bytes_played);
        }
        return;
    }
    stream->free_halves |= done & ~full;
    request_half(stream);
}
