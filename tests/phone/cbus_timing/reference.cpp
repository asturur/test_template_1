#include "Vngage_cbus_uem.h"
#include "verilated.h"
#include "boot_profile.h"
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>
int main(int argc,char**argv){
 Verilated::commandArgs(argc,argv);
 std::ifstream f("build/firmware/nem4-factory/core.bin",std::ios::binary);
 std::vector<uint8_t> rom((std::istreambuf_iterator<char>(f)),{});if(rom.empty())return 2;
 BootProfile b(rom,rom.size(),"amd16",true,false,{},true,{},3,-1,-1,-1,-1,-1,false,false,false,false,false,false,false,-1,false,false,false,false,{},false,false,false,false,false,true,false,true,true,false,false,{},false,false,true,true,false,false,{},true);
 Vngage_cbus_uem d;d.clk=0;d.reset=1;d.req=0;d.commit=0;d.we=0;d.addr=0;d.din=0;d.sel=15;d.kernel_periodic=1;d.clear_irq=0;
 auto edge=[&](){d.clk=0;d.eval();d.clk=1;d.eval();};
 edge();d.reset=0;uint32_t out;std::string dev;
 auto op=[&](uint32_t a,uint32_t data,uint8_t sel){
  if(!b.access({a,data,sel,true,false},out,dev))throw std::runtime_error(b.reason());
  d.req=1;d.commit=1;d.we=1;d.addr=a;d.din=data;d.sel=sel;d.clk=0;d.eval();
  if(!d.claim||d.bad)throw std::runtime_error("RTL rejected CBUS write");
  d.clk=1;d.eval();b.tick();d.req=0;d.commit=0;
 };
 auto icu=[&](uint32_t a){if(!b.access({a,2,15,true,false},out,dev))throw std::runtime_error(b.reason());d.clear_irq=(a==0x0c12010c);edge();b.tick();d.clear_irq=0;};
 try{
  icu(0x0c120108);
  op(0x0c150420,15,3);op(0x0c150420,0x00360000,12);op(0x0c150424,0xfff70000,12);
  // Global 65536-cycle phase: countdown starts on the first boundary
  // after arming and lasts 122 boundaries. The four preceding edges count.
  for(uint32_t cycle=5;cycle<7995392;cycle++){
   edge();b.tick();
   if(d.irq_pending || b.uem_irq())throw std::runtime_error("early RTC alarm");
  }
  // Acknowledge on the alarm edge; the event must survive and be seen
  // once the ICU source is enabled again on the following edge.
  icu(0x0c12010c);
  if(!d.irq_pending || b.uem_irq())throw std::runtime_error("alarm/ack collision");
  icu(0x0c120108);
  if(!d.irq_pending || !b.uem_irq())throw std::runtime_error("alarm reenable");
  icu(0x0c12010c);
  if(d.irq_pending || b.uem_irq())throw std::runtime_error("alarm clear");
  icu(0x0c120108);
  for(uint32_t cycle=7995396;cycle<104000000;cycle++){
   edge();b.tick();
   if(d.irq_pending || b.uem_irq())throw std::runtime_error("early 1 Hz interrupt");
  }
  edge();b.tick();
  if(!d.irq_pending || !b.uem_irq())throw std::runtime_error("1 Hz interrupt phase");
  std::cout<<"PASS CBUS alarm, 1 Hz phase and acknowledgement against C++\n";
 }catch(const std::exception&e){std::cerr<<"FAIL "<<e.what()<<"\n";return 1;}
}
