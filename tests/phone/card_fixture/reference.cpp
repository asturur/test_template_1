#include "test_card.h"
#include <fstream>
#include <initializer_list>
#include <stdexcept>
int main(){
 TestCard c;std::ofstream out("build/sim/unit-test-sim/reference.tsv");
 auto send=[&](std::initializer_list<unsigned> xs){for(auto x:xs){c.write(x);out<<"W "<<std::hex<<x<<' '<<c.available()<<'\n';}};
 auto drain=[&](){uint8_t x;while(c.read(x))out<<"R "<<std::hex<<unsigned(x)<<' '<<c.available()<<'\n';};
 auto select=[&](unsigned hi,unsigned lo){send({0xa0,0xa4,0,0,2});drain();send({hi,lo});drain();};
 auto get=[&](){send({0xa0,0xc0,0,0,15});drain();};
 auto read=[&](unsigned n){send({0xa0,0xb0,0,0,n});drain();};
 select(0x3f,0);select(0x2f,0xe2);get();read(10);select(0x7f,0x20);
 send({0xa0,0xf2,0,0,15});drain();send({0xa0,0xf2,0,0,22});drain();
 const unsigned files[][3]={{0x6f,0xb7,3},{0x6f,5,1},{0x6f,0xae,1},{0x6f,0x38,16},{0x6f,0x7e,11},{0x6f,0xad,4},{0x6f,7,9},{0x6f,0x78,2}};
 for(auto &f:files){select(f[0],f[1]);get();read(f[2]);}
 select(0x6f,0x14);select(0x6f,0xc6);select(0xff,0xff);
 send({0xa0,0x10,0,0,3});drain();send({1,2,3});drain();
 send({0xff,0x00,0,0,0});drain();send({0xa0,0x55,0,0,0});drain();
}
