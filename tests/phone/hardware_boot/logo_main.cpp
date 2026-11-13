#include "Vtb.h"
#ifdef NGAGE_REFILL_STATS
#include "Vtb___024root.h"
#include <vector>
#endif
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
    uint64_t stop_lcd_words=0, lcd_limit_tick=0, panic_ticks=0;
    const char *panic_arg=context.commandArgsPlusMatch("stop-kernel-panic");
    const bool stop_panic=panic_arg && *panic_arg;
    auto number_arg=[&](const char *name,uint64_t fallback) {
        const char *value=context.commandArgsPlusMatch(name);
        return value && *value ? std::stoull(std::string(value).substr(std::string(value).find('=')+1)) : fallback;
    };
    const uint64_t checkpoint_before=number_arg("checkpoint-before=",1000000000ULL);
    const uint64_t checkpoint_after=number_arg("checkpoint-after=",100000000ULL);
    const uint64_t checkpoint_switch=number_arg("checkpoint-switch=",10000000000ULL);
    if(!checkpoint_before || !checkpoint_after)throw std::runtime_error("checkpoint intervals must be positive");
    const char *key_arg=context.commandArgsPlusMatch("key-command=");
    const std::string key_file=key_arg && *key_arg ? std::string(key_arg).substr(std::string(key_arg).find('=')+1) : "";
    const char *limit=context.commandArgsPlusMatch("stop-lcd-words=");
    if(limit && *limit)stop_lcd_words=std::stoull(std::string(limit).substr(std::string(limit).find('=')+1));
    Vtb model{&context};Host host;
    model.clk=0;model.cold=1;model.reset=1;model.frame_index=0;
    model.key_command_id=0;model.key_command_mask=0;model.key_command_hold=0;model.eval();
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
#ifdef NGAGE_REFILL_STATS
    #define Z(x) tb__DOT__dut__DOT__board__DOT__upp__DOT__cpu_inside__DOT__cpu__DOT__u_zap__DOT__##x
    #define IC(x) Z(l_generate_with_cache_mmu__DOT__u_code_cache__DOT__##x)
    #define DC(x) Z(l_generate_with_cache_mmu__DOT__u_data_cache__DOT__##x)
    uint64_t stat_clocks=0,stat_code=0,stat_data=0,stat_ic_clocks=0,stat_dc_clocks=0;
    uint64_t stat_ic_starts=0,stat_dc_starts=0,stat_ddr_reads=0,stat_ddr_beats=0,stat_trace=0;
    unsigned prev_ic=0,prev_dc=0,prev_ddelay=model.rootp->tb__DOT__ddelay;
    std::vector<uint8_t> original_c(4194304);
    for(unsigned j=0;j<original_c.size();j++)original_c[j]=model.rootp->tb__DOT__ddr[0x1400000+j];
