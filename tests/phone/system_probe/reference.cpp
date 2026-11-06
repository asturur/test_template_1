#include "boot_profile.h"
#include <fstream>
#include <iomanip>
#include <iterator>
#include <vector>
int main(){
 std::ifstream f("build/firmware/nem4-factory/core.bin",std::ios::binary);
 std::vector<uint8_t> rom((std::istreambuf_iterator<char>(f)),{});if(rom.empty())return 2;
 BootProfile b(rom,rom.size(),"amd16",true,false,{},true,{},3,-1,-1,-1,-1,0x82,false,false,false,false,false,false,true,0x400,true,true,false,false,{},false,false,false,true,false,true,false,true,true,true,false,{},false,true,true,true);
 std::ofstream o("build/sim/unit-system-probe/reference.tsv");
 auto op=[&](uint32_t a,uint32_t v,unsigned mask,bool write){uint32_t d=0;std::string dev;bool ok=b.access({a,v,uint8_t(mask),write,false},d,dev);o<<std::hex<<a<<' '<<v<<' '<<mask<<' '<<write<<' '<<ok<<' '<<d<<'\n';};
 op(0x0c120074,3,15,true);
 op(0x0c14d000,0,15,false);
 op(0x0c150420,7,3,true);op(0x0c150420,0x00820000,12,true);op(0x0c150424,0x12340000,12,true);
 op(0x0c150420,7,3,true);op(0x0c150420,0x008d0000,12,true);op(0x0c150424,0x45670000,12,true);
 op(0x0c120074,3,15,true);
 op(0x0c14d000,0,15,false);
 op(0x0c14d000,0x12345678,15,true);
 op(0x0c14d000,0x0000abcd,3,true);
 op(0x0c14d000,0,15,false);
 op(0x0c14d010,0,15,false);
}
