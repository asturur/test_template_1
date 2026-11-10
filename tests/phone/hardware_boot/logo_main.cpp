#include "Vtb.h"
#include "verilated.h"
#include "verilated_save.h"
#include <chrono>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <string>
#include <array>
#include <stdexcept>

static volatile std::sig_atomic_t stop_requested=0;
static void stop(int) { stop_requested=1; }
struct Host {
    uint64_t ticks=0;
    uint32_t phase=0,settle=0;
    std::array<uint8_t,320*240*3> scan{};
};
static_assert(sizeof(Host)==230416, "checkpoint host layout");
static void ppm(const std::string &path,int w,int h,const uint8_t *data) {
    std::ofstream f(path,std::ios::binary);f<<"P6\n"<<w<<" "<<h<<"\n255\n";
    f.write(reinterpret_cast<const char*>(data),w*h*3);if(!f)throw std::runtime_error("image write failed");
}
int main(int argc,char **argv) {
 try {
    if(argc<4)throw std::runtime_error("usage: Vtb target-cycle output-dir checkpoint-prefix-or-dash [+image options]");
    uint64_t target=std::stoull(argv[1]);std::string out=argv[2],restore=argv[3];
    VerilatedContext context; context.commandArgs(argc,argv);
    Vtb model{&context};Host host;
    model.clk=0;model.cold=1;model.reset=1;model.frame_index=0;model.eval();
    if(restore!="-") {
        std::ifstream h(restore+".host",std::ios::binary);h.read(reinterpret_cast<char*>(&host),sizeof host);
        if(!h || h.peek()!=EOF)throw std::runtime_error("invalid host checkpoint");
        VerilatedRestore f;f.open(restore+".cpu");f>>model;f.close();
        context.time(host.ticks*10000);
    }
    // ticks is already serialized as 64 bits. Recover the reset offset modulo
    // 2^32 so old checkpoints keep working after the HDL observation counter wraps.
    uint64_t boot_offset=host.phase==3 ? uint32_t(host.ticks-model.cycle_count) : 0;
    auto total=[&]() -> uint64_t {return host.phase==3 ? host.ticks-boot_offset : 0;};
    auto started=std::chrono::steady_clock::now();uint64_t initial=total();
    auto save=[&]() {
        auto base=out+"/checkpoint-"+std::to_string(total());
        if(std::ifstream(base+".cpu").good() || std::ifstream(base+".host").good()) {
            if(!std::ifstream(base+".cpu").good() || !std::ifstream(base+".host").good())throw std::runtime_error("incomplete existing checkpoint pair");
            return; // never overwrite a permanent billion-cycle pair
        }
        {VerilatedSave f;f.open(base+".cpu.partial");f<<model;f.close();}
        {std::ofstream f(base+".host.partial",std::ios::binary);f.write(reinterpret_cast<const char*>(&host),sizeof host);if(!f)throw std::runtime_error("host save failed");}
        if(std::rename((base+".cpu.partial").c_str(),(base+".cpu").c_str()) || std::rename((base+".host.partial").c_str(),(base+".host").c_str()))throw std::runtime_error("checkpoint rename failed");
        std::printf("CHECKPOINT cycle=%llu prefix=%s\n",(unsigned long long)total(),base.c_str());std::fflush(stdout);
    };
    std::signal(SIGTERM,stop);std::signal(SIGINT,stop);
    while(total()<target && !stop_requested && !context.gotFinish()) {
        if(host.phase==0 && host.ticks>=4){model.cold=0;host.phase=1;}
        if(host.phase==1 && model.ready){host.phase=2;host.settle=2;}
        if(host.phase==2 && host.settle--==0){model.reset=0;host.phase=3;boot_offset=host.ticks;}
        model.clk=1;context.timeInc(5000);model.eval();
        if(model.scan_ce && model.scan_de && model.scan_x<320 && model.scan_y<240) {
            auto i=(model.scan_y*320+model.scan_x)*3;auto rgb=model.scan_rgb;
            host.scan[i]=((rgb>>8)&15)*17;host.scan[i+1]=((rgb>>4)&15)*17;host.scan[i+2]=(rgb&15)*17;
        }
        model.clk=0;context.timeInc(5000);model.eval();host.ticks++;
        if(host.phase!=3 && host.ticks>100000)throw std::runtime_error("initialization timeout");
        if(total() && total()%10000000==0) {
            double seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-started).count();
            std::printf("PROGRESS cycles=%llu pc=%08x words=%u errors=%u data_errors=%u seconds=%.2f rate=%.0f\n",(unsigned long long)total(),model.pc,model.pixel_writes,model.bus_errors,model.data_faults,seconds,(total()-initial)/seconds);std::fflush(stdout);
        }
        if(total() && total()%100000000==0)save();
    }
    // Snapshot the actual display RAM; this is observation, not a guest write.
    std::array<uint8_t,176*208*3> pixels{};
    std::ofstream raw(out+"/framebuffer.bin",std::ios::binary);
    for(unsigned i=0;i<18304;i++) {
        model.frame_index=i;model.eval();uint32_t w=model.frame_word;
        raw.write(reinterpret_cast<const char*>(&w),4);
        for(unsigned j=0;j<2;j++){auto rgb=(w>>(16*j))&4095;auto n=(2*i+j)*3;pixels[n]=((rgb>>8)&15)*17;pixels[n+1]=((rgb>>4)&15)*17;pixels[n+2]=(rgb&15)*17;}
    }
    model.frame_index=0;model.eval();save();
    ppm(out+"/framebuffer.ppm",176,208,pixels.data());
    // Keep the saved Host layout stable, but export only the active native
    // phone raster captured through CE + DE, not the diagnostic canvas.
    std::array<uint8_t,176*208*3> active_scan{};
    for(unsigned y=0;y<208;y++)for(unsigned x=0;x<176*3;x++)
        active_scan[y*176*3+x]=host.scan[y*320*3+x];
    ppm(out+"/scanout.ppm",176,208,active_scan.data());
    double seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-started).count();
    std::ofstream result(out+"/result.json");
    result<<"{\"boot_index\":"<<model.boot_index<<",\"boot_limit\":"<<model.boot_limit<<",\"retired\":"<<model.retired_count<<",\"ddr_commands\":"<<model.ddr_command_count<<",\"ddr_beats\":"<<model.ddr_beat_count<<",\"cycle\":"<<total()<<",\"pc\":"<<model.pc<<",\"lcd_words\":"<<model.pixel_writes<<",\"frame_complete\":"<<unsigned(model.frame_complete)<<",\"display_on\":"<<unsigned(model.display_on)<<",\"unsupported\":"<<unsigned(model.unsupported)<<",\"bus_errors\":"<<model.bus_errors<<",\"data_errors\":"<<model.data_faults<<",\"seconds\":"<<seconds<<",\"interrupted\":"<<(stop_requested?"true":"false")<<"}\n";
    model.final();return 0;
 }catch(const std::exception &e){std::fprintf(stderr,"ERROR %s\n",e.what());return 1;}
}
