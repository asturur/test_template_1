/* NGVM adapter. Original SoundDevice and MediaServer still send every frame.
 * The FIFO models sample timing at this boundary instead of the PCM RTL. */
static uint32_t pcm_registers[PCM_PLAYED + 1];
static struct channel *pcm_channel;
static u8 pcm_source_device, pcm_source_object;
static unsigned active_half;
static unsigned audible;

static void bridge_reply(void *client, const uint8_t *frame)
{
    (void)client;
    u8 copy[ISI_LEN];
    memcpy(copy, frame, ISI_LEN);
    copy[2] = pcm_source_device;
    copy[5] = ISI_LEN - 6;
    copy[7] = pcm_source_object;
    if (copy[9] == 0x21 || copy[9] == 0x2b)
        kprintf("[bridge] reply %02x bytes %d\n", copy[9],
                copy[10] << 8 | copy[11]);
    isi_post(pcm_channel, copy);
}

static struct pcm_stream bridge = {
    .registers = pcm_registers,
    .reply = bridge_reply,
};

static unsigned pcm_full(unsigned half)
{
    return 1u << (PCM_FULL_SHIFT + half);
}

static void bridge_send(struct channel *channel, const u8 *frame, int bytes)
{
    unsigned id = frame[9];
    if (pcm_accepts_start(frame, bytes)) {
        pcm_channel = channel;
        pcm_source_device = frame[1];
        pcm_source_object = frame[6];
        pcm_registers[PCM_STATUS] = 0;
        pcm_registers[PCM_POSITION] = 0;
        active_half = 0;
        audible = 0;
    }
    if (channel != pcm_channel)
        return;
    unsigned half = id == 0x23 ? frame[10] : bridge.requested;
    if (!pcm_request(&bridge, frame, bytes))
        kprintf("[bridge] unhandled %02x\n", id);
    if (id == 0x20)
        IO(IO_AUDIO_RATE) = pcm_registers[PCM_RATE];
    if ((id == 0x23 || id == 0x27) && half < PCM_NO_HALF &&
        pcm_registers[PCM_FRAMES0 + half]) {
        pcm_registers[PCM_STATUS] |= pcm_full(half);
        IO(IO_IRQ_ENABLE) |= IRQ_AUDIO;
    }
}

void dsp_pump(void)
{
    int room = (int)IO(IO_AUDIO_SIZE) - (int)IO(IO_AUDIO_LEVEL);
    while ((pcm_registers[PCM_CONTROL] & PCM_RUN) && room > 0) {
        unsigned half = active_half;
        if (!(pcm_registers[PCM_STATUS] & pcm_full(half)))
            half ^= 1;
        if (!(pcm_registers[PCM_STATUS] & pcm_full(half)))
            break;

        const u16 *samples = (const u16 *)(audio_shm
                           + pcm_registers[PCM_ADDRESS0 + half] - 0x0a061000);
        unsigned pos = pcm_registers[PCM_POSITION];
        u32 sample = samples[pos];
        if (sample && !audible) {
            audible = 1;
            kprintf("[bridge] first nonzero sample\n");
        }
        IO(IO_AUDIO_DATA) = sample | sample << 16;
        --room;
        if (++pos == pcm_registers[PCM_FRAMES0 + half]) {
            pcm_registers[PCM_POSITION] = 0;
            pcm_registers[PCM_FRAMES0 + half] = 0;
            pcm_registers[PCM_STATUS] &= ~pcm_full(half);
            active_half = half ^ 1;
            pcm_completed(&bridge, 1u << half);
        } else {
            pcm_registers[PCM_POSITION] = pos;
            active_half = half;
        }
    }
    if (!(pcm_registers[PCM_CONTROL] & PCM_RUN) ||
        !(pcm_registers[PCM_STATUS] & (pcm_full(0) | pcm_full(1))))
        IO(IO_IRQ_ENABLE) &= ~IRQ_AUDIO;
}
