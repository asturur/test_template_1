/* Original EFSrv and FAT FileServer, with a test-only local-drive sink. */
#include "kobj.h"

#define IO_CARD_MODE 0x0e0
#define SIZE 1739
#define FILE_WRITE 0x200

u64 launch_due = ~0ull;
static int started;
static u32 fs[4], file[8];
static u32 connect_fs, close_fs, create, open_file, write_file, flush, read_file, size_file;
static u8 data[SIZE];
static const u16 name[] = u"E:\\WRITE_TEST\\ROUNDTRP.BIN";

struct desc { u32 length, pointer; };
struct desc_out { u32 length, max, pointer; };

static u32 exp(const struct rom_image *image, int n)
{
    return image && n <= image->export_count ? uread32(image->export_dir + 4*(n-1)) : 0;
}

void launch_init(void)
{
    const struct rom_image *image = rom_image("\\System\\Libs\\EFSrv.dll");
    connect_fs = exp(image, 18);
    close_fs = exp(image, 15);
    create = exp(image, 25);
    open_file = exp(image, 121);
    write_file = exp(image, 198);
    flush = exp(image, 50);
    read_file = exp(image, 140);
    size_file = exp(image, 185);
    launch_due = 0;
}

static u8 byte_at(int i)
{
    return (i*37 + (i >> 3) + 0x69) & 255;
}

static s32 client(u32 unused)
{
    int mode = IO(IO_CARD_MODE);
    struct desc path = {0x10000000u | (sizeof(name)/sizeof(name[0])-1), (u32)name};
    int r = ((s32(*)(u32*, int))connect_fs)(fs, 16);
    kprintf("ROUNDTRIP connect %d\n", r);
    if (r) goto done;

    if (mode == 1) {
        r = ((s32(*)(u32*,u32*,void*,u32))create)(file, fs, &path, FILE_WRITE);
    } else {
        r = ((s32(*)(u32*,u32*,void*,u32))open_file)(file, fs, &path, mode == 2 ? FILE_WRITE : 0);
    }
    kprintf("ROUNDTRIP open %d\n", r);
    if (r) {
        if (mode == 2 && (r == -21 || r == -46)) r = 0;
        goto close;
    }
    if (mode) {
        int n = mode == 1 ? SIZE : 17;
        for (int i = 0; i < n; ++i) data[i] = mode == 1 ? byte_at(i) : byte_at(i)^255;
        struct desc payload = {0x10000000u | n, (u32)data};
        r = ((s32(*)(u32*,int,void*))write_file)(file, 0, &payload);
        kprintf("ROUNDTRIP write %d\n", r);
        if (!r) {
            r = ((s32(*)(u32*))flush)(file);
            kprintf("ROUNDTRIP flush %d\n", r);
        }
        if (mode == 2) r = (r == -21 || r == -46) ? 0 : -2;
    } else {
        int n = 0;
        r = ((s32(*)(u32*,int*))size_file)(file, &n);
        kprintf("ROUNDTRIP size %d %d\n", r, n);
        if (r || n != SIZE) { r = -2; goto close; }
        struct desc_out payload = {0x20000000u, SIZE, (u32)data};
        r = ((s32(*)(u32*,int,void*))read_file)(file, 0, &payload);
        kprintf("ROUNDTRIP read %d %d\n", r, payload.length & 0xfffffff);
        if (!r && (payload.length & 0xfffffff) == SIZE) {
            for (int i = 0; i < SIZE; ++i)
                if (data[i] != byte_at(i)) { r = -2; break; }
        } else r = -2;
    }

close:
    ((void(*)(u32*))close_fs)(fs);
done:
    kprintf("ROUNDTRIP done %d mode %d\n", r, mode);
    IO(IO_DBG_EXIT) = r ? 2 : 0;
    return 0;
}

void launch_poll(void)
{
    if (started) return;
    launch_due = now_us() + 10000;
    /* EStart mounts the card after the FileServer first accepts sessions. */
    if (now_us() < 6000000 || !server_find(u"FileServer", 10)) return;
    started = 1;
    launch_due = ~0ull;
    struct process *p = proc_new(u"MMCWrite", 8);
    p->exit_type = 3;
    p->prio = 400;
    struct thread *t = thread_create(p, (u32)client, 0, 0x10000, 0, 0x1000, 0x10000, 1);
    obj_set_name_a(&t->o, "CardClient");
    thread_reprioritise(t);
    thread_resume(t);
}
