// Small deterministic capture from the actual C++ board, not a checkpoint.
#include "boot_profile.h"
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <vector>
int main() {
 std::ifstream f("build/firmware/nem4-factory/core.bin",std::ios::binary);
 if(!f) return 2;
 std::vector<uint8_t> rom((std::istreambuf_iterator<char>(f)),{});
 BootProfile board(rom,rom.size(),"amd16", true, false, {}, true, {}, 3);
 unsigned ticks=0;
 auto op=[&](uint32_t a,uint32_t d,uint8_t sel,bool write) {
  uint32_t out=0; std::string dev;
  bool ok=board.access({a,d,sel,write,false},out,dev);
  std::cout<<std::dec<<ticks<<'\t'<<(write?'W':'R')<<'\t'<<std::hex<<std::setw(8)<<std::setfill('0')<<a<<'\t'
   <<std::setw(8)<<d<<'\t'<<unsigned(sel)<<'\t'<<ok<<'\t'<<std::setw(8)<<out<<'\t'<<dev<<'\t'
   <<board.timer_irq()<<'\t'<<board.unit60_fiq()<<'\n';
 };
 std::cout<<"ticks\top\taddress\twrite\tmask\taccepted\tread\tdevice\tirq\tfiq\n";
 op(0x04000000,0,15,false); op(0x007f0000,0x00600060,3,true);
 op(0x007f0000,0,3,false); op(0x007f0000,0x00f000f0,3,true);
 for(int i=0;i<16;i++){board.tick();ticks++;}
 op(0x04000000,0,15,false);
 op(0x0c120a04,2,15,true); op(0x0c120a18,0x0115b5c0,15,true); op(0x0c120108,1,15,true);
 for(int i=0;i<4;i++){board.tick();ticks++;op(0x0c120108,0,15,false);}
 op(0xdead0000,0,15,false);
}
