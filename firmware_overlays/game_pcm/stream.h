#ifndef NGAGE_GAME_PCM_STREAM_H
#define NGAGE_GAME_PCM_STREAM_H

#include <stdint.h>

enum pcm_register {
    PCM_ID, PCM_CONTROL, PCM_FORMAT, PCM_RATE, PCM_ADDRESS0, PCM_ADDRESS1,
    PCM_FRAMES0, PCM_FRAMES1, PCM_STATUS, PCM_POSITION, PCM_GAIN, PCM_PLAYED
};

enum { PCM_RUN = 1, PCM_INTERRUPT = 2, PCM_DONE = 3, PCM_FULL_SHIFT = 4 };
enum { PCM_RESOURCE = 0xe8, PCM_FRAME_BYTES = 14, PCM_NO_HALF = 2 };

struct pcm_stream {
    volatile uint32_t *registers;
    void (*reply)(void *client, const uint8_t *frame);
    void *client;
    uint8_t media, destination, object;
    uint8_t open, requested, last, first, free_halves;
    uint16_t capacity, last_frames;
};

/* Preflight before binding an interrupt or claiming a NOS stream. */
int pcm_accepts_start(const uint8_t *frame, unsigned bytes);

/* Returns 1 for requests handled here. Header length byte order and the DSP
 * source address are filled in by the transport. */
int pcm_request(struct pcm_stream *stream, const uint8_t *frame,
                unsigned bytes);
void pcm_completed(struct pcm_stream *stream, unsigned done);

#endif
