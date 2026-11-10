#include "Vtb.h"
#include "verilated.h"
#include "verilated_save.h"
#include <array>
#include <cstdint>
#include <fstream>
#include <stdexcept>
#include <string>

// Keep the existing serialized Host layout. This reader never advances clocks
// or writes a checkpoint; it links against the checkpoint's frozen HDL archive.
struct Host {
    uint64_t ticks;
    uint32_t phase, settle;
    std::array<uint8_t,320*240*3> scan;
};
static_assert(sizeof(Host)==230416, "checkpoint host layout");
static void ppm(const std::string &path, const uint8_t *pixels) {
    std::ofstream f(path,std::ios::binary);
    f<<"P6\n176 208\n255\n";
    f.write(reinterpret_cast<const char*>(pixels),176*208*3);
    if(!f) throw std::runtime_error("screenshot write failed");
}
int main(int argc,char **argv) {
    if(argc!=3) return 2;
    const std::string checkpoint=argv[1], output=argv[2];
    VerilatedContext context;
    Vtb model{&context};
    Host host{};
    std::ifstream h(checkpoint+".host",std::ios::binary);
    h.read(reinterpret_cast<char*>(&host),sizeof host);
    if(!h || h.peek()!=EOF) throw std::runtime_error("invalid host checkpoint");
    VerilatedRestore f;
    f.open(checkpoint+".cpu"); f>>model; f.close();
    context.time(host.ticks*10000);
    if(model.clk!=0) throw std::runtime_error("checkpoint is not at a low clock edge");
    std::array<uint8_t,176*208*3> framebuffer{}, scan{};
    for(unsigned i=0;i<18304;i++) {
        model.frame_index=i; model.eval();
        uint32_t word=model.frame_word;
        for(unsigned j=0;j<2;j++) {
            auto rgb=(word>>(16*j))&4095, n=(2*i+j)*3;
            framebuffer[n]=((rgb>>8)&15)*17;
            framebuffer[n+1]=((rgb>>4)&15)*17;
            framebuffer[n+2]=(rgb&15)*17;
        }
    }
    for(unsigned y=0;y<208;y++) for(unsigned x=0;x<176*3;x++)
        scan[y*176*3+x]=host.scan[y*320*3+x];
    ppm(output+"-framebuffer.ppm",framebuffer.data());
    ppm(output+"-scanout.ppm",scan.data());
    std::ofstream metadata(output+".json");
    metadata<<"{\"host_ticks\":"<<host.ticks
            <<",\"cycle_low32\":"<<model.cycle_count
            <<",\"display_on\":"<<unsigned(model.display_on)
            <<",\"frame_complete\":"<<unsigned(model.frame_complete)<<"}\n";
}
