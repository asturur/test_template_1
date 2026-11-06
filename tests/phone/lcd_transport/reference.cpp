#include "boot_profile.h"
#include <fstream>
#include <iomanip>
#include <iterator>
#include <stdexcept>
#include <vector>
int main(){
 std::ifstream f("build/firmware/nem4-factory/core.bin",std::ios::binary);
 std::vector<uint8_t> rom((std::istreambuf_iterator<char>(f)),{});if(rom.empty())return 2;
 BootProfile b(rom,rom.size(),"amd16",true,true);
 std::ofstream o("build/sim/unit-lcd-transport/reference.tsv");
 auto op=[&](uint32_t a,uint32_t v,unsigned mask,bool write){
  uint32_t data=0;std::string dev;bool ok=b.access({a,v,uint8_t(mask),write,false},data,dev);
  o<<std::hex<<a<<' '<<v<<' '<<mask<<' '<<write<<' '<<ok<<' '<<data<<'\n';
 };
 op(0x0c121200,0x49200000,15,true); // enable required
 op(0x0c121204,1,3,true);          // invalid width
 op(0x0c121204,1,15,true);
 op(0x0c121204,0,15,false);
 op(0x0c121208,0,15,false);        // header required
 op(0x0c121200,0x49200000,15,true);
 op(0x0c121200,0,15,false);
 op(0x0c121208,0x12345678,15,true);
 op(0x0c121200,0x07840011,15,true);
 op(0x0c121208,0,15,false);
 op(0x0c121204,2,15,true);
 op(0x0c121208,0,15,false);
 op(0x0c121204,1,15,true);
 op(0x0c121208,0,15,false);
 op(0x0c121200,0xdeadbeef,15,true);
 op(0x0c121200,0x8924d67f,15,true);
 op(0x0c121208,0xabcdabcd,15,true);
}
