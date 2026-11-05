#include "Vngage_flash_read_decode.h"
#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>
int main(int argc,char**argv){
 if(argc!=2)return 2;std::ifstream f(argv[1],std::ios::binary);std::vector<uint8_t> b((std::istreambuf_iterator<char>(f)),{});
 if(b.size()<0x11b5000)return 3;Vngage_flash_read_decode dut;dut.array_read=1;dut.code_flash=1;
 for(uint32_t pa=0x9000;pa<0x11b5000;pa+=4){
  dut.physical_address=pa;dut.raw_data=uint32_t(b[pa])|(uint32_t(b[pa+1])<<8)|(uint32_t(b[pa+2])<<16)|(uint32_t(b[pa+3])<<24);dut.eval();
  uint32_t x=dut.result;char out[4]={char(x),char(x>>8),char(x>>16),char(x>>24)};std::cout.write(out,4);
 }return std::cout?0:4;
}