#endif
    while(total()<target && !stop_requested && !context.gotFinish()) {
        if(host.phase==0 && host.ticks>=4){model.cold=0;host.phase=1;}
        if(host.phase==1 && model.ready){host.phase=2;host.settle=2;}
        if(host.phase==2 && host.settle--==0){model.reset=0;host.phase=3;boot_offset=host.ticks;}
        // The command file is atomically replaced by send_sim_key.py. Only the
        // simulation host checks it; latched key levels, duration and request ID
        // are HDL state, so a checkpoint taken during a hold resumes faithfully.
        if(host.phase==3 && (total()&65535)==0 && !key_file.empty()) {
            std::ifstream request(key_file);uint64_t id=0,hold=0;uint32_t mask=0;
            if(request>>id>>std::hex>>mask>>std::dec>>hold) {
                if(id>model.key_applied_id && mask<(1U<<27)) {
                    model.key_command_id=id;model.key_command_mask=mask;model.key_command_hold=hold;
                    std::printf("KEY_REQUEST cycle=%llu id=%llu mask=%07x hold=%llu\n",
                        (unsigned long long)total(),(unsigned long long)id,mask,(unsigned long long)hold);
                    std::fflush(stdout);
                }
            }
        }
#ifdef NGAGE_REFILL_STATS
        auto *r=model.rootp;
        unsigned ic=r->IC(cache_adapter__DOT__cache__DOT__state),dc=r->DC(cache_adapter__DOT__cache__DOT__state);
        stat_clocks++;stat_code+=r->Z(u_zap_core__DOT__code_stall);stat_data+=r->Z(u_zap_core__DOT__data_stall);
        stat_ic_clocks+=ic==5;stat_dc_clocks+=dc==5;
        stat_ic_starts+=ic==5 && prev_ic!=5;stat_dc_starts+=dc==5 && prev_dc!=5;prev_ic=ic;prev_dc=dc;
        stat_ddr_reads+=prev_ddelay==0 && r->tb__DOT__ddelay==3;prev_ddelay=r->tb__DOT__ddelay;
        stat_ddr_beats+=r->tb__DOT__phyready;stat_trace+=r->Z(o_trace_valid);
#endif
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
        const uint64_t interval=total()<=checkpoint_switch ? checkpoint_before : checkpoint_after;
        if(total() && total()%interval==0)save();
        if(stop_panic) {
            // NEM-4's terminal panic branch and speculative fetch lookahead.
            if(model.pc>=0x50324294 && model.pc<0x503242a4)panic_ticks++;
            else if(model.pc!=0)panic_ticks=0; // zero is an idle fetch, not an escape
            if(panic_ticks>=1000)break;
        }
        if(stop_lcd_words && model.pixel_writes>=stop_lcd_words) {
            if(!lcd_limit_tick)lcd_limit_tick=total();
            if(total()-lcd_limit_tick>=1000)break; // let queued LCD writes commit
        }
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
    result<<"{\"boot_index\":"<<model.boot_index<<",\"boot_limit\":"<<model.boot_limit<<",\"retired\":"<<model.retired_count<<",\"ddr_commands\":"<<model.ddr_command_count<<",\"ddr_beats\":"<<model.ddr_beat_count<<",\"cycle\":"<<total()<<",\"pc\":"<<model.pc<<",\"lcd_words\":"<<model.pixel_writes<<",\"frame_complete\":"<<unsigned(model.frame_complete)<<",\"display_on\":"<<unsigned(model.display_on)<<",\"unsupported\":"<<unsigned(model.unsupported)<<",\"bus_errors\":"<<model.bus_errors<<",\"data_errors\":"<<model.data_faults<<",\"seconds\":"<<seconds<<",\"stop_after_lcd_words\":"<<stop_lcd_words<<",\"stopped_on_kernel_panic\":"<<(panic_ticks>=1000?"true":"false")<<",\"stopped_at_lcd_limit\":"<<(lcd_limit_tick?"true":"false")<<",\"interrupted\":"<<(stop_requested?"true":"false")<<"}\n";
#ifdef NGAGE_REFILL_STATS
    unsigned changed_c=0;for(unsigned j=0;j<original_c.size();j++)changed_c+=original_c[j]!=model.rootp->tb__DOT__ddr[0x1400000+j];
    std::ofstream stats(out+"/refill-stats.json");
    stats<<"{\"clocks\":"<<stat_clocks<<",\"code_stall\":"<<stat_code<<",\"data_stall\":"<<stat_data
         <<",\"ic_refill_clocks\":"<<stat_ic_clocks<<",\"ic_refill_starts\":"<<stat_ic_starts
         <<",\"dc_refill_clocks\":"<<stat_dc_clocks<<",\"dc_refill_starts\":"<<stat_dc_starts
         <<",\"ddr_read_commands\":"<<stat_ddr_reads<<",\"ddr_return_beats\":"<<stat_ddr_beats
         <<",\"trace_uop_observations\":"<<stat_trace<<",\"c_changed_positions_in_segment\":"<<changed_c<<"}\n";
#endif
    model.final();return 0;
 }catch(const std::exception &e){std::fprintf(stderr,"ERROR %s\n",e.what());return 1;}
}
