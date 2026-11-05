#include "boot_profile.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>
int main(){
 std::ifstream f("build/firmware/nem4-factory/core.bin",std::ios::binary);std::vector<uint8_t> rom((std::istreambuf_iterator<char>(f)),{});if(rom.empty())return 2;
 BootProfile b(rom,rom.size(),"amd16",true,false,{},true,{{6,512}},5,1,0,16,-1,-1,false,false,false,false,false,false,false,-1,false,false,false,false,{},false,false,false,false,false,false,false,false,false,false,false,{});
 uint32_t q=0;std::string dev;
 auto bus=[&](bool w,uint32_t a,uint16_t v,uint8_t sel){uint32_t d=sel==12?uint32_t(v)<<16:v;if(!b.access({a,d,sel,w,false},q,dev))throw std::runtime_error(b.reason());};
 auto cfg=[&](uint16_t v){bus(true,0x0c150420,v,3);};auto cmd=[&](uint16_t v){bus(true,0x0c150420,v,12);};auto payload=[&](uint16_t v){bus(true,0x0c150424,v,12);};
 try{
 cfg(7);cmd(0x135);bus(false,0x0c150420,0,12);if(q!=0x05350000)throw std::runtime_error("status");bus(false,0x0c150424,0,12);if(q!=0x00180000)throw std::runtime_error("RTC status");
 cfg(7);cmd(0x39);payload(0x6800);cfg(7);cmd(0x13a);bus(false,0x0c150424,0,12);if(q!=0x02000000)throw std::runtime_error("ADC");

 std::cout<<"PASS CBUS reference RTC and ADC\n";
 }catch(const std::exception&e){std::cerr<<e.what()<<"\n";return 1;}
}
