#include "boot_profile.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>
int main(){
 std::ifstream f("build/firmware/nem4-factory/core.bin",std::ios::binary);std::vector<uint8_t> rom((std::istreambuf_iterator<char>(f)),{});if(rom.empty())return 2;
 BootProfile b(rom,rom.size(),"amd16",true,false,{},true,{},1,-1,-1,-1,-1,-1,false,false,false,false,false,false,false,-1,false,false,false,false,{},false,false,false,false,false,true,false,true,true,false,false,{},false,true);uint32_t out;std::string dev;
 auto op=[&](uint32_t a,uint32_t d,bool w){if(!b.access({a,d,15,w,false},out,dev))throw std::runtime_error(b.reason());};
 try{
 op(0x0c14b004,0x500,true);op(0x0c1003e8,2,true);op(0x0c1003ec,0,true);
 for(unsigned i=0;i<104000;i++)b.tick();op(0x0c1003e8,0,false);if(out!=0x00020002)throw std::runtime_error("ring consumption");
 op(0x0c150100,0,false);if(!(out&0x200))throw std::runtime_error("consumption event");
 for(unsigned i=0;i<104000*19;i++)b.tick();op(0x0c1001f4,0,false);if(out!=0)throw std::runtime_error("early announcement");
 for(unsigned i=0;i<104000;i++)b.tick();op(0x0c1001f4,0,false);if(out!=0x7cd00000)throw std::runtime_error("first frame");
 op(0x0c1001f8,0,false);if(out!=0x04000001)throw std::runtime_error("second frame");op(0x0c1003ec,0,false);if(out!=4)throw std::runtime_error("receive pointer");
 op(0x0c150100,0,false);if((out&0x600)!=0x600)throw std::runtime_error("announcement event");
 std::cout<<"PASS staged MDI reference timing and status\n";
 }catch(const std::exception&e){std::cerr<<e.what()<<"\n";return 1;}
}
