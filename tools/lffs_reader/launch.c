/* Read-only file API probe: exact guest EFile/EFSrv implements LFFS. */
#include "kobj.h"
struct ptrc { u32 len, ptr; };
static u32 fs[4];
static u32 f_connect, f_diropen, f_dirread, f_open, f_size, f_read;
static int started, entries;
#ifndef NGFS_ALL_FILES
#define NGFS_ALL_FILES 0
#endif
u64 launch_due = ~0ull;
static void bytehex(u8 x) { const char *h="0123456789abcdef"; IO(IO_DBG_PUTC)=h[x>>4]; IO(IO_DBG_PUTC)=h[x&15]; }
static void pathhex(const u16 *p) { for(;*p;p++){bytehex(*p);bytehex(*p>>8);} }
static void des(struct ptrc *d,const u16 *p) {int n=0;while(p[n])n++;d->len=0x10000000u|n;d->ptr=(u32)p;}
static u32 exp(const struct rom_image *im,int n) {return im && n<=im->export_count?uread32(im->export_dir+4*(n-1)):0;}
void launch_init(void) {
 const struct rom_image *im=rom_image("\\System\\Libs\\EFSrv.dll");
 f_connect=exp(im,18);f_diropen=exp(im,120);f_dirread=exp(im,134);
 f_open=exp(im,121);f_size=exp(im,185);f_read=exp(im,140);
 launch_due=0;
}
static int wanted(const u16 *p) {
 char s[520];int n=0;for(;*p&&n<519;p++){int c=*p;s[n++]=c>='A'&&c<='Z'?c+32:c;}s[n]=0;
 if(n>=4&&(!memcmp(s+n-4,".txt",4)||!memcmp(s+n-4,".log",4)))return 1;
 for(int i=0;i+6<n;i++)if(!memcmp(s+i,"\\logs\\",6))return 1;
 return 0;
}
static void dumpfile(const u16 *path) {
 if(!NGFS_ALL_FILES&&!wanted(path))return;
 struct ptrc d;des(&d,path);u32 f[8]={0};s32 r=((s32(*)(u32*,u32*,struct ptrc*,u32))f_open)(f,fs,&d,0x200);
 kprintf("NGFS_OPEN %d ",r);pathhex(path);kprintf("\n");if(r)return;
 s32 size=0;r=((s32(*)(u32*,s32*))f_size)(f,&size);
 if(r||size<0||size>0x400000){kprintf("NGFS_ERROR size %d %d\n",r,size);return;}
 int id=entries; kprintf("NGFS_FILE %d %d ",id,size);pathhex(path);kprintf("\n");
 u8 data[256]; struct {u32 len,max,ptr;} b={0x20000000u,256,(u32)data};
 for(int at=0;at<size;) {
  b.len=0x20000000u;b.max=size-at<256?size-at:256;
  r=((s32(*)(u32*,int,void*))f_read)(f,at,&b);
  int n=b.len&0x0fffffff;
  if(r||n<=0||n>(int)b.max){kprintf("NGFS_ERROR read %d %d\n",r,n);return;}
  kprintf("NGFS_DATA %d %d ",id,at);for(int i=0;i<n;i++)bytehex(data[i]);kprintf("\n");at+=n;
 }
 kprintf("NGFS_END %d\n",id);
}
static void walk(const u16 *path,int depth) {
 if(depth>16||entries>2048){kprintf("NGFS_ERROR limit\n");return;}
 u16 query[520];int plen=0;while(path[plen]&&plen<515){query[plen]=path[plen];plen++;}query[plen]='*';query[plen+1]=0;
 struct ptrc d;des(&d,query);u32 dir[8]={0};
 s32 r=((s32(*)(u32*,u32*,struct ptrc*,u32))f_diropen)(dir,fs,&d,0x10|0x02|0x04);
 if(r){kprintf("NGFS_DIRERR %d ",r);pathhex(path);kprintf("\n");return;}
 for(int z=0;z<2048;z++) {
  u32 entry[160]={0};r=((s32(*)(u32*,void*))f_dirread)(dir,entry);
  if(r==-25)break;
  if(r){kprintf("NGFS_ERROR dirread %d\n",r);break;}
  int n=entry[7]&0xfffffff;u16 *name=(u16*)&entry[8];
  if(n<1||n>256||plen+n+2>=520){kprintf("NGFS_ERROR entry layout %x\n",entry[7]);return;}
  u16 full[520];memcpy(full,path,plen*2);for(int i=0;i<n;i++)full[plen+i]=name[i];full[plen+n]=0;
  entries++;kprintf("NGFS_ENTRY %x %d ",entry[0],entry[1]);pathhex(full);kprintf("\n");
  if(entry[0]&16){full[plen+n]='\\';full[plen+n+1]=0;walk(full,depth+1);}else dumpfile(full);
 }
}
static s32 reader(u32 unused) {
 s32 r=((s32(*)(u32*,int))f_connect)(fs,16);kprintf("NGFS_CONNECT %d\n",r);
 if(!r)walk(u"C:\\",0);
 kprintf("NGFS_DONE %d\n",entries);IO(IO_DBG_EXIT)=r?2:0;
 return 0;
}
void launch_poll(void) {
 if(started)return;
 launch_due=now_us()+10000;
 if(!server_find(u"FileServer",10))return;
 started=1;launch_due=~0ull;
 struct process *p=proc_new(u"FSReader",8);p->exit_type=3;p->prio=400;
 struct thread *t=thread_create(p,(u32)reader,0,0x10000,0,0x1000,0x10000,1);
 obj_set_name_a(&t->o,"Reader");thread_reprioritise(t);thread_resume(t);
}
