#include "boot_profile.h"
#include <iostream>
#include <stdexcept>
#include <sstream>
#include <vector>

void check(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}
void put(std::vector<uint8_t>& rom, size_t at, uint32_t value) {
    for (unsigned i=0; i<4; ++i) rom.at(at+i) = (value >> (8*i)) & 255;
}
std::vector<uint8_t> fixture() {
    std::vector<uint8_t> rom(0x1000, 0x5a);
    put(rom,0,0x11223344); put(rom,0x100,0x55667788);
    for (size_t table : {0x638u,0x744u,0x830u}) {
        put(rom,table,3); put(rom,table+4,1);
        const uint32_t values[12]={0,0x100,1,0, 0x02000000,0x100,1,0,
                                  0x0a000000,table==0x830?0x01000000u:0x00800000u,2,0};
        for (unsigned i=0;i<12;++i) put(rom,table+8+4*i,values[i]);
    }
    return rom;
}
int main() {
    try {
        auto rom=fixture();
        for (const std::string kind : {"intel8","amd8","amd16"}) {
            BootProfile board(rom,rom.size(),kind);
            uint32_t data=0; std::string device;
            auto read=[&](uint32_t a,uint8_t sel=15){return board.access({a,0,sel,false},data,device);};
            auto write=[&](uint32_t a,uint32_t v,uint8_t sel=15){return board.access({a,v,sel,true},data,device);};
            check(read(0)&&data==0x11223344,"first physical ROM bank");
            check(read(0x02000000)&&data==0x55667788,"noncontiguous second ROM bank");
            check(!read(0x0c004748),"scratch reads before writes must stop");
            check(write(0x0c004748,0x11223344,3),"scratch halfword write");
            check(!read(0x0c004748),"unwritten upper scratch bytes must stop");
            check(read(0x0c004748,3)&&data==0x3344,"scratch halfword read");
            check(write(0x0c004748,0x55660000,12),"scratch upper halfword write");
            check(read(0x0c004748)&&data==0x55663344,"scratch word fetch after initialization");
            check(write(0x0c0047e0,0xaabbccdd),"last boot-copied scratch word");
            check(write(0x0c0047f0,0x5149d09c)&&read(0x0c0047f0)&&data==0x5149d09c,"variant interface pointer scratch word");
            check(!read(0x0c0047ec),"gap scratch bytes remain unwritten");
            check(!write(0x0c0047f4,0),"scratch end boundary");
            check(!write(0x0c004744,0),"scratch start boundary");
            check(!read(0x50000000),"virtual ROM alias must not bypass MMU");
            check(!read(0x80000000),"virtual RAM alias must not bypass MMU");
            check(!read(0x08000000),"unwritten register reset value must stop");
            check(write(0x08000000,0x7037f800),"startup latch write");
            check(read(0x08000000)&&data==0x7037f800,"startup latch readback");
            check(!write(0x0800000c,0),"unobserved startup register must stop");
            check(write(0x0c150004,0x80,3),"observed halfword register");
            check(!read(0x0c150004),"unknown upper register bits must stop");
            check(read(0x0c150004,3)&&data==0x80,"known halfword register readback");
            check(write(0x0a000100,0x11223344),"physical RAM write");
            check(write(0x0a000100,0x0000aa00,2),"physical RAM byte enable");
            check(read(0x0a000100)&&data==0x1122aa44,"RAM byte-enable result");
            const uint32_t end=kind=="amd16"?0x0b000000:0x0a800000;
            check(read(end-4),"last physical RAM word");
            check(!read(end),"physical RAM boundary");
            check(write(0x02000000,0xff,3),"read-array reset");
            check(write(0x0200aaaa,0x00900000,12),"Intel identification command");
            if (kind=="intel8") {
                check(read(0x02000000)&&data==0x88720089,"Intel IDs");
            } else {
                check(read(0x02000000)&&data==0x55667788,"Intel probe must not select AMD ID mode");
                check(write(0x02000000,0xf0,3),"AMD reset");
                check(write(0x02000aaa,0x00aa0000,12),"AMD unlock 1");
                check(write(0x02000554,0x55,3),"AMD unlock 2");
                check(write(0x02000aaa,0x00900000,12),"AMD autoselect");
                const uint32_t expected=kind=="amd8"?0x22d10001:0x257e0001;
                check(read(0x02000000)&&data==expected,"AMD IDs");
            }
            check(!read(0x02000004),"unmodeled ID offsets must stop");
            check(write(0x02000000,0xff,3),"leave ID mode");
            check(read(0x02000000)&&data==0x55667788,"read-array restored");
            // CS0 and CS2 have their own AMD autoselect state and extended IDs.
            for (uint32_t base : {0u,0x04000000u}) {
                check(!write(base+0x16aaa,0x00c00000,12),"burst configuration requires unlock");
                check(write(base+0xaaa,0x00aa0000,12),"burst unlock 1");
                check(write(base+0x554,0x55,3),"burst unlock 2");
                check(write(base+0x16aaa,0x00c00000,12),"burst configuration command");
                check(write(base,0xf0,3),"independent chip reset");
                check(write(base+0xaaa,0x00aa0000,12),"independent chip unlock 1");
                check(write(base+0x554,0x55,3),"independent chip unlock 2");
                check(write(base+0xaaa,0x00900000,12),"independent chip autoselect");
                check(read(base)&&data==0x257e0001,"hypothesized Nokia-custom chip manufacturer/device");
                check(read(base+0x1c)&&data==0x25002502,"AMD extended device identity");
                check(read(base+4,12)&&data==0x00420000,"AMD handshake option");
                check(!read(base+4,3),"unknown lock state must not be invented");
                check(read(0x02000000)&&data==0x55667788,"chip ID state must not leak to CS1");
            }
            check(write(0,0xf0,3),"reset CS0 only");
            check(read(0)&&data==0x11223344,"CS0 array restored");
            check(read(0x04000000)&&data==0x257e0001,"CS2 ID state survives CS0 reset");
            check(write(0x04000000,0xf0,3),"reset CS2");
            check(!read(0x04000000),"CS2 missing array payload must stop");
            check(!write(0x02000000,0x40,3),"unmodeled programming command must stop");
            std::ostringstream report; board.report(report);
            check(report.str().find("\"rom_mapping_verified\":false")!=std::string::npos,"assumptions recorded");
            const std::string table = kind=="amd16" ? "2096" : "1860";
            check(report.str().find("\"table_offset\":"+table)!=std::string::npos,
                  "profile bank table must match the firmware flash-ID branch");
            std::cout<<"PASS boot profile "<<kind<<'\n';
        }
        BootProfile clocks(rom,rom.size(),"amd16",true);
        uint32_t clock_data=0; std::string clock_device;
        auto clock_read=[&](uint32_t a){return clocks.access({a,0,15,false},clock_data,clock_device);};
        auto clock_write=[&](uint32_t a,uint32_t v){return clocks.access({a,v,15,true},clock_data,clock_device);};
        check(!clock_read(0x0c120020),"clock status before control must stop");
        check(clock_write(0x0c120004,12),"observed clock command 12");
        check(clock_read(0x0c120020)&&clock_data==0x04000000,"explicit clock-ready hypothesis");
        check(!clock_read(0x0c120024),"unobserved clock register must stop");
        check(clock_write(0x0c120004,0x27)&&clock_write(0x0c120008,1),"second clock sequence");
        check(clock_read(0x0c120020)&&clock_data==0x08000000,"second clock-ready hypothesis");
        check(!clock_read(0x0c149000),"PLL reset bits must remain unknown");
        check(clock_write(0x0c149000,0x2210),"observed PLL control");
        check(clock_read(0x0c149000)&&clock_data==0x2211,"explicit PLL lock hypothesis");
        check(clock_write(0x0c120004,3),"third clock command");
        check(clock_read(0x0c120020)&&clock_data==0x08000000,"third clock-ready hypothesis");
        check(clock_write(0x0c120004,99)&&!clock_read(0x0c120020),"unknown clock sequence must stop");
        BootProfile no_clocks(rom,rom.size(),"amd16");
        check(no_clocks.access({0x0c120004,12,15,true},clock_data,clock_device),"clock control latch without assumptions");
        check(!no_clocks.access({0x0c120020,0,15,false},clock_data,clock_device),"ready status must require opt-in");
        std::cout<<"PASS explicit clock hypothesis boundaries\n";
        BootProfile lcd(rom,rom.size(),"amd16",true,true);
        auto lcd_access=[&](uint32_t a,uint32_t v,uint8_t select,bool write){
            return lcd.access({a,v,select,write},clock_data,clock_device);
        };
        check(!no_clocks.access({0x0c14f008,0,3,false},clock_data,clock_device),"LCD reset assumptions require opt-in");
        check(lcd_access(0x0c14f008,0,3,false)&&clock_data==0,"explicit LCD halfword reset hypothesis");
        check(!lcd_access(0x0c14f008,0,15,false),"LCD reset must not initialize adjacent halfword");
        check(lcd_access(0x0c15020c,0,12,false)&&clock_data==0,"upper-halfword reset hypothesis");
        check(!lcd_access(0x0c15020c,0,3,false),"neighboring GPIO reset remains unknown");
        check(!lcd_access(0x0c121204,0,15,false),"LCD status before enable must stop");
        check(!lcd_access(0x0c121204,99,15,true),"unknown LCD control must stop");
        check(lcd_access(0x0c121204,2,15,true)&&lcd_access(0x0c121204,1,15,true),"observed LCD reset-enable writes");
        check(lcd_access(0x0c121204,0,15,false)&&clock_data==4,"explicit LCD FIFO-ready hypothesis");
        check(!lcd_access(0x0c121208,0,15,false),"LCD data read must not invent a panel ID");
        check(!lcd_access(0x0c121208,0xaf,15,true),"LCD data needs a transfer header");
        check(!lcd_access(0x0c121200,0xdeadbeef,15,true),"unknown LCD header must stop");
        check(lcd_access(0x0c121200,0x49200000,15,true),"observed LCD wait header");
        check(lcd_access(0x0c121200,0,15,false)&&clock_data==0x40000000,"explicit LCD completion-bit hypothesis");
        check(lcd_access(0x0c121200,0x09200000,15,true)&&lcd_access(0x0c121208,0xaf,15,true),"LCD raw command transfer");
        check(!lcd_access(0x0c121200,0,15,false),"unmodeled header status must stop");
        check(!lcd_access(0x0c121208,0,3,true),"unobserved LCD transfer width must stop");
        check(!lcd_access(0x0c12120c,0,15,false),"neighboring LCD address remains unknown");
        std::cout<<"PASS explicit LCD probe boundaries\n";
        BootProfile io_probe(rom,rom.size(),"amd16",true,true,{},true);
        auto io_access=[&](uint32_t a,uint32_t v,uint8_t select,bool write){
            return io_probe.access({a,v,select,write},clock_data,clock_device);
        };
        check(io_access(0x0c150210,0,12,false)&&clock_data==0,"explicit boot GPIO reset hypothesis");
        check(!io_access(0x0c150210,0,3,false),"neighboring GPIO halfword stays unknown");
        check(io_access(0x0c150000,0,3,false)&&clock_data==0,"explicit cold reset-cause hypothesis");
        check(io_access(0x0c0047fc,0,14,false)&&clock_data==0,"only three cold-boot flag bytes initialized");
        check(!io_access(0x0c0047fc,0,1,false),"neighboring scratch flag byte stays unknown");
        check(io_access(0x0c0047fc,0x01000000,8,true),"observed byte flag write");
        check(io_access(0x0c0047fc,0,8,false)&&clock_data==0x01000000,"flag byte readback");
        check(!io_access(0x0c150420,0,12,false),"control-bus status before transaction must stop");
        check(!io_access(0x0c150420,99,3,true),"unknown control-bus configuration must stop");
        check(io_access(0x0c150420,0x10,3,true)&&io_access(0x0c150420,0x003b0000,12,true),"first observed control-bus command");
        check(!io_access(0x0c150420,0,12,false),"completion before payload must stop");
        check(io_access(0x0c150424,0x00610000,12,true),"first observed control-bus payload");
        check(io_access(0x0c150420,0,12,false)&&clock_data==0x043b0000,"explicit first control-bus completion");
        check(clock_device=="ideal_boot_cbus_status","ideal completion must be labeled");
        check(!io_access(0x0c150420,0x002b0000,12,true),"new command needs configuration write");
        check(io_access(0x0c150420,8,3,true)&&io_access(0x0c150420,0x002b0000,12,true),"second observed control-bus command");
        check(io_access(0x0c150424,0x00810000,12,true),"second observed control-bus payload");
        check(io_access(0x0c150420,0,12,false)&&clock_data==0x042b0000,"explicit second control-bus completion");
        check(!io_access(0x0c150424,0,12,false),"unmodeled control-bus data read stays unknown");
        check(io_access(0x0c150420,0xf,3,true)&&io_access(0x0c150420,0x012b0000,12,true),"read a written control-bus register");
        check(io_access(0x0c150420,0,12,false)&&clock_data==0x052b0000,"explicit read transaction completion");
        check(io_access(0x0c150424,0,12,false)&&clock_data==0x00810000,"control-bus read uses prior written value");
        check(io_access(0x0c150420,0xf,3,true)&&io_access(0x0c150420,0x01360000,12,true),"unknown initial register read command");
        check(io_access(0x0c150420,0,12,false),"transport can complete an unknown-value read");
        check(!io_access(0x0c150424,0,12,false),"unknown initial control-bus data must not be invented");
        check(!io_access(0x0c004720,0,3,false),"software shadow unknown until ROM initializes it");
        check(io_access(0x0c004720,0x1234,3,true),"software shadow halfword initialization");
        check(io_access(0x0c004720,0,3,false)&&clock_data==0x1234,"initialized software shadow read");
        check(!io_access(0x0c004720,0,15,false),"unwritten neighboring software shadow bytes stay unknown");
        check(io_access(0x0c004744,0xabcd,3,true),"last software shadow halfword");
        check(!io_access(0x0c004744,0,12,false),"gap before executable scratch remains unknown");
        check(io_access(0x0c150420,0xf,3,true)&&io_access(0x0c150420,0x003a0000,12,true),"watchdog shares ADC register number on write");
        check(io_access(0x0c150424,0xbeef0000,12,true),"watchdog payload cannot become ADC data");
        check(io_access(0x0c150420,0x8f,3,true)&&io_access(0x0c150420,0x02390000,12,true),"observed encoded conversion-control command");
        check(io_access(0x0c150424,0x68000000,12,true),"observed conversion-control payload");
        check(io_access(0x0c150420,0,12,false),"explicit encoded command completion");
        check(io_access(0x0c150420,0xf,3,true)&&io_access(0x0c150420,0x013a0000,12,true),"conversion result read command");
        check(!io_access(0x0c150424,0,12,false),"conversion result is not fabricated or aliased to control data");
        check(io_probe.reason()=="UEM ADC channel 6 input is not supplied","identify the unknown conversion input");
        check(!lcd.access({0x0c150210,0,12,false},clock_data,clock_device),"LCD probe alone must not initialize boot GPIO");
        std::cout<<"PASS explicit boot I/O probe boundaries\n";
        for (const auto& setup : std::map<uint32_t,uint32_t>{{0x0c120a04,2},{0x0c120a08,0},
             {0x0c120a10,0x0115b5c0},{0x0c120a18,0x0115b5c0},{0x0c120108,1}}) {
            check(io_access(setup.first,setup.second,15,true),"exact observed timer setup write captured");
            check(!io_access(setup.first,0,15,false),"timer write capture must not imply readback or ticking");
            check(!io_access(setup.first,setup.second,3,true),"unobserved timer write width rejected");
            check(!io_access(setup.first,setup.second^1,15,true),"unobserved timer setup value rejected");
        }
        check(!io_access(0x0c120a00,0,15,false),"timer counter remains unknown");
        check(!lcd.access({0x0c120a04,2,15,true},clock_data,clock_device),"timer setup requires boot-I/O opt-in");
        std::cout<<"PASS bounded timer setup writes without fabricated readback\n";
        BootProfile timer(rom,rom.size(),"amd16",true,true,{},true,{},5);
        auto timer_access=[&](uint32_t a,uint32_t v,bool write){
            return timer.access({a,v,15,write},clock_data,clock_device);
        };
        check(timer_access(0x0c120a04,2,true)&&timer_access(0x0c120a18,0x0115b5c0,true)&&
              timer_access(0x0c120108,1,true),"observed timer setup arms explicit IRQ delay");
        for (int i=0;i<4;++i) timer.tick();
        check(!timer.timer_irq()&&timer.has_scheduled_interrupt(),"timer does not fire early");
        timer.tick();
        check(timer.timer_irq(),"timer asserts IRQ after the explicit delay");
        check(timer_access(0x0c120a08,1,true)&&!timer.timer_irq(),"explicit IRQ acknowledgement deasserts event");
        check(!timer.has_scheduled_interrupt(),"acknowledged one-shot event is complete");
        check(timer_access(0x0c120a08,0,false)&&clock_data==1,"explicit timer flag read reflects handler acknowledgement");
        check(timer_access(0x0c120a18,0,true)&&timer_access(0x0c120a10,0,true)&&
              timer_access(0x0c120a04,0,true)&&timer_access(0x0c12010c,1,true),"observed IRQ cleanup writes");
        check(!timer.has_scheduled_interrupt(),"timer cleanup must not restart one-shot timer");
        check(timer_access(0x0c120a04,2,true) && timer_access(0x0c120a04,0,false) && clock_data==2,
              "explicit timer control readback after IRQ");
        check(timer_access(0x0c120a18,0x632ea,true),"capture exact kernel timer reload hypothesis");
        check(!timer_access(0x0c120a18,0x632eb,true),"unobserved timer reload remains unknown");
        check(!timer_access(0x0c120a18,0,false),"timer reload capture does not invent readback");
        check(timer.access({0x0c150100,0x80008000,3,true},clock_data,clock_device)&&
              clock_device=="assumed_irq_halfword_write","exact observed IRQ halfword write");
        check(!timer.access({0x0c150100,0,3,false},clock_data,clock_device),"IRQ halfword does not imply readback");
        check(timer.access({0x0c150420,0xf,3,true},clock_data,clock_device)&&
              timer.access({0x0c150420,0x013f0000,12,true},clock_data,clock_device),"observed IRQ handler's UEM read command");
        check(!timer.access({0x0c150424,0,12,false},clock_data,clock_device),"IRQ power-key/charger input remains unknown");
        check(timer.reason()=="UEM power-key/charger status is not supplied","IRQ unknown status is identified");
        std::cout<<"PASS explicit timer IRQ and unknown status boundaries\n";
        BootProfile power(rom,rom.size(),"amd16",true,true,{},true,{},5,0);
        check(power.access({0x0c150420,0xf,3,true},clock_data,clock_device)&&
              power.access({0x0c150420,0x013f0000,12,true},clock_data,clock_device)&&
              power.access({0x0c150424,0,12,false},clock_data,clock_device)&&clock_data==0&&
              clock_device=="assumed_uem_power_status", "explicit UEM status only");
        BootProfile status36(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0);
        check(status36.access({0x0c150420,0xf,3,true},clock_data,clock_device)&&
              status36.access({0x0c150420,0x01360000,12,true},clock_data,clock_device)&&
              status36.access({0x0c150424,0,12,false},clock_data,clock_device)&&clock_data==0&&
              clock_device=="assumed_uem_status36", "explicit UEM 0x36 initial status");
        BootProfile status35(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16);
        check(status35.access({0x0c150420,0xf,3,true},clock_data,clock_device)&&
              status35.access({0x0c150420,0x00350000,12,true},clock_data,clock_device)&&
              status35.access({0x0c150424,0x02000000,12,true},clock_data,clock_device)&&
              status35.access({0x0c150420,0xf,3,true},clock_data,clock_device)&&
              status35.access({0x0c150420,0x01350000,12,true},clock_data,clock_device)&&
              status35.access({0x0c150424,0,12,false},clock_data,clock_device)&&clock_data==0x00100000&&
              clock_device=="assumed_uem_status35", "UEM 0x35 directional status is independent of earlier write");
        BootProfile cbus27(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27);
        check(cbus27.access({0x0c150420,7,3,true},clock_data,clock_device) &&
              cbus27.access({0x0c150420,0x00270000,12,true},clock_data,clock_device) &&
              cbus27.access({0x0c150424,0x12340000,12,true},clock_data,clock_device),"opt-in CBUS register write");
        check(cbus27.access({0x0c150420,7,3,true},clock_data,clock_device) &&
              !cbus27.access({0x0c150420,0x01270000,12,true},clock_data,clock_device),"opt-in CBUS write must not permit register read");
        check(cbus27.access({0x0c150420,7,3,true},clock_data,clock_device) &&
              !cbus27.access({0x0c150420,0x00280000,12,true},clock_data,clock_device),"opt-in CBUS write must not permit another register");
        BootProfile ui(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true);
        check(!ui.access({0x0c150214,0,12,false},clock_data,clock_device),"GPIO 216 unknown before sequence");
        check(!ui.access({0x0c150218,0,12,false},clock_data,clock_device),"GPIO 21a unknown before sequence");
        check(!ui.access({0x0c150210,0,3,false},clock_data,clock_device),"GPIO low value unknown before IRQ sequence");
        check(!ui.access({0x0c120c10,0,15,false},clock_data,clock_device),"explicit probe unknown before setup");
        check(!ui.access({0x0c120c14,0,15,false},clock_data,clock_device),"system control unknown before PUP setup");
        check(!ui.access({0x0c14f008,0,12,false},clock_data,clock_device),"PUP high half unknown before CBUS setup");
        check(!ui.access({0x0c150010,0x80008000,12,true},clock_data,clock_device),"UIF write requires earlier IRQ and UEM setup");
        check(ui.access({0x0c120a04,2,15,true},clock_data,clock_device) && ui.access({0x0c120a18,0x0115b5c0,15,true},clock_data,clock_device) && ui.access({0x0c120108,1,15,true},clock_data,clock_device),"UIF test timer setup");
        for(int i=0;i<5;++i)ui.tick();
        check(ui.access({0x0c150420,7,3,true},clock_data,clock_device) && ui.access({0x0c150420,0x00270000,12,true},clock_data,clock_device) && ui.access({0x0c150424,0x12340000,12,true},clock_data,clock_device),"UIF test UEM setup");
        check(ui.access({0x0c150010,0x80008000,12,true},clock_data,clock_device) && clock_device=="assumed_uif_8000_write","exact UIF write allowed");
        check(ui.access({0x0c120108,0x02000000,15,true},clock_data,clock_device),"exact ICU bit25 write allowed after UIF");
        check(!ui.access({0x0c120108,0x04000000,15,true},clock_data,clock_device),"other ICU write remains unknown");
        check(ui.access({0x0c150210,0,3,false},clock_data,clock_device) && clock_data==0,"explicit GPIO low zero assumption");
        check(ui.access({0x0c150210,0x40,3,true},clock_data,clock_device) && ui.access({0x0c150210,0,3,false},clock_data,clock_device) && (clock_data & 0xffff)==0x40,"GPIO low reflects exact later write");
        check(ui.access({0x0c150218,0,12,false},clock_data,clock_device) && (clock_data>>16)==0,"explicit GPIO 21a zero assumption");
        check(!ui.access({0x0c150218,0,3,false},clock_data,clock_device),"adjacent GPIO remains unknown");
        check(ui.access({0x0c150214,0,12,false},clock_data,clock_device) && (clock_data>>16)==0,"explicit GPIO 216 zero assumption");
        check(ui.access({0x0c150214,0,3,false},clock_data,clock_device) && (clock_data & 0xffff)==0,"GPIO 214 low zero hypothesis");
        check(ui.access({0x0c150214,0x0180,3,true},clock_data,clock_device),"GPIO 214 low write");
        check(ui.access({0x0c150214,0,3,false},clock_data,clock_device) && (clock_data & 0xffff)==0x0180,"GPIO 214 low retains write");
        check(ui.access({0x0c150214,0,12,false},clock_data,clock_device) && (clock_data>>16)==0,"GPIO 216 high remains unchanged");
        check(ui.access({0x0c150100,0x00100010,12,true},clock_data,clock_device) && clock_device=="assumed_uif_0010_write","exact UIF102 write");
        check(ui.access({0x0c150420,15,3,true},clock_data,clock_device) && !ui.access({0x0c150420,0x01820000,12,true},clock_data,clock_device),"CBUS82 read requires earlier write");
        check(ui.access({0x0c150420,15,3,true},clock_data,clock_device) && ui.access({0x0c150420,0x00820000,12,true},clock_data,clock_device) && ui.access({0x0c150424,0x12340000,12,true},clock_data,clock_device),"explicit second CBUS device write");
        check(ui.access({0x0c150420,15,3,true},clock_data,clock_device) && ui.access({0x0c150420,0x01820000,12,true},clock_data,clock_device) && ui.access({0x0c150424,0,12,false},clock_data,clock_device) && clock_data==0x12340000 && clock_device=="assumed_cbus82_readback","explicit CBUS82 write readback");
        check(ui.access({0x0c150420,15,3,true},clock_data,clock_device) && !ui.access({0x0c150420,0x01830000,12,true},clock_data,clock_device),"other device reads remain unknown");
        check(ui.access({0x0c150420,15,3,true},clock_data,clock_device) && ui.access({0x0c150420,0x01800000,12,true},clock_data,clock_device) && ui.access({0x0c150424,0,12,false},clock_data,clock_device) && clock_data==0x04000000 && clock_device=="assumed_cbus80_input","explicit CBUS80 input");
        check(ui.access({0x0c150420,7,3,true},clock_data,clock_device) && ui.access({0x0c150420,0x018d0000,12,true},clock_data,clock_device) && ui.access({0x0c150424,0,12,false},clock_data,clock_device) && clock_data==0 && clock_device=="assumed_cbus8d_read","explicit CBUS8d initial zero");
        check(ui.access({0x0c150420,7,3,true},clock_data,clock_device) && ui.access({0x0c150420,0x008d0000,12,true},clock_data,clock_device) && ui.access({0x0c150424,0x120000,12,true},clock_data,clock_device),"CBUS8d write");
        check(ui.access({0x0c150420,7,3,true},clock_data,clock_device) && ui.access({0x0c150420,0x018d0000,12,true},clock_data,clock_device) && ui.access({0x0c150424,0,12,false},clock_data,clock_device) && clock_data==0x120000,"CBUS8d readback reflects write");
        check(ui.access({0x0c120148,0x4000,15,true},clock_data,clock_device) && clock_device=="assumed_icu46_write","exact ICU46 write allowed");
        check(!ui.access({0x0c150024,1,3,true},clock_data,clock_device),"GPIO24 requires previous SYSC74 write");
        check(ui.access({0x0c120074,3,15,true},clock_data,clock_device) && clock_device=="assumed_sysc74_write3","exact SYSC74 write");
        check(ui.access({0x0c1201c8,0x08000000,15,true},clock_data,clock_device),"ICU exact write");
        check(!ui.access({0x0c1201c8,0,15,false},clock_data,clock_device),"ICU read unknown");
        check(!ui.access({0x0c1201c8,0x04000000,15,true},clock_data,clock_device),"other ICU write unknown");
        check(ui.access({0x0c120050,7,15,true},clock_data,clock_device),"SYSC50 exact write");
        check(ui.access({0x0c120044,2,15,true},clock_data,clock_device),"SYSC44 exact write");
        check(!ui.access({0x0c120050,0,15,false},clock_data,clock_device),"SYSC50 read unknown");
        check(!ui.access({0x0c120050,6,15,true},clock_data,clock_device),"SYSC50 other value unknown");
        check(ui.access({0x0c120a10,0x632ea,15,true},clock_data,clock_device),"observed timer compare probe");
        check(!ui.access({0x0c120a10,0x632eb,15,true},clock_data,clock_device),"other timer values remain unknown");
        check(ui.access({0x0c150024,0x00010001,3,true},clock_data,clock_device),"GPIO24 exact write");
        check(ui.access({0x0c150028,0x00010001,3,true},clock_data,clock_device),"GPIO28 exact write");
        check(!ui.access({0x0c150024,0,3,false},clock_data,clock_device),"GPIO24 read unknown");
        check(!ui.access({0x0c150024,2,3,true},clock_data,clock_device),"GPIO24 other write unknown");
        check(!ui.access({0x0c120074,0,15,false},clock_data,clock_device),"SYSC74 read remains unknown");
        check(!ui.access({0x0c120074,4,15,true},clock_data,clock_device),"other SYSC74 values remain unknown");
        check(!ui.access({0x0c120074,3,3,true},clock_data,clock_device),"other SYSC74 widths remain unknown");
        check(ui.access({0x0c150204,0x00060000,12,true},clock_data,clock_device),"GPIO 206 extra observed write");
        check(ui.access({0x0c150204,0x00010001,12,true},clock_data,clock_device),"GPIO 206 epbus halfword-1 write accepted");
        check(!ui.access({0x0c150204,0,12,false},clock_data,clock_device),"GPIO 206 read remains unknown");
        check(!ui.access({0x0c150204,0x00070000,12,true},clock_data,clock_device),"GPIO 206 other values unknown");
        check(ui.access({0x0c14f004,0,3,false},clock_data,clock_device) && (clock_data&0xffff)==0,"PUP low zero hypothesis");
        check(ui.access({0x0c14f004,0x42,3,true},clock_data,clock_device),"PUP low write");
        check(ui.access({0x0c14f004,0,3,false},clock_data,clock_device) && (clock_data&0xffff)==0x42,"PUP low retained");
        check(ui.access({0x0c14f004,0,12,false},clock_data,clock_device) && (clock_data>>16)==0,"PUP upper independent");
        check(!ui.access({0x0c120148,0x8000,15,true},clock_data,clock_device) && !ui.access({0x0c120148,0,15,false},clock_data,clock_device),"other ICU46 accesses unknown");
        check(ui.access({0x0c14f008,0,12,false},clock_data,clock_device) && (clock_data>>16)==0,"explicit PUP high zero assumption");
        check(ui.access({0x0c14f008,0x00200020,12,true},clock_data,clock_device) && ui.access({0x0c14f008,0,12,false},clock_data,clock_device) && (clock_data>>16)==0x20,"PUP write retained");
        check(ui.access({0x0c120c14,0,15,false},clock_data,clock_device) && clock_data==0,"explicit system control zero");
        check(ui.access({0x0c120c14,0x40000,15,true},clock_data,clock_device) && ui.access({0x0c120c14,0,15,false},clock_data,clock_device) && clock_data==0x40000,"system control write retained");
        check(!ui.access({0x0c120c14,0,3,false},clock_data,clock_device),"system control unknown width rejected");
        check(ui.access({0x0c120c10,0,15,false},clock_data,clock_device) && clock_data==0 && clock_device=="assumed_register_probe","explicit register initial value");
        check(ui.access({0x0c120c10,0x123,15,true},clock_data,clock_device) && ui.access({0x0c120c10,0,15,false},clock_data,clock_device) && clock_data==0x123,"explicit register write retained");
        check(!ui.access({0x0c120c10,0,3,false},clock_data,clock_device) && !ui.access({0x0c120c0c,0,15,false},clock_data,clock_device),"other width and adjacent register unknown");
        check(ui.access({0x0c150204,0x01800180,12,true},clock_data,clock_device) && clock_device=="assumed_register_probe","explicit GPIO upper write");
        check(!ui.access({0x0c150204,0,12,false},clock_data,clock_device) && !ui.access({0x0c150204,0x01810181,12,true},clock_data,clock_device),"GPIO upper reads and different writes rejected");
        check(ui.access({0x0c150204,0x1234,3,true},clock_data,clock_device),"neighbor low half remains available");
        check(!ui.access({0x0c150100,0x00110011,12,true},clock_data,clock_device) && !ui.access({0x0c150100,0,12,false},clock_data,clock_device),"unknown UIF102 writes and reads rejected");
        check(!ui.access({0x0c150010,0x80008000,3,true},clock_data,clock_device) && !ui.access({0x0c150010,0x80008000,12,false},clock_data,clock_device) && !ui.access({0x0c150010,0x80018001,12,true},clock_data,clock_device),"UIF probe rejects other widths, reads, values");
        std::cout<<"PASS UI continuation probe boundaries\n";
        bool periodic_rejected=false;
        try { BootProfile bad_periodic(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{},true,true,true,true,true,true,true,false,true); }
        catch(const std::runtime_error&) { periodic_rejected=true; }
        check(periodic_rejected,"periodic hypothesis requires the ICU1c8 probe");
        BootProfile per(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true);
        auto per_write=[&](uint32_t a,uint32_t v,uint8_t select=15){
            return per.access({a,v,select,true},clock_data,clock_device);
        };
        auto per_read=[&](uint32_t a,uint8_t select=15){
            return per.access({a,0,select,false},clock_data,clock_device);
        };
        check(!per_read(0x0c120114),"ICU current read requires IRQ context under periodic build");
        check(per_write(0x0c120a04,2)&&per_write(0x0c120a18,0x0115b5c0)&&per_write(0x0c120108,1),"periodic test boot timer setup");
        for(int i=0;i<5;++i)per.tick();
        check(per.timer_irq(),"boot one-shot IRQ fires under the periodic build");
        check(per_write(0x0c120a08,1)&&!per.timer_irq(),"boot IRQ acknowledged");
        check(per_write(0x0c150420,7,3)&&per_write(0x0c150420,0x00270000,12)&&per_write(0x0c150424,0x12340000,12),"periodic test UEM setup");
        check(per_write(0x0c150010,0x80008000,12),"periodic test UIF write");
        check(per_write(0x0c120108,0x02000000),"periodic test ICU25 write");
        check(per_write(0x0c150420,15,3)&&per_write(0x0c150420,0x00820000,12)&&per_write(0x0c150424,0x12340000,12),"periodic test second CBUS device write");
        check(per_write(0x0c150420,7,3)&&per_write(0x0c150420,0x008d0000,12)&&per_write(0x0c150424,0x00120000,12),"periodic test CBUS8d write");
        check(per_write(0x0c120148,0x4000),"periodic test ICU46 write");
        check(per_write(0x0c120074,3),"periodic test SYSC74 write");
        check(!per.has_scheduled_interrupt(),"nothing scheduled before the kernel reload write");
        check(per_write(0x0c120a04,2),"kernel rewrites timer control");
        check(per_write(0x0c120a18,0x632ea),"kernel reload write arms the periodic hypothesis");
        check(per.has_scheduled_interrupt(),"periodic event is scheduled by the reload");
        for(uint32_t i=0;i<0x632ea;++i)per.tick();
        check(!per.timer_irq(),"stale-enable hypothesis keeps the early expiry undelivered");
        check(per_write(0x0c120a10,0x632ea),"observed kernel compare write");
        check(per_write(0x0c120a08,0)&&!per.timer_irq(),"kernel status clear acknowledges the stale expiry");
        check(per_write(0x0c120108,1),"kernel enable-set delivers later ticks");
        check(per_write(0x0c1201c8,0x08000000),"FIQ enable-set remains an exact sink");
        for(uint32_t i=0;i<0x632ea-1;++i)per.tick();
        check(!per.timer_irq(),"periodic event does not fire early");
        per.tick();
        check(per.timer_irq(),"periodic event fires after the reload period");
        check(per_read(0x0c120114)&&clock_data==1,"ICU current reports source 0 plus one");
        check(per_read(0x0c120154)&&clock_data==0,"secondary ICU bank is empty");
        check(per_read(0x0c120194)&&clock_data==0,"third ICU bank is empty");
        check(per_read(0x0c120a08)&&clock_data==1,"periodic expiry presents status bit");
        check(per_write(0x0c120a08,0)&&!per.timer_irq(),"ISR status write of zero acknowledges");
        check(per_read(0x0c120114)&&clock_data==0,"ICU current clears after acknowledgement");
        check(per_read(0x0c120a10)&&clock_data==0x632ea,"dispatcher entropy read returns the compare latch");
        check(per.has_scheduled_interrupt(),"periodic event reschedules after acknowledgement");
        for(uint32_t i=0;i<0x632ea;++i)per.tick();
        check(per.timer_irq(),"periodic event fires again without another arming write");
        check(per_write(0x0c120a08,0)&&!per.timer_irq()&&per.has_scheduled_interrupt(),"second acknowledgement keeps the schedule");
        check(!per_write(0x0c15053c,0xffff,3)&&!per_read(0x0c14d00c),"block 0x14d region unknown without its probe");
        std::cout<<"PASS explicit periodic timer hypothesis boundaries\n";
        bool block_rejected=false;
        try { BootProfile bad_block(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{},true,true,true,true,true,true,true,true,false,true); }
        catch(const std::runtime_error&) { block_rejected=true; }
        check(block_rejected,"block probe requires the periodic hypothesis");
        BootProfile blk(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true,true);
        auto blk_access=[&](uint32_t a,uint32_t v,uint8_t select,bool write){
            return blk.access({a,v,select,write},clock_data,clock_device);
        };
        check(!blk_access(0x0c15053c,0xffff,3,true),"block probe requires the earlier SYSC74 write");
        check(blk_access(0x0c120a04,2,15,true)&&blk_access(0x0c120a18,0x0115b5c0,15,true)&&blk_access(0x0c120108,1,15,true),"block test timer setup");
        for(int i=0;i<5;++i)blk.tick();
        check(blk_access(0x0c120a08,1,15,true),"block test boot ack");
        check(blk_access(0x0c150420,7,3,true)&&blk_access(0x0c150420,0x00270000,12,true)&&blk_access(0x0c150424,0x12340000,12,true),"block test UEM setup");
        check(blk_access(0x0c150010,0x80008000,12,true),"block test UIF write");
        check(blk_access(0x0c120108,0x02000000,15,true),"block test ICU25 write");
        check(blk_access(0x0c150420,15,3,true)&&blk_access(0x0c150420,0x00820000,12,true)&&blk_access(0x0c150424,0x12340000,12,true),"block test CBUS82 write");
        check(blk_access(0x0c150420,7,3,true)&&blk_access(0x0c150420,0x008d0000,12,true)&&blk_access(0x0c150424,0x00120000,12,true),"block test CBUS8d write");
        check(blk_access(0x0c120148,0x4000,15,true),"block test ICU46 write");
        check(blk_access(0x0c120074,3,15,true),"block test SYSC74 write");
        check(blk_access(0x0c15053c,0xffff,3,true)&&blk_access(0x0c15053c,0,3,false)&&(clock_data&0xffff)==0xffff,"block halfword write and readback");
        check(blk_access(0x0c150538,0x004c0000,12,true),"block high halfword write");
        check(blk_access(0x0c14d000,2,3,true)&&blk_access(0x0c14d000,0x03000000,12,true),"block mixed-width word writes");
        check(blk_access(0x0c14d000,0,15,false)&&clock_data==0x03000002,"block word readback combines halves");
        check(blk_access(0x0c14d00c,0,12,false)&&clock_data==0,"unwritten block register reads zero by explicit assumption");
        check(blk_access(0x0c14d010,0,15,false)&&clock_data==0,"block word register zero reset");
        check(!blk_access(0x0c14d014,0,15,false),"addresses beyond the probed block remain unknown");
        check(!blk_access(0x0de00000,0xc0,1,true),"debug output region unknown without its sink");
        std::cout<<"PASS explicit block 0x14d probe boundaries\n";
        bool debug_rejected=false;
        try { BootProfile bad_debug(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{},true,true,true,true,true,true,true,true,true,false,true); }
        catch(const std::runtime_error&) { debug_rejected=true; }
        check(debug_rejected,"debug sink requires the block probe");
        BootProfile dbg(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true,true,true);
        auto dbg_access=[&](uint32_t a,uint32_t v,uint8_t select,bool write){
            return dbg.access({a,v,select,write},clock_data,clock_device);
        };
        check(dbg_access(0x0de00000,0xc0,1,true)&&clock_device=="assumed_debug59_write","debug byte write accepted");
        check(dbg_access(0x0de00000,0x4800,2,true),"debug second-byte-lane write accepted");
        check(!dbg_access(0x0de00000,0,1,false),"debug output must not invent readback");
        check(!dbg_access(0x0de00000,0xffff,3,true),"debug halfword width remains unknown");
        check(dbg_access(0x0de00010,0x32,1,true),"sequential debug buffer bytes accepted");
        check(!dbg_access(0x0de01000,0xc0,1,true),"addresses beyond the debug window remain unknown");
        check(dbg_access(0x0dfd0000,0xe0,1,true)&&clock_device=="assumed_debug59_control","newline control write accepted");
        check(!dbg_access(0x0dfd0000,0,1,false),"control window must not invent readback");
        check(!dbg_access(0x0dfd0010,0xe0,1,true),"addresses beyond the control window remain unknown");
        check(dbg_access(0x0c150420,7,3,true)&&!dbg_access(0x0c150420,0x01240000,12,true),"CBUS24 read requires its explicit input");
        BootProfile rtc(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true,true,true,{{0x24,0x1234},{0x31,0}});
        auto rtc_access=[&](uint32_t a,uint32_t v,uint8_t select,bool write){
            return rtc.access({a,v,select,write},clock_data,clock_device);
        };
        check(rtc_access(0x0c150420,7,3,true)&&rtc_access(0x0c150420,0x01240000,12,true)&&rtc_access(0x0c150424,0,12,false)&&clock_data==0x12340000&&clock_device=="assumed_cbus_input","explicit CBUS24 input");
        check(rtc_access(0x0c150420,7,3,true)&&rtc_access(0x0c150420,0x01310000,12,true)&&rtc_access(0x0c150424,0,12,false)&&clock_data==0,"second explicit CBUS input");
        check(rtc_access(0x0c150420,7,3,true)&&!rtc_access(0x0c150420,0x01250000,12,true),"adjacent CBUS register remains unknown");
        check(rtc_access(0x0c150420,7,3,true)&&!rtc_access(0x0c150420,0x00240000,12,true),"CBUS24 write remains unknown");
        std::cout<<"PASS explicit debug output sink boundaries\n";
        bool stub_rejected=false;
        try { BootProfile bad_stub(rom,rom.size(),"amd16",true,true,{},true,{},0,-1,-1,-1,-1,-1,false,false,false,false,false,false,false,-1,false,false,false,false,{},false,false,false,false,false,false,false,false,false,false,false,{},true); }
        catch(const std::runtime_error&) { stub_rejected=true; }
        check(stub_rejected,"NOS stub requires the periodic timer experiment");
        BootProfile nos(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true,true,true,{{0x24,0}},true);
        uint32_t nos_data=0; std::string nos_device;
        check(!(nos.access({0x0009d284,0,15,false,true},nos_data,nos_device) && nos_device=="synthetic_nos_entry_stub"),"stub inactive before the kernel tick (digest hashes the ROM bytes)");
        check(nos.access({0x0c120a04,2,15,true,false},nos_data,nos_device)&&nos.access({0x0c120a18,0x0115b5c0,15,true,false},nos_data,nos_device),"arm the boot one-shot (stub fixture)");
        for(int i=0;i<6;++i) nos.tick();
        check(nos.access({0x0c120a18,0x632ea,15,true,false},nos_data,nos_device),"arm the kernel tick (stub fixture)");
        check(nos.access({0x0009d284,0,15,false,true},nos_data,nos_device) && nos_data==0xeaffff5d && nos_device=="synthetic_nos_entry_stub","entry trampoline branches into the init routine");
        check(nos.access({0x0009d000,0,15,false,true},nos_data,nos_device) && nos_data==0xe92d4030 && nos_device=="synthetic_nos_entry_stub","init routine served as code");
        check(nos.access({0x0009d000,0,15,false,false},nos_data,nos_device) && nos_data==0xe92d4030,"blob also served as data read (vtable/object pointers)");
        check(nos.access({0x0009d0cc,0,15,false,false},nos_data,nos_device) && nos_data==0x5149d184,"iface vtable +0xc points at ret0 VA");
        check(nos.access({0x0009d180,0,15,false,false},nos_data,nos_device) && nos_data==0x5149d0c0,"iface object word0 points at the vtable VA");
        check(!nos.access({0x0009d284,0,15,true,true},nos_data,nos_device),"blob writes are never accepted");
        check(!nos.access({0x0009e000,0,15,false,true},nos_data,nos_device) || nos_device!="synthetic_nos_entry_stub","fetches beyond the blob window are never served by the stub");
        std::cout<<"PASS synthetic NOS interface-provider blob boundaries\n";
        check(nos.access({0x0009e000,0,15,false,false},nos_data,nos_device) && nos_data==0x5149d0c0 && nos_device=="synthetic_nos_power_model","power-model vptr points at the vtable");
        check(nos.access({0x0009e010,0,15,false,false},nos_data,nos_device) && nos_data==0x5149e010,"power-model queue head self-links (empty)");
        check(nos.access({0x0009e018,0,15,false,false},nos_data,nos_device) && nos_data==4,"power-model queue iOffset is 4");
        check(nos.access({0x0009e008,0x1234,15,true,false},nos_data,nos_device)&&nos.access({0x0009e008,0,15,false,false},nos_data,nos_device)&&nos_data==0x1234,"power-model fields are writable by the kernel");
        check(nos.access({0x0009d108,0,15,false,false},nos_data,nos_device) && nos_data==0x5149d18c,"iface vtable +0x48 points at the zero-fill param reader");
        std::cout<<"PASS synthetic NOS power-model window boundaries\n";
        BootProfile kp(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true,true,true,{{0x24,0}},true,true);
        uint32_t kd=0; std::string kdev;
        check(kp.access({0x0c150404,0x1f00,3,true},kd,kdev)&&kdev=="assumed_keypad_gpio","keypad GPIO write accepted");
        check(kp.access({0x0c150404,0,3,false},kd,kdev)&&(kd&0xffff)==0x1f00,"keypad config reads back");
        check(kp.access({0x0c150400,0,3,false},kd,kdev)&&(kd&0xffff)==0,"unwritten keypad input reads zero (no keys)");
        check(kp.access({0x0c150408,0x0101,3,true},kd,kdev)&&kp.access({0x0c150408,0,3,false},kd,kdev)&&(kd&0xffff)==0x0101,"second keypad register latches");
        check(!kp.access({0x0c150500,0,3,false},kd,kdev)||kdev!="assumed_keypad_gpio","addresses beyond the pin-config pages are not keypad GPIO");
        std::cout<<"PASS keypad GPIO block boundaries\n";
        BootProfile icu(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true,true,true,{{0x24,0}},true,true,true);
        uint32_t id=0; std::string idev;
        check(icu.access({0x0c120188,0x40,15,true},id,idev)&&idev=="assumed_icu_bank","ICU bank2 enable-set accepted");
        check(icu.access({0x0c120188,0,15,false},id,idev)&&id==0x40,"ICU enable reads back set bits");
        check(icu.access({0x0c12018c,0x40,15,true},id,idev)&&icu.access({0x0c120188,0,15,false},id,idev)&&id==0,"ICU enable-clear clears the bit");
        check(icu.access({0x0c120190,0,15,false},id,idev)&&id==0,"ICU pending reads zero (no modelled source)");
        check(icu.access({0x0c120148,0x8,15,true},id,idev)&&icu.access({0x0c120148,0,15,false},id,idev)&&id==0x8,"ICU bank1 enable independent");
        std::cout<<"PASS ICU enable-bank boundaries\n";
        BootProfile tu(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true,true,true,{{0x24,0}},true,true,true,true);
        uint32_t td=0; std::string tdev;
        check(tu.access({0x0c120a24,1,15,true},td,tdev)&&tdev=="assumed_timer_unit","timer unit 1 control write accepted");
        check(tu.access({0x0c120a24,0,15,false},td,tdev)&&td==1,"timer unit 1 control reads back");
        check(tu.access({0x0c120a28,0,15,false},td,tdev)&&td==0,"timer unit 1 status reads not-expired");
        check(tu.access({0x0c120a44,2,15,true},td,tdev)&&tu.access({0x0c120a44,0,15,false},td,tdev)&&td==2,"timer unit 2 independent");
        std::cout<<"PASS timer units 1-4 boundaries\n";
        BootProfile cd(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true,true,true,{{0x24,0}},true,true,true,true,true);
        uint32_t cv=0; std::string cdev;
        auto cwr=[&](uint32_t a,uint32_t v){return cd.access({a,v,3,true},cv,cdev);};         // low-halfword write
        auto crd=[&](uint32_t a){return cd.access({a,0,3,false},cv,cdev);};                     // low-halfword read
        auto cwrh=[&](uint32_t word,uint32_t v){return cd.access({word,v<<16,12,true},cv,cdev);};// high-halfword write (byte word+2)
        // medint drives byte 0xaaa as the high halfword of word 0xaa8, byte 0x554 as the low halfword.
        check(cwr(0x02400000,0xf0)&&cdev=="cdrive_flash","C: reset accepted");
        check(cwr(0x02400000,0x60),"C: blind sector-lock 0x60 accepted");
        check(crd(0x02400000)&&(cv&0xffff)==0xffff,"C: erased array reads 0xFF");
        check(cwrh(0x02400aa8,0xaa)&&cwr(0x02400554,0x55)&&cwrh(0x02400aa8,0x90),"C: autoselect unlock");
        check(crd(0x02400004)&&(cv&0xffff)==0,"C: sector-protect verify reads 0 (unprotected)");
        check(cwr(0x02400000,0xf0),"C: autoselect exit");
        check(cwrh(0x02400aa8,0xaa)&&cwr(0x02400554,0x55)&&cwrh(0x02400aa8,0xa0)&&cwr(0x02401000,0x1234),"C: program a halfword");
        check(crd(0x02401000)&&(cv&0xffff)==0x1234,"C: programmed data reads back");
        check(cwrh(0x02400aa8,0xaa)&&cwr(0x02400554,0x55)&&cwrh(0x02400aa8,0x80)&&cwrh(0x02400aa8,0xaa)&&cwr(0x02400554,0x55)&&cwr(0x02401000,0x30),"C: sector erase command");
        check(crd(0x02401000)&&(cv&0xffff)==0x0008,"C: erase poll returns DQ3=1,DQ7=0");
        check(crd(0x02401000)&&(cv&0xffff)==0xffff,"C: erase completes to 0xFF");
        check(cd.access({0x02401000,0,15,false},cv,cdev)&&cv==0xffffffff&&cdev=="cdrive_flash","C: array word read of erased cells is 0xFFFFFFFF");
        check(cwrh(0x02400aa8,0xaa)&&cwr(0x02400554,0x55)&&cwrh(0x02400aa8,0xa0)&&cwr(0x02401000,0x1234)&&cd.access({0x02401000,0,15,false},cv,cdev)&&(cv&0xffff)==0x1234,"C: array word read returns a freshly programmed low cell");
        check(cd.access({0x02401000,0,2,false},cv,cdev)&&((cv>>8)&0xff)==0x12&&cdev=="cdrive_flash","C: array byte read serves byte lane 1 (seen at 1.5176e9)");
        check(cwrh(0x02400aa8,0xaa)&&cd.access({0x02400aa8,0,2,false},cv,cdev)==false,"C: byte read refused mid-command-sequence");
        check(cwrh(0x02400aa8,0xf0)||true,"C: reset after refusal");
        check(cd.access({0x02400540,6,15,true},cv,cdev)&&cdev=="cdrive_flash","C: bare word array write ignored (never a command cycle)");
        check(cd.access({0x02400540,0,15,false},cv,cdev)&&cv!=6,"C: array unchanged by the ignored write");
        check(cwrh(0x02400aa8,0xaa)&&cd.access({0x02400554,0x55005500,15,true},cv,cdev)==false,"C: word write refused mid-unlock");
        check(cwrh(0x02400aa8,0xf0)||true,"C: reset after mid-unlock refusal");
        std::cout<<"PASS C: drive flash boundaries\n";
        BootProfile u60(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true,true,true,{{0x24,0}},true,true,true,true,true,true);
        uint32_t ud=0; std::string udev;
        check(u60.access({0x0c1201c8,0x8,15,true},ud,udev)&&udev=="assumed_icu_mask","FIQ mask bank0 enable-set accepted");
        check(u60.access({0x0c1201c8,0,15,false},ud,udev)&&ud==0x8,"mask bank0 reads back set bit");
        check(u60.access({0x0c120a70,0x186,15,true},ud,udev)&&udev=="assumed_timer_unit","unit 0x60 compare write latches");
        check(u60.access({0x0c120a64,0,15,true},ud,udev),"unit 0x60 control stop accepted");
        for(int i=0;i<30000;++i) u60.tick();
        check(!u60.unit60_fiq(),"no FIQ while control is stopped");
        check(u60.access({0x0c120a64,2,15,true},ud,udev),"unit 0x60 control run (2) arms");
        for(int i=0;i<1999;++i) u60.tick();
        check(!u60.unit60_fiq(),"FIQ not raised before the assumed delay");
        u60.tick();
        check(u60.unit60_fiq()&&!u60.timer_irq(),"compare match raises FIQ, not IRQ");
        check(u60.access({0x0c1201d0,0,15,false},ud,udev)&&ud==0x8,"pending register reads bit 3 (pump entry 0x503851cc)");
        check(u60.access({0x0c1201d4,0,15,false},ud,udev)&&ud==4,"current register reads source+1 = 4");
        check(u60.access({0x0c120a68,0,15,true},ud,udev)&&!u60.unit60_fiq(),"counter rewrite clears the match (pump re-arm)");
        for(int i=0;i<2000;++i) u60.tick();
        check(u60.unit60_fiq(),"re-armed counter raises again");
        check(u60.access({0x0c120a64,0,15,true},ud,udev)&&!u60.unit60_fiq(),"control stop clears the match");
        check(u60.access({0x0c1201cc,0x8,15,true},ud,udev)&&u60.access({0x0c1201c8,0,15,false},ud,udev)&&ud==0,"enable-clear (+0x0c) disables source 3");
        check(u60.access({0x0c120a64,2,15,true},ud,udev),"control run with source disabled");
        for(int i=0;i<30000;++i) u60.tick();
        check(!u60.unit60_fiq(),"no FIQ delivery while source 3 is masked");
        check(u60.access({0x0c120208,0x10,15,true},ud,udev)&&u60.access({0x0c120208,0,15,false},ud,udev)&&ud==0x10,"mask bank1 independent");
        check(u60.access({0x0c120050,0,15,false},ud,udev)&&ud==0&&udev=="assumed_fiq_status","FIQ fast-status reads 0");
        check(u60.access({0x0c120050,2,15,true},ud,udev)&&udev=="assumed_fiq_status","FIQ fast-status ack write accepted");
        std::cout<<"PASS unit 0x60 FIQ pump timer\n";
        std::vector<uint8_t> img(0x100); for(size_t i=0;i<img.size();++i) img[i]=uint8_t(i);
        BootProfile ni(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true,true,false,{{0x24,0}},false,true,true,true,true,true,img,true,true);
        uint32_t nd=0; std::string ndev;
        check(!(ni.access({0x0009d280,0,15,false},nd,ndev)&&ndev=="nos_image_thc"),"NOS image inactive before the kernel tick arms (digest sees raw bytes)");
        check(ni.access({0x0c120a04,2,15,true},nd,ndev)&&ni.access({0x0c120a18,0x0115b5c0,15,true},nd,ndev),"arm the boot one-shot");
        for(int i=0;i<6;++i) ni.tick();
        check(!(ni.access({0x0009d280,0,15,false},nd,ndev)&&ndev=="nos_image_thc"),"NOS image still inactive after the one-shot (digest runs post-IRQ)");
        check(ni.access({0x0c120a18,0x632ea,15,true},nd,ndev),"arm the kernel periodic tick");
        check(ni.access({0x0009d280,0,15,false},nd,ndev)&&ndev=="nos_image_thc"&&nd==0x03020100,"NOS image word served at base");
        check(ni.access({0x0009d37c,0,15,false},nd,ndev)&&nd==0xfffefdfc,"NOS image last word served");
        check(!ni.access({0x0009d280,1,15,true},nd,ndev),"NOS image window rejects writes");
        bool both_rejected=false;
        try { BootProfile bad(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true,true,false,{{0x24,0}},true,true,true,true,true,true,img); }
        catch(const std::exception&) { both_rejected=true; }
        check(both_rejected,"nos-image and nos-entry-stub are mutually exclusive");
        std::cout<<"PASS real NOS image window boundaries\n";
        // UEM IRQ source-1 hypothesis: kernel-phase CBUS write to UEM 0x30
        // raises ICU source 1; current reads 2; bank0 +0x0c bit 1 acks.
        check(ni.access({0x0c120108,2,15,true},nd,ndev),"uem: enable ICU source 1");
        check(ni.access({0x0c150420,7,3,true},nd,ndev)&&ni.access({0x0c150420,0x00300000,12,true},nd,ndev)&&ni.access({0x0c150424,0x00400000,12,true},nd,ndev),"uem: power-up write 0x30=0x40");
        check(ni.timer_irq()&&ni.uem_irq(),"uem: source 1 pending after the 0x30 write");
        check(ni.access({0x0c120114,0,15,false},nd,ndev)&&nd==2,"uem: ICU current reads source+1 = 2");
        check(ni.access({0x0c12010c,2,15,true},nd,ndev)&&!ni.uem_irq(),"uem: bank0 clear bit1 acknowledges");
        std::cout<<"PASS UEM IRQ source-1 hypothesis\n";
        // Unit-1 settle timer: compare + control start counts to expiry and
        // raises the shared source-1 pending; status +0x08 reads 1 pending.
        check(ni.access({0x0c120108,2,15,true},nd,ndev),"unit1: re-enable source 1 (firmware re-arms after ack)");
        check(ni.access({0x0c120a30,100,15,true},nd,ndev)&&ni.access({0x0c120a24,1,15,true},nd,ndev),"unit1: compare 100 + start");
        for(int i=0;i<99;++i) ni.tick();
        check(!ni.uem_irq(),"unit1: no IRQ before compare");
        ni.tick();
        check(ni.uem_irq(),"unit1: source 1 raised at compare");
        check(ni.access({0x0c120a28,0,15,false},nd,ndev)&&nd==1,"unit1: status reads expired");
        check(ni.access({0x0c120114,0,15,false},nd,ndev)&&nd==2,"unit1: ICU current reads 2");
        check(ni.access({0x0c12010c,2,15,true},nd,ndev)&&!ni.uem_irq(),"unit1: bank0 bit1 ack clears");
        check(ni.access({0x0c120a24,0,15,true},nd,ndev),"unit1: stop accepted");
        for(int i=0;i<200;++i) ni.tick();
        check(!ni.uem_irq(),"unit1: stopped timer does not fire");
        std::cout<<"PASS unit-1 settle timer source-1\n";
        check(ni.access({0x0c120614,0x280,15,true},nd,ndev)&&ndev=="assumed_epbus_clk","epbus clk-block write latches");
        check(ni.access({0x0c120614,0,15,false},nd,ndev)&&nd==0x280,"epbus clk-block reads back");
        check(ni.access({0x0c120610,0,15,false},nd,ndev)&&nd==0&&ndev=="assumed_epbus_clk","epbus clk-block unwritten reads 0");
        check(ni.access({0x0c1206fc,0x1234,15,true},nd,ndev)&&ni.access({0x0c1206fc,0,15,false},nd,ndev)&&nd==0x1234,"epbus clk-block covers whole 0x1206xx");
        check(!ni.access({0x0c120700,0,15,false},nd,ndev)||ndev!="assumed_epbus_clk","block ends at 0x1206ff");
        std::cout<<"PASS epbus clock-block latches\n";
        // Board checkpoint v2 roundtrip: mutate state across the newer device
        // models, save, load into a fresh identically-configured board, and
        // check the observable state survived.
        {
            auto mk=[&]{ return BootProfile(rom,rom.size(),"amd16",true,true,{},true,{},5,0,0,16,0x27,0x82,true,true,true,true,true,true,true,0x400,true,true,true,true,{{0x0c120c10,{0,15}},{0x0c150204,{0,12}},{0x0c14f004,{0,12}}},true,true,true,true,true,true,true,true,true,true,true,{{0x24,0}},true,true,true,true,true,true); };
            BootProfile a=mk(); uint32_t d=0; std::string dev;
            check(a.access({0x0c1201c8,0x8,15,true},d,dev),"ckpt: mask set");
            check(a.access({0x0c120a64,2,15,true},d,dev),"ckpt: unit60 arm");
            for(int i=0;i<2000;++i) a.tick();
            check(a.unit60_fiq(),"ckpt: unit60 pending before save");
            check(a.access({0x02400000,0xf0,3,true},d,dev)&&dev=="cdrive_flash","ckpt: touch C: overlay");
            check(a.access({0x0c150404,0x1f00,3,true},d,dev),"ckpt: keypad write");
            std::stringstream snap; a.save_state(snap);
            BootProfile b=mk();
            b.load_state(snap);
            check(b.unit60_fiq(),"ckpt: unit60 pending restored");
            check(b.access({0x0c1201c8,0,15,false},d,dev)&&d==0x8,"ckpt: mask restored");
            check(b.access({0x0c150404,0,3,false},d,dev)&&(d&0xffff)==0x1f00,"ckpt: keypad restored");
            check(b.access({0x02400000,0,3,false},d,dev)&&(d&0xffff)==0xffff,"ckpt: C: overlay restored erased");
            std::cout<<"PASS board checkpoint v2 roundtrip\n";
        }
        const auto analog_inputs = BootProfile::parse_adc_inputs("6=0x200,12=800");
        BootProfile analog(rom,rom.size(),"amd16",true,true,{},true,analog_inputs);
        auto analog_access=[&](uint32_t a,uint32_t v,uint8_t select,bool write){
            return analog.access({a,v,select,write},clock_data,clock_device);
        };
        auto analog_command=[&](uint16_t config,uint16_t command){
            return analog_access(0x0c150420,config,3,true) &&
                   analog_access(0x0c150420,uint32_t(command)<<16,12,true);
        };
        check(analog_command(15,0x13a)&&!analog_access(0x0c150424,0,12,false),
              "configured sample still requires conversion start");
        check(analog.reason()=="UEM ADC read before known conversion","unstarted ADC guard");
        check(analog_command(15,0x3a)&&analog_access(0x0c150424,0xbeef0000,12,true),
              "watchdog write before explicit ADC sample");
        check(analog_command(0x8f,0x239)&&analog_access(0x0c150424,0x68000000,12,true),
              "start configured channel six");
        check(analog_command(15,0x13a)&&analog_access(0x0c150424,0,12,false)&&clock_data==0x02000000,
              "ADC returns selected analog input rather than watchdog or control payload");
        check(clock_device=="assumed_uem_adc_data","analog data labeled as assumption");
        check(!analog_access(0x0c150424,0,3,false),"ADC data cannot initialize neighboring halfword");
        check(analog_command(0x8f,0x239)&&analog_access(0x0c150424,0xc8000000,12,true),
              "select a different configured channel");
        check(analog_command(15,0x13a)&&analog_access(0x0c150424,0,12,false)&&clock_data==0x03200000,
              "ADC samples are independent by channel");
        check(analog_command(0x8f,0x239)&&analog_access(0x0c150424,0x18000000,12,true),
              "select an unconfigured channel");
        check(analog_command(15,0x13a)&&!analog_access(0x0c150424,0,12,false),
              "unconfigured channel cannot reuse an earlier conversion sample");
        check(analog.reason()=="UEM ADC channel 1 input is not supplied","unknown channel identified");
        for(const std::string option : {"6=-1","6=1024","14=1","6=1,6=2","6=0x","6=1,","6=1,,7=2"}) {
            bool rejected=false;
            try { BootProfile::parse_adc_inputs(option); } catch(const std::exception&) { rejected=true; }
            check(rejected,"invalid ADC configuration rejected: "+option);
        }
        bool adc_requires_probe=false;
        try { BootProfile bad(rom,rom.size(),"amd16",true,true,{},false,analog_inputs); }
        catch(const std::runtime_error&) { adc_requires_probe=true; }
        check(adc_requires_probe,"ADC inputs cannot silently enable boot I/O");
        std::cout<<"PASS explicit UEM ADC inputs and directional/unknown-channel boundaries\n";
        auto tail_rom=fixture();
        put(tail_rom,0x830+8+4,0x10000);
        put(tail_rom,0x830+8+16+4,0x10000);
        std::vector<uint8_t> tail(32,0xa5);
        tail[0]=0x11; tail[1]=0x22; tail[2]=0x33; tail[3]=0x44;
        BootProfile extended(tail_rom,tail_rom.size(),"amd16",false,false,tail);
        check(extended.access({0x1000,0,15,false},clock_data,clock_device)&&clock_data==0x44332211,
              "explicit reconstructed tail word");
        check(clock_device=="reconstructed_flash_tail","reconstructed reads must be labeled");
        check(extended.access({0x101c,0,15,false},clock_data,clock_device)&&clock_data==0xa5a5a5a5,
              "last reconstructed tail word");
        check(!extended.access({0x1020,0,15,false},clock_data,clock_device),"tail end remains unknown");
        check(!extended.access({0x02400000,0,15,false},clock_data,clock_device),"tail must not create user flash backing");
        BootProfile no_tail(tail_rom,tail_rom.size(),"amd16");
        check(!no_tail.access({0x1000,0,15,false},clock_data,clock_device),"default missing payload still stops");
        bool bad_tail=false;
        try { BootProfile bad(tail_rom,tail_rom.size(),"amd16",false,false,std::vector<uint8_t>(3)); }
        catch(const std::runtime_error&) { bad_tail=true; }
        check(bad_tail,"misaligned reconstructed tail rejected");
        bad_tail=false;
        try { BootProfile bad(tail_rom,tail_rom.size(),"amd16",false,false,std::vector<uint8_t>(0x20000)); }
        catch(const std::runtime_error&) { bad_tail=true; }
        check(bad_tail,"oversized reconstructed tail rejected");
        std::cout<<"PASS reconstructed tail boundaries and default stop\n";
        auto sparse=fixture(); put(sparse,0x830+8+16+4,0x2000);
        BootProfile sparse_board(sparse,sparse.size(),"amd16");
        uint32_t data=0; std::string device;
        check(!sparse_board.access({0x02001000,0,15,false},data,device),
              "missing ROM dump bytes must stop instead of supplying invented data");
        std::cout<<"PASS missing ROM payload rejection\n";
        auto bad=fixture(); put(bad,0x830,1000);
        bool rejected=false;
        try { BootProfile board(bad,bad.size(),"amd16"); }
        catch(const std::runtime_error&) { rejected=true; }
        check(rejected,"malformed memory-bank table rejected");
        std::cout<<"PASS malformed profile rejection\n";
        return 0;
    } catch(const std::exception& e) { std::cerr<<"FAIL "<<e.what()<<'\n'; return 1; }
}
