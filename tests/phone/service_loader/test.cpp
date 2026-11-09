#include "Vservice_transport.h"
#include <algorithm>
#include <cstdint>
#include <fstream>
#include <filesystem>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>

static void check(bool ok, const char* message) {
    if (!ok) throw std::runtime_error(message);
}
static std::vector<uint8_t> read(const char* path) {
    std::ifstream stream(path, std::ios::binary);
    check(bool(stream), "missing input");
    return {std::istreambuf_iterator<char>(stream), {}};
}
struct Test {
    Vservice_transport d;
    std::vector<uint8_t> memory = std::vector<uint8_t>(0x1810000, 0xA5);
    uint64_t cycles = 0, writes = 0;
    bool stall = false;
    void tick(unsigned n=1) {
        while (n--) {
            d.clk=0; d.ddr_busy=stall || cycles%11<3; d.eval();
            if (d.ddr_we && !d.ddr_busy) {
                uint64_t base=uint64_t(d.ddr_addr)*8;
                check(base>=0x30000000 && base+8<=0x313F0000, "firmware write escaped its DDR range");
                for (unsigned i=0;i<8;i++) if (d.ddr_be & (1<<i))
                    memory.at(base-0x30000000+i)=uint8_t(d.ddr_data>>(8*i));
                writes++;
            }
            d.clk=1; d.eval(); cycles++;
        }
    }
    void reset() {
        d.host_enable=0;d.host_strobe=0;d.direct_download=0;d.direct_wr=0;
        d.mounted=0;d.save_busy=0;d.save_error=0;stall=false;
        d.reset=1;tick(5);d.reset=0;tick(5);
    }
    void ready() {
        uint64_t deadline=cycles+100000000;
        d.clk=0;d.eval();
        while (d.wait_req) {check(cycles<deadline, "wait timeout");tick();}
    }
    void word(uint16_t value) {
        d.host_data=value;d.host_strobe=1;tick();
        d.host_strobe=0;tick(3);
    }
    void command(uint16_t cmd, uint16_t value) {
        d.host_enable=1;tick();word(cmd);word(value);d.host_enable=0;tick(4);
    }
    void start(uint16_t index, bool hps) {
        d.use_hps=hps;
        if (hps) {command(0x55,index);command(0x53,1);}
        else {d.direct_index=index;d.direct_addr=0;d.direct_download=1;tick();}
    }
    void end(bool hps) {
        ready();
        if (hps) {d.host_enable=0;tick(4);command(0x53,0);}
        else {d.direct_wr=0;d.direct_download=0;tick();}
        tick(8);
    }
    void send(const std::vector<uint8_t>& bytes, uint16_t index, bool hps) {
        start(index,hps);ready();
        if (hps) {d.host_enable=1;tick();word(0x54);}
        for (size_t pos=0;pos<bytes.size();pos+=2) {
            ready();
            uint16_t value=bytes[pos] | (pos+1<bytes.size()?uint16_t(bytes[pos+1])<<8:0);
            if (hps) word(value);
            else {d.direct_addr=pos;d.direct_data=value;d.direct_wr=1;tick();d.direct_wr=0;}
        }
        end(hps);
    }
    void preserved() {
        check(std::all_of(memory.begin()+0x13F0000,memory.end(),[](uint8_t b){return b==0xA5;}),
              "guard, C: or PMM modified");
    }
    void compare(const std::vector<uint8_t>& expected) {
        check(d.valid && !d.failed,"firmware pair not ready");
        auto mismatch=std::mismatch(expected.begin(),expected.end(),memory.begin());
        if (mismatch.first!=expected.end()) {
            std::cerr<<"backing mismatch offset "<<std::hex<<(mismatch.first-expected.begin())<<"\n";
            throw std::runtime_error("firmware backing differs");
        }
        preserved();
        // Every decoded word in the scrambled window sees exactly the same
        // production read-side transform as the current assembled firmware.
        for (size_t a=0xA000;a<0x2B3000;a+=4) {
            auto decode=[&](const std::vector<uint8_t>& bytes) {
                d.direct_addr=a;d.direct_data=bytes[a]|uint16_t(bytes[a+1])<<8;
                d.host_data=bytes[a+2]|uint16_t(bytes[a+3])<<8;d.eval();return d.decoded;
            };
            uint32_t baseline=decode(expected), actual=decode(memory);
            check(baseline==actual,"descrambled read mismatch");
        }
    }
};
int main(int argc, char** argv) {
    auto mcu=read("firmware/NEM-04 v.04.03 N-GAGE/nem440.3c1");
    auto ppm=read("firmware/NEM-04 v.04.03 N-GAGE/nem440.326");
    auto expected=read("build/firmware/nem4-factory/core.bin");
    auto extension=read("build/firmware/nem4-factory/extension.bin");
    expected.insert(expected.end(),extension.begin(),extension.end());
    Test t;t.reset();
    // Actual Main-style numbered-first order, followed by the legacy boot name.
    t.send(ppm,0x40,true);check(!t.d.valid&&!t.d.failed,"PPM alone released CPU");
    t.send(mcu,0,true);t.compare(expected);
    std::cout<<"PASS actual hps_io boot1 then boot: all 20905984 backing bytes, decoded reads and C:/PMM guard\n"<<std::flush;
    // Produce boot input only AFTER real hps_io + production loader + DDR
    // adapter traffic has completed and full backing equality was verified.
    if (argc == 3 && std::string(argv[1]) == "--export-boot") {
        std::filesystem::create_directories(argv[2]);
        auto save = [&](const char* name, size_t offset, size_t size) {
            auto path = std::filesystem::path(argv[2]) / name;
            check(!std::filesystem::exists(path), "refuse existing export");
            std::ofstream f(path, std::ios::binary);
            f.write(reinterpret_cast<const char*>(t.memory.data()+offset),size);
            check(bool(f), "boot export failed");
        };
        save("core.bin",0,18612224);
        save("extension.bin",18612224,2293760);
        std::cout << "PASS exported production service-loader DDR output\n";
        return 0;
    }
    // A bad slot must not release the CPU; reloading retains the other slot.
    auto corrupt=ppm;corrupt[0xD9+10]^=1;
    t.send(corrupt,2,false);check(!t.d.valid&&t.d.failed&&t.d.reason==7,"payload corruption accepted");
    // Drop download immediately after the final accepted input word. The
    // unpacker and last DDR write must drain before validity can rise.
    t.start(2,false);t.ready();
    for (size_t pos=0;pos<ppm.size();pos+=2) {
        t.ready();t.d.direct_addr=pos;
        t.d.direct_data=ppm[pos] | (pos+1<ppm.size()?uint16_t(ppm[pos+1])<<8:0);
        t.d.direct_wr=1;t.tick();t.d.direct_wr=0;
    }
    t.d.direct_download=0;t.stall=true;t.tick(20);
    check(!t.d.valid,"pair validated before final DDR acknowledgement");
    t.stall=false;t.tick(40);t.compare(expected);
    t.send(mcu,1,false);t.compare(expected);
    std::cout<<"PASS manual indices, rejected payload, recovery and same-file reloads\n"<<std::flush;
    // Preserve mounted/save-owned backing and reject reload requests before
    // they reach the parser. Same protections as Template.sv.
    uint64_t before=t.writes;
    for (unsigned condition=0;condition<3;condition++) {
        t.d.mounted=condition==0;t.d.save_busy=condition==1;t.d.save_error=condition==2;
        t.send(std::vector<uint8_t>(32,0),1,false);
        check(t.d.blocked&&t.writes==before&&t.d.valid,"protected reload changed backing");
    }
    t.d.mounted=0;t.d.save_busy=0;t.d.save_error=0;
    // Opposite full input order, with real hps manual selectors.
    t.reset();t.send(mcu,1,true);check(!t.d.valid&&!t.d.failed,"MCU alone released CPU");
    t.send(ppm,2,true);t.compare(expected);
    std::cout<<"PASS actual hps_io MCU then PPM and protected mounted/busy/error reloads\n"<<std::flush;
    // End with bounded malformed-input cases; full-file CRC catches mutations
    // in skipped metadata/algorithm even when all record checksums still pass.
    corrupt=ppm;corrupt[20]^=1;
    t.send(corrupt,2,false);check(!t.d.valid&&t.d.failed,"metadata corruption accepted");
    for (size_t cut : {size_t(1),size_t(0xD9),size_t(0xD9+5),size_t(0xD9+11),ppm.size()-1}) {
        t.send(std::vector<uint8_t>(ppm.begin(),ppm.begin()+cut),2,false);
        check(!t.d.valid&&t.d.failed,"truncated file accepted");
    }
    // Corrupt a record address, recomputing its header checksum. Explicit
    // range checks reject it before any payload byte can reach user storage.
    for (uint32_t a : {0x2400000U,0x7F0000U,0xFFFFFFFEU}) {
        corrupt.assign(ppm.begin(),ppm.begin()+0xD9+12);
        for (unsigned i=0;i<4;i++) corrupt[0xD9+1+i]=a>>(24-8*i);
        unsigned sum=0;for(unsigned i=1;i<9;i++)sum+=corrupt[0xD9+i];
        corrupt[0xD9+9]=255-sum;
        t.send(corrupt,2,false);check(t.d.failed&&t.d.reason==9,"bad address accepted");t.preserved();
    }
    // PPM's odd EOF accepts Main's one zero pad only.
    corrupt=ppm;corrupt.push_back(1);
    t.send(corrupt,2,false);check(t.d.failed&&t.d.reason==4,"nonzero pad accepted");
    corrupt=ppm;corrupt.insert(corrupt.end(),3,0);
    t.send(corrupt,2,false);check(t.d.failed,"extra transport word accepted");
    // Out-of-order ioctl addresses, slot change, abort during clear, and cold
    // reset while DDR is stalled cannot validate a partial image.
    t.start(2,false);t.ready();t.d.direct_addr=2;t.d.direct_data=0;t.d.direct_wr=1;t.tick();t.d.direct_wr=0;t.end(false);
    check(t.d.failed&&t.d.reason==3,"address hole accepted");
    t.start(2,false);t.ready();t.d.direct_index=1;t.tick();t.end(false);
    check(t.d.failed&&t.d.reason==2,"mid-stream slot change accepted");
    t.start(2,false);t.d.direct_download=0;t.tick(20);check(t.d.failed&&!t.d.valid,"erase abort accepted");
    t.reset();t.start(0,false);t.stall=true;t.tick(20);check(t.d.wait_req&&!t.d.valid,"erase did not stall");
    t.d.reset=1;t.tick(4);t.stall=false;t.d.direct_download=0;t.d.reset=0;t.tick(8);
    check(!t.d.valid&&!t.d.failed,"cold reset kept partial pair valid");t.preserved();
    std::cout<<"PASS malformed streams, bounds, odd EOF, abort/reset and DDR stalls; "<<t.cycles<<" clocks, "<<t.writes<<" writes\n";
}
