#include "boot_profile.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>
int main(){
 std::ifstream f("build/firmware/nem4-factory/core.bin",std::ios::binary);
 std::vector<uint8_t> rom((std::istreambuf_iterator<char>(f)),{}); if(rom.empty())return 2;
 BootProfile b(rom,rom.size(),"amd16",false,false,{},false,{},0,-1,-1,-1,-1,-1,false,false,false,false,false,false,false,-1,false,false,false,false,{},false,false,false,false,false,false,false,false,false,false,false,{},false,false,false,false,true);
 uint32_t q=0;std::string dev;
 auto t=[&](bool w,uint32_t a,uint16_t v,uint8_t sel){uint32_t d=sel==12?uint32_t(v)<<16:v;if(!b.access({0x02400000+a,d,sel,w,false},q,dev))throw std::runtime_error(b.reason());};
 auto cmd=[&](uint32_t a,uint16_t v){t(true,a,v,(a&2)?12:3);};
 auto unlock=[&](){cmd(0xaaa,0xaa);cmd(0x554,0x55);};
 auto prog=[&](uint32_t a,uint16_t v){unlock();cmd(0xaaa,0xa0);cmd(a,v);};
 try {
 prog(0x100,0x60);t(false,0x100,0,15);if(q!=0xffff0060)throw std::runtime_error("program 60");
 prog(0x102,0xf0);t(false,0x100,0,15);if(q!=0x00f00060)throw std::runtime_error("program f0");
 prog(0x100,0xffff);t(false,0x100,0,15);if(q!=0x00f0ffff)throw std::runtime_error("0-to-1 behavior");
 unlock();cmd(0xaaa,0x90);t(false,0,0,3);if(q!=1)throw std::runtime_error("vendor");t(false,2,0,12);if(q!=0x257e0000)throw std::runtime_error("device");cmd(0,0xf0);
 prog(0x10000,0);prog(0x1fffc,0);prog(0x20000,0x1234);
 unlock();cmd(0xaaa,0x80);unlock();cmd(0x10000,0x30);t(false,0x10000,0,3);if(q!=8)throw std::runtime_error("erase status");t(false,0x10000,0,3);
 t(false,0x1fffc,0,15);if(q!=0xffffffff)throw std::runtime_error("erase end");t(false,0x20000,0,15);if(q!=0xffff1234)throw std::runtime_error("adjacent sector");
 std::cout<<"PASS C: reference commands and erase geometry\n";
 }catch(const std::exception&e){std::cerr<<e.what()<<"\n";return 1;}
}
