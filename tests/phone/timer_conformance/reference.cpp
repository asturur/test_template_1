#include "boot_profile.h"
#include <fstream>
#include <iomanip>
#include <iterator>
#include <stdexcept>
#include <vector>
int main() {
 std::ifstream f("build/firmware/nem4-factory/core.bin",std::ios::binary);
 std::vector<uint8_t> rom((std::istreambuf_iterator<char>(f)),{});
 if(rom.empty()) return 2;
 BootProfile board(rom,rom.size(),"amd16",true,false,{},true,{},3,-1,-1,-1,-1,-1,false,false,false,false,false,false,false,-1,false,false,false,false,{},false,false,false,false,false,true,false,true,true,false,false,{},false,false,true,true,false,true,{},true);
 std::ofstream out("build/sim/unit-timer-conformance/reference.tsv");
 auto step=[&](bool active,uint32_t address,uint32_t data,bool write) {
  uint32_t read=0;std::string device;
  bool ok=!active || board.access({address,data,15,write,false},read,device);
  board.tick();
  out<<active<<' '<<std::hex<<address<<' '<<data<<' '<<write<<' '<<read<<' '<<board.timer_irq()<<' '<<board.unit60_fiq()<<' '<<ok<<'\n';
 };
 auto idle=[&](unsigned count) {
  for(unsigned i=0;i<count;i++)board.tick();
  out<<2<<' '<<std::hex<<count<<" 0 0 0 "<<board.timer_irq()<<' '<<board.unit60_fiq()<<" 1\n";
 };
 step(true,0x0c120a04,0,true);
 step(true,0x0c120a08,1,true);
 step(true,0x0c120a18,0x000632ea,true);
 step(true,0x0c120a08,0,false);
 step(true,0x0c120a10,0,false);
 step(true,0x0c120a18,0,false);
 step(true,0x0c120a08,0,true);
 step(true,0x0c120a04,2,true);
 step(true,0x0c120a10,0x0115b5c0,true);
 step(true,0x0c120a18,0x0115b5c0,true);
 step(true,0x0c120108,1,true);
 step(false,0,0,false);
 step(true,0x0c120a08,0,false);
 step(true,0x0c120a10,0,false);
 // Periodic arming disables the old IRQ mask on the same transaction.
 step(true,0x0c120a18,0x000632ea,true);
 step(true,0x0c120a08,1,true);
 step(true,0x0c120108,1,true);
 step(false,0,0,false);
 step(true,0x0c1201c8,8,true);
 step(true,0x0c120a64,2,true);
 for(unsigned i=0;i<128;i++)step(false,0,0,false);
 step(true,0x0c1201d0,0,false);
 step(true,0x0c120a68,0,true);
 for(unsigned i=0;i<128;i++)step(false,0,0,false);
 step(true,0x0c120a64,0,true);
 step(true,0x0c120108,2,true);
 step(true,0x0c120a30,4,true);
 step(true,0x0c120a24,1,true);
 for(unsigned i=0;i<4;i++)step(false,0,0,false);
 step(true,0x0c12010c,2,true);
 step(true,0x0c120108,2,true);
 step(true,0x0c120a30,2,true);
 step(true,0x0c120a24,1,true);
 step(true,0x0c12010c,2,true);
 step(true,0x0c120108,2,true);
 step(true,0x0c12010c,2,true);
 step(false,0,0,false);
 step(true,0x0c120a18,0x000632ea,true);
 step(true,0x0c120108,1,true);
 idle(0x632ea-3);
 idle(1);
 step(true,0x0c120a08,0,false);
 step(true,0x0c120a08,0,true);
 idle(0x632ea-3);
 step(true,0x0c120a08,0,true);
 step(true,0x0c120a04,0xdeadbeef,true);
 step(true,0x0c120a08,0xdeadbeef,true);
 step(true,0x0c120a10,0xdeadbeef,true);
 step(true,0x0c120a18,0xdeadbeef,true);
}
