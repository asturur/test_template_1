#include "boot_profile.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>
int main() {
 try {
  std::ifstream f("build/firmware/nem4-factory/core.bin",std::ios::binary);
  if(!f) throw std::runtime_error("firmware missing");
  std::vector<uint8_t> rom((std::istreambuf_iterator<char>(f)),{});
  BootProfile board(rom,rom.size(),"amd16");
  uint32_t data;std::string device;
  auto access=[&](uint32_t a,uint32_t d,uint8_t sel,bool w,bool code=false){
   if(!board.access({a,d,sel,w,code},data,device)) throw std::runtime_error("unmodeled access: "+board.reason());
  };
  access(0x0027ee60,0,15,false,true);auto original=data;
  access(0x04000000,0,15,false,true);auto other_chip=data;
  access(0x007f0000,0x00600060,3,true);
  access(0x04000000,0,15,false,true);
  if(data!=other_chip || device=="flash_pmm_status")throw std::runtime_error("lock mode leaked to another chip");
  access(0x0027ee60,0,15,false,true);
  if(data!=original || device=="flash_pmm_status")throw std::runtime_error("other bank instruction fetch corrupted by lock sequence");
  access(0x007f0000,0x00600060,3,true);
  access(0x007f0080,0x00600060,3,true);
  access(0x007f0000,0,3,false);
  if((data&0xffff)!=1 || device!="flash_pmm_status")throw std::runtime_error("PMM lock status unavailable");
  access(0x007f0000,0x00f000f0,3,true);
  access(0x0027ee60,0,15,false,true);
  if(data!=original)throw std::runtime_error("array reset failed");
  access(0x007f003e,0x00400000,12,true);
  access(0x007f003e,0x00600000,12,true);
  access(0x007f0000,0x00f000f0,3,true);
  access(0x007f003e,0,12,false);
  if((data>>16)!=0x60 || device!="flash_pmm_overlay")throw std::runtime_error("program data 0x60 misdecoded as lock command");
  std::cout<<"PASS: PMM lock sequence preserves instruction reads in another bank\n";
 } catch(const std::exception& e) { std::cerr<<e.what()<<'\n';return 1; }
}
