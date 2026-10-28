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
            check(write(0x0c0047e0,0xaabbccdd),"last observed scratch word");
            check(!write(0x0c0047e4,0),"scratch end boundary");
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
                check(read(base)&&data==0x227e0001,"schematic chip manufacturer/device");
                check(read(base+0x1c)&&data==0x22002202,"AMD extended device identity");
                check(read(base+4,12)&&data==0x00430000,"AMD handshake option");
                check(!read(base+4,3),"unknown lock state must not be invented");
                check(read(0x02000000)&&data==0x55667788,"chip ID state must not leak to CS1");
            }
            check(write(0,0xf0,3),"reset CS0 only");
            check(read(0)&&data==0x11223344,"CS0 array restored");
            check(read(0x04000000)&&data==0x227e0001,"CS2 ID state survives CS0 reset");
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
        check(!timer_access(0x0c120a08,0,false),"IRQ does not fabricate timer read semantics");
        check(timer.access({0x0c150420,0xf,3,true},clock_data,clock_device)&&
              timer.access({0x0c150420,0x013f0000,12,true},clock_data,clock_device),"observed IRQ handler's UEM read command");
        check(!timer.access({0x0c150424,0,12,false},clock_data,clock_device),"IRQ power-key/charger input remains unknown");
        check(timer.reason()=="UEM power-key/charger status is not supplied","IRQ unknown status is identified");
        std::cout<<"PASS explicit timer IRQ and unknown status boundaries\n";
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
