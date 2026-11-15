#include "Vngage_uem_clock.h"
#include "verilated.h"
#include <cstdlib>
#include <iostream>
static void tick(Vngage_uem_clock& d) { d.clk=0; d.eval(); d.clk=1; d.eval(); }
int main(int argc,char** argv) {
    Verilated::commandArgs(argc,argv);
    if(argc!=2) return 2;
    const unsigned hz=std::strtoul(argv[1],nullptr,10);
    Vngage_uem_clock d;
    d.clk=0; d.host_timestamp=0;d.day_write=0;d.day_data=0;d.eval();tick(d);
    d.host_timestamp=(1ULL<<32)|45296;
    for(unsigned n=0;n<128&&!d.valid;++n)tick(d);
    if(!d.valid || d.second!=56 || d.minute!=34 || d.hour!=12) return 3;
    for(unsigned n=1;n<hz;++n)tick(d);
    if(d.second!=56)return 4;
    tick(d);
    if(d.second!=57||d.minute!=34||d.hour!=12)return 5;
    std::cout<<"PASS exact "<<hz<<" clocks per UEM second\n";
}
