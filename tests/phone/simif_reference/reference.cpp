#include "boot_profile.h"
#include <fstream>
#include <vector>
#include <cstdint>
#include <string>
#include <cstdlib>
int main(int argc,char**argv){
 if(argc!=2)return 2;
 std::ifstream f("build/firmware/nem4-factory/core.bin",std::ios::binary);
 std::vector<uint8_t> rom((std::istreambuf_iterator<char>(f)),{});if(rom.empty())return 2;
 BootProfile b(rom,rom.size(),"amd16",true,false,{},true,{},1,-1,-1,-1,-1,-1,false,false,false,false,false,false,false,-1,false,false,false,false,{},false,false,false,false,false,true,false,true,true,false,false,{},false,true);
 bool present=std::atoi(argv[1]);b.set_simif_no_atr(!present);
 std::ofstream o("build/sim/unit-simif-reference/reference.tsv");
 auto op=[&](uint32_t a,uint32_t d,unsigned sel,bool write){uint32_t out=0;std::string dev;bool ok=b.access({a,d,uint8_t(sel),write,false},out,dev);o<<std::hex<<a<<' '<<d<<' '<<sel<<' '<<write<<' '<<ok<<' '<<out<<' '<<b.simif_pending()<<'\n';};
 auto w=[&](uint32_t a,uint32_t v,unsigned s=3){op(a,v,s,true);};
 auto r=[&](uint32_t a,unsigned s=3){op(a,0,s,false);};
 auto status=[&](){r(0x0c150800);r(0x0c1500b8);};
 auto send=[&](std::initializer_list<unsigned> data){for(auto v:data)w(0x0c15080c,v);};
 auto read=[&](unsigned n){for(unsigned i=0;i<n;i++){r(0x0c15080c);status();}};
 // Control bit auto-clear, mixed writes and byte selection.
 w(0x0c150804,0x00790000,12);r(0x0c150804,12);r(0x0c150804,12);
 w(0x0c150804,0x007e0000,12);r(0x0c150804,12);
 w(0x0c150804,0x00001234,3);r(0x0c150804,3);r(0x0c150804,15);
 status();w(0x0c150808,0xab000000,8);r(0x0c150808,8);w(0x0c150808,1,1);status();r(0x0c15080c,1);r(0x0c15080c,2);
 w(0x0c150808,1);status();w(0x0c150800,0x10,1);status();
 if(present){
  send({0xa0,0xa4,0,0,2});status();w(0x0c150800,8);status();read(1);
  send({0x3f,0});status();w(0x0c150800,8);status();read(2);
  send({0xa0,0xc0,0,0,15});status();w(0x0c150800,8);status();read(18);
  send({0xa0,0xa4,0,0,2});w(0x0c150800,8);read(1);send({0x7f,0x20});w(0x0c150800,8);read(2);
  send({0xa0,0xf2,0,0,15});status();w(0x0c150800,8);read(18);
  r(0x0c15080c); // empty FIFO is an explicit failure
 }else {send({0xa0,0xa4,0,0,2});status();r(0x0c15080c);}
}
