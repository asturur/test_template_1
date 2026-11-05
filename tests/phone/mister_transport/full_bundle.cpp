#include "Vfull_bundle.h"
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>
#include <stdexcept>
int main(int argc,char** argv) {
 if(argc!=2) return 2;
 std::ifstream f(argv[1],std::ios::binary); std::vector<uint8_t> image((std::istreambuf_iterator<char>(f)),{});
 const size_t lengths[]={0x11c0000,0x230000,0x400000,0x10000};
 const size_t offsets[]={0,0x11c0000,0x1400000,0x1800000};
 if(image.size()!=128+lengths[0]+lengths[1]+lengths[2]+lengths[3]) throw std::runtime_error("incorrect input length");
 std::vector<uint8_t> memory(0x1810000,0xa5); Vfull_bundle d;
 uint64_t cycles=0, writes=0; size_t pos=0; bool started=false, ended=false; int read_delay=0; uint64_t read_value=0;
 auto tick=[&]() {
  d.clk=0; d.busy=(cycles%7<3);
  d.ddr_dout_ready=(read_delay==1); d.ddr_dout=read_value; d.eval();
  if(read_delay) read_delay--;
  if(d.ddr_rd && !d.busy) {
   if(read_delay) throw std::runtime_error("overlapping DDR reads");
   uint64_t address=uint64_t(d.ddr_addr)*8;
   if(address<0x30000000 || address+8>0x31810000) throw std::runtime_error("read out of range");
   size_t off=address-0x30000000; read_value=0;
   for(int i=0;i<8;i++) read_value |= uint64_t(memory.at(off+i)) << (8*i);
   read_delay=3;
  }
  if(d.ddr_we && !d.busy) {
   uint64_t byte_addr=uint64_t(d.ddr_addr)*8;
   if(byte_addr<0x30000000 || byte_addr+8>0x31810000) throw std::runtime_error("DDR address out of bounds");
   size_t base=byte_addr-0x30000000;
   for(int i=0;i<8;i++) if(d.ddr_be&(1<<i)) memory.at(base+i)=uint8_t(d.ddr_din>>(i*8));
   writes++;
  }
  d.clk=1; d.eval(); cycles++;
 };
 d.reset=1;tick();d.reset=0;d.download=1;d.wr=0;tick();
 while(!d.valid && !d.failed && cycles<350000000) {
  d.clk=0;d.eval();
  if(pos<image.size() && !d.wait_req) {
   d.addr=pos; d.data=uint16_t(image[pos]) | (uint16_t(image[pos+1])<<8); d.wr=1; pos+=2; started=true;
  } else { d.wr=0; if(pos==image.size() && started && !d.wait_req) {d.download=0; ended=true;} }
  tick();
 }
 if(!ended || !d.valid || d.failed || pos!=image.size()) throw std::runtime_error("loader rejected full image");
 size_t src=128;
 // Issue CPU-side DDR reads for every word. The arbiter and adapter must return
 // exactly the bytes streamed in, including both halves of each 64-bit beat.
 for(int section=0;section<4;section++) {
  for(size_t i=0;i<lengths[section];i+=4) {
   d.cpu_addr=uint32_t(0x30000000+offsets[section]+i); d.cpu_valid=1;
   do { d.clk=0; d.eval(); bool accept=d.cpu_ready; tick(); if(accept) break; } while(true);
   d.cpu_valid=0;
   for(;;) { d.clk=0; d.eval(); bool done=d.cpu_done; uint32_t value=d.cpu_data; tick();
    if(done) { for(unsigned j=0;j<4;j++) if(uint8_t(value>>(8*j))!=image[src+i+j]) throw std::runtime_error("CPU DDR readback mismatch"); break; }
    if(cycles>500000000) throw std::runtime_error("readback timeout");
   }
  }
  src+=lengths[section];
 }
 src=128;
 for(int section=0;section<4;section++) {
  for(size_t i=0;i<lengths[section];i++) if(memory[offsets[section]+i]!=image[src+i]) throw std::runtime_error("section readback mismatch");
  src+=lengths[section];
 }
 for(size_t i=0x13f0000;i<0x1400000;i++) if(memory[i]!=0xa5) throw std::runtime_error("guard was modified");
 std::cout<<"PASS full bundle: "<<pos<<" input bytes, "<<writes<<" accepted writes, "<<cycles<<" cycles; all CPU DDR reads, sections and guard match\n";
}
