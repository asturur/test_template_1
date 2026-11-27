/* Exercise the original EFile/EFSrv disk calls in a private NGVM image. */
#include "kobj.h"
#include "disk_payload.h"

struct descriptor { u32 len, ptr; };
struct writable8 { u32 len, max, ptr; };
static u32 fs[4], files[25][8];
static u32 connect_fs, create_file, open_file, close_file, write_file, read_file, flush_file, delete_file;
static int started;
int disk_probe_phase;
u64 launch_due = ~0ull;

static u32 ordinal(const struct rom_image *im, int n)
{
    return im && n <= im->export_count ? uread32(im->export_dir + 4 * (n-1)) : 0;
}

void launch_init(void)
{
    const struct rom_image *im = rom_image("\\System\\Libs\\EFSrv.dll");
    connect_fs = ordinal(im,18);
    create_file = ordinal(im,25);
    open_file = ordinal(im,121);
    close_file = ordinal(im,15);
    write_file = ordinal(im,194);
    read_file = ordinal(im,136);
    flush_file = ordinal(im,50);
    delete_file = ordinal(im,29);
    launch_due = 0;
}

static void name_for(u16 *out, int file, int absolute)
{
    if (absolute) {
        *out++ = 'C';
        *out++ = ':';
        *out++ = '\\';
    }
    for (const u16 *c = u"TestFile"; *c; c++) *out++ = *c;
    if (file >= 10) *out++ = '0' + file / 10;
    *out++ = '0' + file % 10;
    for (const u16 *c = u".dat"; *c; c++) *out++ = *c;
    *out = 0;
}

static struct descriptor name_desc(const u16 *name)
{
    unsigned n = 0;
    while (name[n]) n++;
    return (struct descriptor){0x10000000u | n, (u32)name};
}

static s32 file_call(u32 func, u32 *file, const u16 *name)
{
    struct descriptor desc = name_desc(name);
    return ((s32(*)(u32*,u32*,void*,u32))func)(file,fs,&desc,0x200);
}

static void require(s32 result, int file)
{
    if (!result) return;
    kprintf("DISK_GUEST_FAIL phase=%d file=%d error=%d\n", disk_probe_phase, file, result);
    IO(IO_DBG_EXIT) = 1;
}

static void report(int round, u32 started_at)
{
    kprintf("DISK_GUEST round=%d phase=%d elapsed_us=%u\n", round, disk_probe_phase,
            (u32)now_us() - started_at);
    disk_probe_phase = 0;
}

static s32 reader(u32 unused)
{
    u16 name[32];
    struct descriptor data = {0x10000000u | sizeof(payload), (u32)payload};
    require(((s32(*)(u32*,int))connect_fs)(fs,4), -1);
    for (int i = 0; i < 25; i++) {
        name_for(name,i,0);
        s32 result = file_call(open_file,files[i],name);
        if (!result) {
            ((void(*)(u32*))close_file)(files[i]);
            struct descriptor desc = name_desc(name);
            require(((s32(*)(u32*,void*))delete_file)(fs,&desc),i);
        } else if (result != -1) require(result,i);
    }
    for (int round = 0; round < 4; round++) {
        u32 begin = (u32)now_us();
        disk_probe_phase = 1;
        for (int i = 0; i < 25; i++) {
            name_for(name,i,0);
            require(file_call(create_file,files[i],name),i);
        }
        report(round,begin);
        begin = (u32)now_us();
        disk_probe_phase = 2;
        for (int i = 0; i < 25; i++) {
            require(((s32(*)(u32*,void*))write_file)(files[i],&data),i);
            require(((s32(*)(u32*))flush_file)(files[i]),i);
            ((void(*)(u32*))close_file)(files[i]);
        }
        report(round,begin);
        // The absolute lookup links the same relative file to C: independently
        // of where the application would be installed.
        name_for(name,0,1);
        require(file_call(open_file,files[0],name),0);
        ((void(*)(u32*))close_file)(files[0]);
        begin = (u32)now_us();
        disk_probe_phase = 3;
        for (int i = 0; i < 25; i++) {
            name_for(name,i,0);
            require(file_call(open_file,files[i],name),i);
        }
        for (int i = 0; i < 25; i++) {
            u8 readback[512];
            struct writable8 buffer = {0x20000000u, sizeof(readback), (u32)readback};
            require(((s32(*)(u32*,void*))read_file)(files[i],&buffer),i);
            require((buffer.len & 0xfffffff) != sizeof(payload) || memcmp(readback,payload,sizeof(payload)),i);
            ((void(*)(u32*))close_file)(files[i]);
        }
        report(round,begin);
        begin = (u32)now_us();
        disk_probe_phase = 4;
        for (int i = 0; i < 25; i++) {
            name_for(name,i,0);
            struct descriptor desc = name_desc(name);
            require(((s32(*)(u32*,void*))delete_file)(fs,&desc),i);
        }
        report(round,begin);
        name_for(name,0,1);
        require(file_call(open_file,files[0],name) != -1,0);
    }
    kprintf("PASS DISK_GUEST absolute=C payload=%d files=100\n", sizeof(payload));
    IO(IO_DBG_EXIT) = 0;
    return 0;
}

void launch_poll(void)
{
    if (started) return;
    launch_due = now_us()+10000;
    if (!server_find(u"FileServer",10)) return;
    started = 1;
    launch_due = ~0ull;
    struct process *p = proc_new(u"DiskProbe",9);
    p->exit_type = 3;
    p->prio = 400;
    struct thread *t = thread_create(p,(u32)reader,0,0x10000,0,0x1000,0x10000,1);
    obj_set_name_a(&t->o,"DiskProbe");
    thread_reprioritise(t);
    thread_resume(t);
}
