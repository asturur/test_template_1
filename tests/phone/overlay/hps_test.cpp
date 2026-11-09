#include "Voverlay_transport.h"
#include "verilated.h"
#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>
static void check(bool value, const char *message) {
    if (!value) throw std::runtime_error(message);
}
static std::vector<uint8_t> read(const char *path) {
    std::ifstream f(path,std::ios::binary);check(bool(f),"missing input");
    return {std::istreambuf_iterator<char>(f),{}};
}
static uint32_t word(const std::vector<uint8_t>& bytes,size_t at) {
    return uint32_t(bytes.at(at)) | uint32_t(bytes.at(at+1))<<8 |
        uint32_t(bytes.at(at+2))<<16 | uint32_t(bytes.at(at+3))<<24;
}
struct Test {
    Voverlay_transport d;
    std::vector<uint8_t> memory;
    uint64_t cycles=0,writes=0;
    unsigned delay=0;
    uint32_t pending_addr=0;
    void tick(unsigned n=1) {
        while(n--) {
            d.clk=0;d.ddr_busy=cycles%11<3 || delay;d.ddr_ready=0;
            if(delay && --delay==0) {
                uint64_t data=0;
                for(unsigned i=0;i<8;i++)data|=uint64_t(memory.at(pending_addr+i))<<(8*i);
                d.ddr_q=data;d.ddr_ready=1;
            }
            d.eval();
            if(!d.ddr_busy && (d.ddr_we || d.ddr_rd)) {
                uint64_t base=uint64_t(d.ddr_addr)*8;
                check(base>=0x30000000 && base+8<=0x313F0000,"overlay escaped firmware range");
                base-=0x30000000;
                if(d.ddr_we) {
                    check(!d.ready,"CPU released during patch writes");
                    for(unsigned i=0;i<8;i++)if(d.ddr_be&(1<<i))memory.at(base+i)=d.ddr_data>>(8*i);
                    writes++;
                } else { pending_addr=base;delay=4; }
            }
            d.clk=1;d.eval();cycles++;
            check(!d.error,"overlay transport/validation error");
        }
    }
    void word(uint16_t value) {
        d.host_data=value;d.host_strobe=1;tick();d.host_strobe=0;tick(3);
    }
    void command(uint16_t cmd,uint16_t value) {
        d.host_enable=1;tick();word(cmd);word(value);d.host_enable=0;tick(4);
    }
    void send(const std::vector<uint8_t>& bytes,unsigned index) {
        command(0x55,index);command(0x53,1);
        d.host_enable=1;tick();word(0x54);
        for(size_t i=0;i<bytes.size();i+=2) {
            unsigned wait=0;
            while(d.wait_req) {tick();check(++wait<1000,"ioctl_wait stuck");}
            word(bytes[i] | uint16_t(bytes.at(i+1))<<8);
        }
        d.host_enable=0;tick(4);command(0x53,0);tick(8);
    }
    void settle() {
        unsigned wait=0;
        while(!d.ready) {tick();check(++wait<100000,"overlay release timeout");}
    }
};
int main(int argc,char **argv) {
    check(argc==4,"usage: hps_test package core extension");
    auto pack=read(argv[1]),original=read(argv[2]),extension=read(argv[3]);
    original.insert(original.end(),extension.begin(),extension.end());
    auto patched=original;
    for(size_t at=64;at<pack.size();at+=12) {
        auto address=word(pack,at);check(word(original,address)==word(pack,at+4),"wrong original target");
        auto value=word(pack,at+8);
        for(unsigned i=0;i<4;i++)patched.at(address+i)=value>>(8*i);
    }
    original.resize(0x1810000,0xa5);patched.resize(0x1810000,0xa5);
    Test t;t.memory=original;t.d.reset=1;t.d.enabled=1;t.d.firmware_valid=0;
    t.tick(5);t.d.reset=0;t.tick(5);
    t.send(pack,0x80);
    check(t.d.loaded && !t.d.ready && !t.d.applied && !t.writes,"boot2 did not stage before firmware");
    t.d.firmware_valid=1;t.settle();
    check(t.memory==patched && t.d.applied,"autoload did not apply exact NOS/checksum view");
    t.d.enabled=0;t.tick();t.settle();
    check(t.memory==original && !t.d.applied,"OFF did not restore byte-exact original/C:/PMM");
    for(unsigned index:{0u,0x40u,1u,2u}) {
        auto before=t.writes;t.send(pack,index);t.settle();
        check(t.writes==before && t.memory==original,"service index reached overlay loader");
    }
    t.send(pack,3);t.settle();t.d.enabled=1;t.tick();t.settle();
    check(t.memory==patched,"manual F3 did not apply");
    t.d.enabled=0;t.tick();t.settle();check(t.memory==original,"manual OFF undo failed");
    std::cout<<"PASS actual hps_io boot2/F3, deferred firmware gating, exact ON/OFF, service-index isolation, backpressure and C:/PMM preservation\n";
}
