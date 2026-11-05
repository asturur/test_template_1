#include "Vngage_cpu_sim.h"
#include "boot_profile.h"
#include "descramble_model.h"
#include <verilated.h>
#include <verilated_save.h>
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cerrno>
#include <cstring>
#include <deque>
#include <set>
#include <sstream>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
constexpr uint32_t ram_base = 0x80000000;
constexpr uint32_t rom_alias = 0x50000000;
constexpr uint32_t mailbox_base = 0xf0000000;
constexpr uint32_t success = 0x50415353;

std::string trace_text(const VlWide<32>& packed) {
    std::string text;
    for (int word = 31; word >= 0; --word)
        for (int byte = 3; byte >= 0; --byte) {
            const char c = (packed[word] >> (8 * byte)) & 0xff;
            if (c) text += c;
        }
    const auto start = text.find_first_not_of(' ');
    return start == std::string::npos ? "" : text.substr(start);
}

struct Request {
    uint32_t address = 0, data = 0;
    uint8_t select = 0;
    bool write = false, code = false;
};

int run(int argc, char** argv) {
    if (argc < 8) throw std::runtime_error(
        "usage: ngage_cpu_sim ROM MAX_CYCLES LATENCY TRACE BUS CP15 RESULT [BOOT_PROFILE [ideal-clocks] [lcd-probe] [boot-io-probe] [+ngage-compact-trace] [rom-extension=PATH] [uem-adc=CHANNEL=VALUE,...]]");
    std::ifstream input(argv[1], std::ios::binary);
    if (!input) throw std::runtime_error("cannot open ROM");
    std::vector<uint8_t> rom{std::istreambuf_iterator<char>(input), {}};
    if (rom.empty() || rom.size() > 64 * 1024 * 1024)
        throw std::runtime_error("ROM must contain 1 byte to 64 MiB");
    const size_t rom_bytes = rom.size();
    // Flash read-side descrambler (authentic path): the disk ROM is the ORIGINAL
    // scrambled service file; the CPU reads the window [0xa000,0x2b3000)
    // descrambled, so apply the solved 16-bit GF(2) formulas here before the
    // board serves it. Equivalent to an inline read-path descrambler (the HDL
    // core does it per-read); makes the firmware's own MD5 self-check pass
    // natively (no digest rewrite) and serves the real NOS (no stub).
    for (int i = 9; i < argc; ++i) if (std::string(argv[i]) == "descramble-window") {
        const uint32_t lo = 0xa000, hi = 0x2b3000;
        if (rom.size() >= hi) for (uint32_t pa = lo; pa < hi; pa += 2) {
            const uint32_t C = rom[pa] | (rom[pa+1] << 8), A = pa;
            uint32_t P = 0;
            for (int b = 0; b < 16; ++b) {
                const DescrBit& d = kDescr[b];
                unsigned v = d.cst;
                for (uint32_t m = d.cmask & C; m; m &= m-1) v ^= 1;
                for (uint32_t m = d.amask & A; m; m &= m-1) v ^= 1;
                if (d.p0j >= 0) v ^= ((A>>d.p0j)&1) & ((A>>d.p0k)&1);
                if (d.p1j >= 0) v ^= ((A>>d.p1j)&1) & ((A>>d.p1k)&1);
                P |= (v & 1) << b;
            }
            rom[pa] = P & 0xff; rom[pa+1] = (P >> 8) & 0xff;
        }
    }
    const std::string profile_name = argc >= 9 ? argv[8] : "none";
    bool simif_no_atr = false;
    bool ideal_clocks = false, lcd_probe = false, compact_trace = false, boot_io_probe = false, allow_uif_8000 = false, allow_icu25 = false, gpio210_low_zero = false, gpio21a_zero = false, gpio216_zero = false, gpio214_low_zero = false, pupf004_low_zero = false, gpio206_extra_write = false, sysc74_write3 = false, gpio24_28_write1 = false, timer_compare_probe = false, sysc50_44_probe = false, icu1c8_probe = false, timer_periodic = false, block14d_probe = false, debug59_sink = false, nos_entry_stub = false, keypad_gpio = false, icu_banks = false, timer_units = false, cdrive_flash = false, unit60_irq3 = false, nos_periph4000 = false, uem_irq_source1 = false, module_trace = false, epbus_clkblk = false, uif102_write = false, cbus82_readback = false, cbus8d_zero = false, icu46_write = false, pupf00a_zero = false, sysc0c14_zero = false;
    std::vector<uint8_t> rom_tail, nos_image, cdrive_image, nos_iat_region;
    std::map<uint32_t,uint32_t> nos_iat;
    std::map<unsigned,unsigned> adc_inputs, adc_extra;
    int uem_power_extra = -1;  // post-signature override, see uem-adc-extra
    std::map<uint32_t,std::pair<uint32_t,uint8_t>> probe_regs;
    std::map<int,int> cbus_inputs;
    uint64_t timer_irq_delay = 0, checkpoint_at = 0, checkpoint_every = 0, win_lo = 0, win_hi = 0;
    std::set<uint32_t> pc_log;   // pc-log=0xADDR: always log retirements at these PCs
    std::string pmm_image_path;   // pmm-image=FILE: seeded 64KB PMM sector
    int64_t watch_addr = -1;     // watch-addr=PA: log every bus write to this word
    int64_t watch_word = -1;     // watch-word=0xVAL: tag full-word RAM writes of VAL
    bool rom_va_dump = false;    // rom-va-dump: rom_ is the real-phone VA snapshot (THC dump)
    std::map<uint32_t,uint32_t> rom_va_map;  // rom-va-map: phys page -> dump offset (real captured map)
    std::string checkpoint_path, restore_path;
    int uem_power_status = -1, uem_status36 = -1, uem_status35 = -1, extra_cbus_write = -1, extra_cbus_write2 = -1, cbus80_input = -1;
    for (int i = 9; i < argc; ++i) {
        if (std::string(argv[i]) == "ideal-clocks") ideal_clocks = true;
        else if (std::string(argv[i]) == "lcd-probe") lcd_probe = true;
        else if (std::string(argv[i]) == "boot-io-probe") boot_io_probe = true;
        else if (std::string(argv[i]) == "uif-write-8000") allow_uif_8000 = true;
        else if (std::string(argv[i]) == "icu-write-25") allow_icu25 = true;
        else if (std::string(argv[i]) == "gpio210-low-zero") gpio210_low_zero = true;
        else if (std::string(argv[i]) == "gpio21a-zero") gpio21a_zero = true;
        else if (std::string(argv[i]) == "gpio216-zero") gpio216_zero = true;
        else if (std::string(argv[i]) == "gpio214-low-zero") gpio214_low_zero = true;
        else if (std::string(argv[i]) == "pupf004-low-zero") pupf004_low_zero = true;
        else if (std::string(argv[i]) == "gpio206-extra-write") gpio206_extra_write = true;
        else if (std::string(argv[i]) == "sysc74-write3") sysc74_write3 = true;
        else if (std::string(argv[i]) == "gpio24-28-write1") gpio24_28_write1 = true;
        else if (std::string(argv[i]) == "timer-compare-probe") timer_compare_probe = true;
        else if (std::string(argv[i]) == "sysc50-44-probe") sysc50_44_probe = true;
        else if (std::string(argv[i]) == "icu1c8-probe") icu1c8_probe = true;
        else if (std::string(argv[i]) == "timer-periodic") timer_periodic = true;
        else if (std::string(argv[i]) == "block14d-probe") block14d_probe = true;
        else if (std::string(argv[i]) == "nos-periph-4000") nos_periph4000 = true;
        else if (std::string(argv[i]) == "debug59-sink") debug59_sink = true;
        else if (std::string(argv[i]) == "nos-entry-stub") nos_entry_stub = true;
        else if (std::string(argv[i]) == "simif-no-atr") simif_no_atr = true;
        else if (std::string(argv[i]) == "keypad-gpio") keypad_gpio = true;
        else if (std::string(argv[i]) == "icu-banks") icu_banks = true;
        else if (std::string(argv[i]) == "timer-units") timer_units = true;
        else if (std::string(argv[i]) == "cdrive-flash") cdrive_flash = true;
        else if (std::string(argv[i]) == "timer-unit60-irq3") unit60_irq3 = true;
        else if (std::string(argv[i]) == "uem-irq-source1") uem_irq_source1 = true;
        else if (std::string(argv[i]) == "module-trace") module_trace = true;
        else if (std::string(argv[i]) == "epbus-clkblk") epbus_clkblk = true;
        else if (std::string(argv[i]) == "uif102-write") uif102_write = true;
        else if (std::string(argv[i]) == "cbus82-readback") cbus82_readback = true;
        else if (std::string(argv[i]) == "cbus8d-zero") cbus8d_zero = true;
        else if (std::string(argv[i]) == "icu46-write") icu46_write = true;
        else if (std::string(argv[i]) == "pupf00a-zero") pupf00a_zero = true;
        else if (std::string(argv[i]) == "sysc0c14-zero") sysc0c14_zero = true;
        else if (std::string(argv[i]) == "+ngage-compact-trace") compact_trace = true;
        else if (std::string(argv[i]).rfind("checkpoint-at=", 0) == 0) checkpoint_at = std::stoull(std::string(argv[i]).substr(14));
        else if (std::string(argv[i]).rfind("checkpoint-every=", 0) == 0) checkpoint_every = std::stoull(std::string(argv[i]).substr(17));
        else if (std::string(argv[i]).rfind("pc-log=", 0) == 0) pc_log.insert(uint32_t(std::stoul(std::string(argv[i]).substr(7), nullptr, 0)));
        else if (std::string(argv[i]).rfind("pmm-image=", 0) == 0) pmm_image_path = std::string(argv[i]).substr(10);
        else if (std::string(argv[i]).rfind("watch-addr=", 0) == 0) watch_addr = int64_t(std::stoul(std::string(argv[i]).substr(11), nullptr, 0));
        else if (std::string(argv[i]).rfind("watch-word=", 0) == 0) watch_word = int64_t(std::stoul(std::string(argv[i]).substr(11), nullptr, 0));
        else if (std::string(argv[i]) == "rom-va-dump") rom_va_dump = true;
        else if (std::string(argv[i]) == "descramble-window") {}  // handled before board construction (ROM descramble)
        else if (std::string(argv[i]).rfind("rom-va-map=", 0) == 0) {
            std::ifstream f(std::string(argv[i]).substr(11), std::ios::binary);
            if (!f) throw std::runtime_error("cannot open rom-va-map");
            uint32_t page, off;
            while (f.read(reinterpret_cast<char*>(&page),4) && f.read(reinterpret_cast<char*>(&off),4)) rom_va_map[page]=off;
            if (rom_va_map.empty()) throw std::runtime_error("empty rom-va-map");
        }
        else if (std::string(argv[i]).rfind("win-trace=", 0) == 0) {
            const std::string v = std::string(argv[i]).substr(10); const size_t c = v.find(':');
            win_lo = std::stoull(v.substr(0,c)); win_hi = std::stoull(v.substr(c+1));
        }
        else if (std::string(argv[i]).rfind("checkpoint=", 0) == 0) checkpoint_path = std::string(argv[i]).substr(11);
        else if (std::string(argv[i]).rfind("restore=", 0) == 0) restore_path = std::string(argv[i]).substr(8);
        else if (std::string(argv[i]).rfind("timer-irq-delay=", 0) == 0) {
            if (timer_irq_delay) throw std::runtime_error("duplicate timer IRQ delay");
            const std::string value = std::string(argv[i]).substr(16);
            size_t consumed = 0;
            timer_irq_delay = std::stoull(value,&consumed,10);
            if (!timer_irq_delay || timer_irq_delay > 1000000000ull || consumed != value.size())
                throw std::runtime_error("timer IRQ delay must be 1..1000000000 cycles");
        } else if (std::string(argv[i]).rfind("uem-power-status=", 0) == 0) {
            if (uem_power_status >= 0) throw std::runtime_error("duplicate UEM power status");
            size_t n = 0; const auto v = std::string(argv[i]).substr(17);
            const auto value = std::stoul(v, &n, 0);
            if (n != v.size() || value > 65535) throw std::runtime_error("invalid UEM power status");
            uem_power_status = int(value);
        } else if (std::string(argv[i]).rfind("uem-status36=", 0) == 0) {
            if (uem_status36 >= 0) throw std::runtime_error("duplicate UEM status36");
            size_t n = 0; const auto v = std::string(argv[i]).substr(13);
            const auto value = std::stoul(v, &n, 0);
            if (n != v.size() || value > 65535) throw std::runtime_error("invalid UEM status36");
            uem_status36 = int(value);
        } else if (std::string(argv[i]).rfind("uem-status35=", 0) == 0) {
            if (uem_status35 >= 0) throw std::runtime_error("duplicate UEM status35");
            size_t n = 0; const auto v = std::string(argv[i]).substr(13);
            const auto value = std::stoul(v, &n, 0);
            if (n != v.size() || value > 65535) throw std::runtime_error("invalid UEM status35");
            uem_status35 = int(value);
        } else if (std::string(argv[i]).rfind("cbus-write-allow=", 0) == 0) {
            if (extra_cbus_write >= 0) throw std::runtime_error("duplicate CBUS write option");
            size_t n = 0; const auto v = std::string(argv[i]).substr(17); const auto value = std::stoul(v,&n,0);
            if (n != v.size() || value > 63) throw std::runtime_error("invalid CBUS write option");
            extra_cbus_write = int(value);
        } else if (std::string(argv[i]).rfind("cbus-write-allow2=", 0) == 0) {
            if (extra_cbus_write2 >= 0) throw std::runtime_error("duplicate second CBUS write option");
            size_t n = 0; const auto v = std::string(argv[i]).substr(18); const auto value = std::stoul(v,&n,0);
            if (n != v.size() || value > 255) throw std::runtime_error("invalid second CBUS write option");
            extra_cbus_write2 = int(value);
        } else if (std::string(argv[i]).rfind("cbus80-input=", 0) == 0) {
            if (cbus80_input >= 0) throw std::runtime_error("duplicate CBUS80 input");
            size_t n=0;const auto v=std::string(argv[i]).substr(13);const auto value=std::stoul(v,&n,0);
            if (n!=v.size() || value>65535) throw std::runtime_error("invalid CBUS80 input");
            cbus80_input=int(value);
        } else if (std::string(argv[i]).rfind("cbus-input=", 0) == 0) {
            const std::string v=std::string(argv[i]).substr(11); const size_t eq=v.find('=');
            if (eq==std::string::npos) throw std::runtime_error("invalid CBUS input");
            size_t a=0,b=0; const auto reg=std::stoul(v.substr(0,eq),&a,0); const auto value=std::stoul(v.substr(eq+1),&b,0);
            if (a!=eq || b!=v.size()-eq-1 || reg>0xff || value>65535) throw std::runtime_error("invalid CBUS input");
            if (!cbus_inputs.emplace(int(reg),int(value)).second) throw std::runtime_error("duplicate CBUS input");
        } else if (std::string(argv[i]).rfind("probe-register=", 0) == 0) {
            const std::string v=std::string(argv[i]).substr(15); size_t a=v.find(':'), b=v.find(':',a+1);
            if (a==std::string::npos || b==std::string::npos || v.find(':',b+1)!=std::string::npos) throw std::runtime_error("register probe format ADDRESS:VALUE:SELECT");
            auto number=[](const std::string& x){size_t n=0;auto u=std::stoull(x,&n,0);if(n!=x.size() || u>0xffffffffull)throw std::runtime_error("invalid register probe number");return uint32_t(u);};
            auto address=number(v.substr(0,a)),value=number(v.substr(a+1,b-a-1)),select=number(v.substr(b+1));
            if (select>15 || !probe_regs.emplace(address,std::make_pair(value,uint8_t(select))).second) throw std::runtime_error("invalid or duplicate register probe");
        } else if (std::string(argv[i]).rfind("uem-adc=", 0) == 0) {
            if (!adc_inputs.empty()) throw std::runtime_error("duplicate ADC input option");
            adc_inputs = BootProfile::parse_adc_inputs(std::string(argv[i]).substr(8));
        } else if (std::string(argv[i]).rfind("uem-power-status-extra=", 0) == 0) {
            // Power-on-reason override merged AFTER the checkpoint signature
            // (environment, not machine state): UEM reg 0x3f value. Bit 0 =
            // power key held (hypothesis); with 0 the NOS powers itself off
            // at ~2.38e9 (observed deliberate shutdown, no panic dump).
            uem_power_extra = int(std::stoul(std::string(argv[i]).substr(23), nullptr, 0));
        } else if (std::string(argv[i]).rfind("uem-adc-extra=", 0) == 0) {
            // Extra analog inputs merged AFTER the checkpoint signature is
            // computed: ADC values are environment (battery temp/size/...),
            // not machine state, so adding channels must not invalidate
            // existing checkpoints. Values are still in provenance.json.
            if (!adc_extra.empty()) throw std::runtime_error("duplicate extra ADC input option");
            adc_extra = BootProfile::parse_adc_inputs(std::string(argv[i]).substr(14));
        } else if (std::string(argv[i]).rfind("cdrive-image=", 0) == 0) {
            std::ifstream img(std::string(argv[i]).substr(13), std::ios::binary);
            if (!img) throw std::runtime_error("cannot open C: image");
            cdrive_image.assign(std::istreambuf_iterator<char>(img), {});
            if (cdrive_image.empty()) throw std::runtime_error("C: image is empty");
        } else if (std::string(argv[i]).rfind("nos-iat-region=", 0) == 0) {
            std::ifstream f(std::string(argv[i]).substr(15), std::ios::binary);
            if (!f) throw std::runtime_error("cannot open NOS IAT region file");
            nos_iat_region.assign(std::istreambuf_iterator<char>(f), {});
            if (nos_iat_region.size() != 0x725c0 - 0x6e030) throw std::runtime_error("NOS IAT region size mismatch");
        } else if (std::string(argv[i]).rfind("nos-iat=", 0) == 0) {
            const std::string spec = std::string(argv[i]).substr(8);
            const auto eq = spec.find('=');
            if (eq == std::string::npos) throw std::runtime_error("nos-iat needs ADDR=VALUE");
            const uint32_t a = std::stoul(spec.substr(0,eq),nullptr,0), v = std::stoul(spec.substr(eq+1),nullptr,0);
            if (a & 3) throw std::runtime_error("nos-iat address must be word-aligned");
            nos_iat[a] = v;
        } else if (std::string(argv[i]).rfind("nos-image=", 0) == 0) {
            std::ifstream img(std::string(argv[i]).substr(10), std::ios::binary);
            if (!img) throw std::runtime_error("cannot open NOS image");
            nos_image.assign(std::istreambuf_iterator<char>(img), {});
            if (nos_image.empty()) throw std::runtime_error("NOS image is empty");
        } else if (std::string(argv[i]).rfind("rom-extension=", 0) == 0) {
            std::ifstream tail(std::string(argv[i]).substr(14), std::ios::binary);
            if (!tail) throw std::runtime_error("cannot open reconstructed ROM tail");
            rom_tail.assign(std::istreambuf_iterator<char>(tail), {});
            if (rom_tail.empty()) throw std::runtime_error("reconstructed ROM tail is empty");
        } else throw std::runtime_error("unknown board option");
    }
    std::unique_ptr<BootProfile> board;
    std::map<unsigned,unsigned> adc_all = adc_inputs;
    for (const auto& e : adc_extra) adc_all[e.first] = e.second;  // signature never sees these
    const int uem_power_eff = uem_power_extra >= 0 ? uem_power_extra : uem_power_status;
    if (profile_name != "none") board = std::make_unique<BootProfile>(rom, rom_bytes, profile_name, ideal_clocks, lcd_probe, rom_tail, boot_io_probe, adc_all, timer_irq_delay, uem_power_eff, uem_status36, uem_status35, extra_cbus_write, extra_cbus_write2, allow_uif_8000, allow_icu25, gpio210_low_zero, gpio21a_zero, gpio216_zero, uif102_write, cbus82_readback, cbus80_input, cbus8d_zero, icu46_write, pupf00a_zero, sysc0c14_zero, probe_regs, gpio214_low_zero, pupf004_low_zero, gpio206_extra_write, sysc74_write3, gpio24_28_write1, timer_compare_probe, sysc50_44_probe, icu1c8_probe, timer_periodic, block14d_probe, debug59_sink, cbus_inputs, nos_entry_stub, keypad_gpio, icu_banks, timer_units, cdrive_flash, unit60_irq3, nos_image, uem_irq_source1, epbus_clkblk, cdrive_image, nos_iat, nos_periph4000);
    if (board) board->set_simif_no_atr(simif_no_atr);
    if (board && !nos_iat_region.empty()) board->set_nos_iat_region(std::move(nos_iat_region));
    if (board && watch_word >= 0) board->set_watch_word(uint32_t(watch_word));
    if (board && !pmm_image_path.empty()) {
        std::ifstream f(pmm_image_path, std::ios::binary);
        std::vector<uint8_t> img((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
        if (img.size() != 0x10000) throw std::runtime_error("pmm-image must be 65536 bytes");
        board->set_pmm_image(std::move(img));
    }
    if (board && rom_va_dump) board->set_rom_va_dump();
    if (board && !rom_va_map.empty()) board->set_phys2dump(std::move(rom_va_map));
    rom.resize(std::max<size_t>(65536, (rom.size() + 63) & ~size_t(63)), 0);
    std::vector<uint8_t> ram(4 * 1024 * 1024, 0);
    std::array<uint32_t, 16> mailbox{};
    const uint64_t limit = std::stoull(argv[2]);
    const unsigned latency = std::stoul(argv[3]);
    if (!limit || latency > 1000) throw std::runtime_error("invalid cycle/latency limit");
    const std::string result_path(argv[7]);
    const std::string bus_path(argv[5]);
    const auto slash = bus_path.find_last_of('/');
    const std::string memory_tail_path = (slash == std::string::npos ? "" : bus_path.substr(0,slash+1)) + "memory-tail.tsv";
    std::ofstream instruction_log(argv[4]), bus_log(argv[5]), cp15_log(argv[6]);
    std::ofstream live_lcd((slash == std::string::npos ? "" : bus_path.substr(0,slash+1)) + "live-lcd.bin", std::ios::binary);
    std::ofstream full_window_log((slash == std::string::npos ? "" : bus_path.substr(0,slash+1)) + "window-bus.tsv");
    full_window_log << "cycle\toperation\taddress\tbyte_enable\tdata\tchannel\tdevice\n";
    const std::string branch_tail_path = (slash == std::string::npos ? "" : bus_path.substr(0,slash+1)) + "branch-tail.tsv";
    std::ofstream result(result_path), memory_tail_log(memory_tail_path), branch_log(branch_tail_path);
    if (!result) throw std::runtime_error("cannot create result JSON " + result_path + ": " + std::strerror(errno));
    if (!memory_tail_log) throw std::runtime_error("cannot create memory tail " + memory_tail_path + ": " + std::strerror(errno));
    if (!instruction_log || !bus_log || !cp15_log || !branch_log) throw std::runtime_error("cannot create logs");
    instruction_log << "cycle\tretired_instruction\n";
    bus_log << "cycle\toperation\taddress\tbyte_enable\tdata\tchannel\tdevice\n";
    memory_tail_log << "cycle\toperation\taddress\tbyte_enable\tdata\tdevice\n";
    branch_log << "cycle\tpc\ttarget\tprediction\tstate\tredirect\tfetch_pc\n";
    cp15_log << "cycle\toperation\topcode1\tcrn\tcrm\topcode2\tregister\tvalue\n";
    auto context = std::make_unique<VerilatedContext>();
    context->commandArgs(argc, argv);
    context->randReset(0);
    auto cpu = std::make_unique<Vngage_cpu_sim>(context.get());
    cpu->i_clk = 0;
    cpu->i_reset = 1;
    cpu->i_irq = 0;
    cpu->i_fiq = 0;
    cpu->i_wb_ack = 0;
    cpu->i_wb_err = 0;
    cpu->i_wb_dat = 0;
#ifdef NGAGE_HDL_BOARD
    cpu->i_bus_commit = 0;
    cpu->i_cfg_lcd = lcd_probe;
    cpu->i_cfg_keypad = keypad_gpio;
#endif
    for (unsigned n = 0; n < 20; ++n) {
        cpu->i_clk = 0; cpu->eval(); context->timeInc(1);
        cpu->i_clk = 1; cpu->eval(); context->timeInc(1);
    }
    cpu->i_reset = 0;
    bool pending = false, complete = false, previous_cp15_done = false;
    Request request;
    unsigned wait = 0;
    uint64_t cycle = 0, transactions = 0, retired = 0, cp15_transactions = 0;
    std::string status = "timeout", last_trace, blocked_reason;
    uint32_t blocked_address = 0;
    uint64_t fetch_faults = 0;
#ifdef NGAGE_HDL_BOARD
    uint64_t hdl_claims = 0;
#endif
    bool mmu_seen = false;
    unsigned self_loop_count = 0;
    std::string self_loop_pc;
    std::deque<std::pair<uint64_t,std::string>> retirement_tail;
    std::deque<std::string> memory_tail, branch_tail;
    std::deque<std::string> l1_log;
    if (((checkpoint_at || checkpoint_every) && checkpoint_path.empty()) || (!checkpoint_at && !checkpoint_every && !checkpoint_path.empty())) throw std::runtime_error("invalid checkpoint options");
    std::deque<std::string> rolling_checkpoints;  // rotating every-N snapshots, keep last 10
    uint64_t checkpoint_signature=1469598103934665603ull;
    auto sig_byte=[&](uint8_t x){checkpoint_signature=(checkpoint_signature ^ x)*1099511628211ull;};
    for (size_t i=0;i<rom_bytes;++i) sig_byte(rom[i]);
    for (auto x:rom_tail) sig_byte(x);
    for (char x:profile_name) sig_byte(x);
    auto sig_raw=[&](const auto& v){const auto* p=reinterpret_cast<const uint8_t*>(&v);for(size_t i=0;i<sizeof(v);++i)sig_byte(p[i]);};
    sig_raw(ideal_clocks);sig_raw(lcd_probe);sig_raw(boot_io_probe);sig_raw(timer_irq_delay);
    sig_raw(uem_power_status);sig_raw(uem_status36);sig_raw(uem_status35);sig_raw(latency);
    for(const auto& e:adc_inputs){sig_raw(e.first);sig_raw(e.second);}
    auto save_host = [&](std::ostream& out) {
        auto put=[&](const auto& value){out.write(reinterpret_cast<const char*>(&value),sizeof(value));};
        const uint32_t version=0x484f0002; put(version); put(checkpoint_signature); put(cycle); put(transactions); put(retired); put(cp15_transactions);
        put(fetch_faults); put(pending); put(complete); put(previous_cp15_done); put(request); put(wait); put(mmu_seen); put(self_loop_count);
        put(mailbox); uint64_t n=ram.size(); put(n); out.write(reinterpret_cast<const char*>(ram.data()),n);
        n=self_loop_pc.size(); put(n); out.write(self_loop_pc.data(),n);
        const bool has_board=bool(board); put(has_board); if (board) board->save_state(out);
        if(!out) throw std::runtime_error("host checkpoint write failed");
    };
    auto load_host = [&](std::istream& in) {
        auto get=[&](auto& value){in.read(reinterpret_cast<char*>(&value),sizeof(value));};
        uint32_t version=0;get(version);if(version!=0x484f0002)throw std::runtime_error("host checkpoint version mismatch");
        uint64_t signature=0;get(signature);if(signature!=checkpoint_signature)throw std::runtime_error("checkpoint input or configuration mismatch");
        get(cycle);get(transactions);get(retired);get(cp15_transactions);get(fetch_faults);get(pending);get(complete);
        get(previous_cp15_done);get(request);get(wait);get(mmu_seen);get(self_loop_count);get(mailbox);
        uint64_t n=0;get(n);if(n!=ram.size())throw std::runtime_error("host RAM size mismatch");in.read(reinterpret_cast<char*>(ram.data()),n);
        get(n);if(n>128)throw std::runtime_error("invalid loop PC length");self_loop_pc.resize(n);in.read(self_loop_pc.data(),n);
        bool has_board=false;get(has_board);if(has_board!=bool(board))throw std::runtime_error("checkpoint board mismatch");if(board)board->load_state(in);
        if(!in)throw std::runtime_error("host checkpoint truncated"); ++cycle;
    };
    if (!restore_path.empty()) {
        VerilatedRestore in; in.open((restore_path+".cpu").c_str()); in >> context.get() >> *cpu; in.close();
        std::ifstream host(restore_path+".host",std::ios::binary); if(!host)throw std::runtime_error("checkpoint host unavailable"); load_host(host);
        std::cout << "RESTORED " << restore_path << " next cycle " << cycle << std::endl;
    }

    for (; cycle < limit && !context->gotFinish(); ++cycle) {
        cpu->i_clk = 0;
        cpu->i_irq = board && board->timer_irq();
        cpu->i_fiq = board && board->unit60_fiq();
        cpu->i_wb_ack = 0;
        cpu->i_wb_err = 0;
#ifdef NGAGE_HDL_BOARD
        cpu->i_bus_commit = 0;   // one-shot: high only across the serving posedge
#endif
        cpu->eval();
        const bool active = cpu->o_wb_cyc && cpu->o_wb_stb;
        if (pending && (!active || cpu->o_wb_adr != request.address ||
            bool(cpu->o_wb_we) != request.write || bool(cpu->o_wb_code) != request.code || cpu->o_wb_sel != request.select ||
            (request.write && cpu->o_wb_dat != request.data))) {
            status = "bus_protocol_error";
            break;
        }
        if (active && !pending) {
            request = {cpu->o_wb_adr, cpu->o_wb_dat,
                       uint8_t(cpu->o_wb_sel), bool(cpu->o_wb_we), bool(cpu->o_wb_code)};
            wait = latency ? transactions % (latency + 1) : 0;
            pending = true;
        }
        bool board_wait = false;
#ifdef NGAGE_HDL_BOARD
        // Block-RAM-backed board reads need one extra cycle before dout is valid.
        board_wait = pending && wait == 0 && cpu->o_board_claim && !cpu->o_board_ready;
#endif
        if (pending && wait == 0 && !board_wait) {
            const uint32_t address = request.address & ~uint32_t(3);
            uint32_t data = 0;
            uint8_t* memory = nullptr;
            bool readonly = false, bus_fault = false;
            std::string device;
#ifdef NGAGE_HDL_BOARD
            // HDL board first; the C++ model still runs below as a lockstep
            // shadow oracle and any divergence stops the run (hdl-migration.md).
            const bool hdl_claim = cpu->o_board_claim;
            const bool hdl_unmodeled = cpu->o_board_unmodeled;
            const uint32_t hdl_data = cpu->o_board_dout;
            if (hdl_claim && hdl_unmodeled) {
                status = "unmapped_access";
                blocked_address = request.address;
                blocked_reason = "HDL board: claimed but unmodeled access";
                bus_log << std::dec << cycle << "\tHDL_UNMODELED\t0x" << std::hex
                        << request.address << "\t0x" << unsigned(request.select)
                        << "\t0x" << request.data << "\tdata\thdl_board\n";
                break;
            }
#endif
            if (board) {
                if (!board->access({request.address, request.data, request.select, request.write, request.code}, data, device)) {
                    if (request.code && !request.write) {
                        bus_fault = true;
                        device = "unknown_fetch";
                    } else {
                        status = "unmapped_access";
                        blocked_address = request.address;
                        blocked_reason = board->reason();
                        bus_log << std::dec << cycle << '\t' << (request.write ? "UNMODELED_WRITE" : "UNMODELED_READ")
                                << "\t0x" << std::hex << request.address << "\t0x"
                                << unsigned(request.select) << "\t0x" << request.data
                                << "\tdata\t" << device << '\n';
                        break;
                    }
                }
                if (request.write && request.address == 0x0c120348 && request.data == 2)
                    board->dump_live_lcd(live_lcd, cycle);
#ifdef NGAGE_HDL_BOARD
                // Lockstep shadow compare: the C++ oracle served above; the
                // HDL board must have claimed the same addresses and, for
                // reads, produced the same data.
                if (hdl_claim) {
                    const uint32_t lanes = (request.select & 1 ? 0xffu : 0) | (request.select & 2 ? 0xff00u : 0) |
                                         (request.select & 4 ? 0xff0000u : 0) | (request.select & 8 ? 0xff000000u : 0);
                    // Unselected byte lanes are don't-care on the bus.
                    if (!request.write && !bus_fault && ((data ^ hdl_data) & lanes)) {
                        status = "hdl_divergence";
                        blocked_address = request.address;
                        blocked_reason = "HDL read data differs from C++ oracle";
                        bus_log << std::dec << cycle << "\tHDL_DIVERGENCE\t0x" << std::hex
                                << request.address << "\t0x" << unsigned(request.select)
                                << "\t0x" << hdl_data << "\tvs_0x" << data << "\thdl_board\n";
                        break;
                    }
                    ++hdl_claims;
                } else {
                    // Mirror of the HDL claim map: anything here must have
                    // been claimed, or the two models disagree on ownership.
                    const uint32_t off12 = address & 0xfff;
                    const bool hdl_owned =
                        device == "lcd_probe_transport" ||
                        (device == "assumed_keypad_gpio" && (address >> 12) == 0x0c150 &&
                         ((off12 >= 0x400 && off12 < 0x420) ||
                          (off12 >= 0x428 && off12 < 0x538) ||
                          (off12 >= 0x540 && off12 < 0x600)));
                    if (hdl_owned) {
                        status = "hdl_divergence";
                        blocked_address = request.address;
                        blocked_reason = "C++ oracle served an address the HDL board owns but did not claim";
                        break;
                    }
                }
#endif
            } else if (uint64_t(address) + 4 <= rom.size()) {
                memory = rom.data() + address; readonly = true; device = "diagnostic_rom";
            } else if (address >= rom_alias && uint64_t(address - rom_alias) + 4 <= rom.size()) {
                memory = rom.data() + (address - rom_alias); readonly = true; device = "diagnostic_rom_alias";
            } else if (address >= ram_base && uint64_t(address - ram_base) + 4 <= ram.size()) {
                memory = ram.data() + (address - ram_base); device = "diagnostic_ram";
            } else if (address >= mailbox_base && address < mailbox_base + mailbox.size() * 4) {
                device = "diagnostic_mailbox";
                const unsigned slot = (address - mailbox_base) / 4;
                if (request.write) {
                    for (unsigned byte = 0; byte < 4; ++byte)
                        if (request.select & (1 << byte)) {
                            const uint32_t mask = 0xffu << (byte * 8);
                            mailbox[slot] = (mailbox[slot] & ~mask) | (request.data & mask);
                        }
                    if (slot == 0) complete = true;
                }
                data = mailbox[slot];
            } else if (request.code && !request.write) {
                bus_fault = true;
                device = "unknown_fetch";
            } else {
                status = "unmapped_access";
                blocked_address = request.address;
                bus_log << std::dec << cycle << '\t' << (request.write ? "UNMAPPED_WRITE" : "UNMAPPED_READ")
                        << "\t0x" << std::hex << request.address << "\t0x"
                        << unsigned(request.select) << "\t0x" << request.data << '\n';
                break;
            }
            if (memory) {
                if (readonly && request.write) {
                    status = "write_to_rom"; blocked_address = request.address; break;
                }
                for (unsigned byte = 0; byte < 4; ++byte) {
                    if (request.write && (request.select & (1 << byte)))
                        memory[byte] = (request.data >> (8 * byte)) & 0xff;
                    data |= uint32_t(memory[byte]) << (8 * byte);
                }
            }
            if (watch_addr >= 0 && request.write && address == uint32_t(watch_addr))
                bus_log << std::dec << cycle << "\tWATCH_WRITE\t0x" << std::hex << request.address << "\t0x" << unsigned(request.select) << "\t0x" << request.data << "\tdata\twatch_addr\n";
            if (!compact_trace || bus_fault || device == "flash_command" || device == "flash_identify" ||
                device == "observed_boot_latch" || device == "ideal_clock_status" ||
                device == "ideal_pll_status" || device == "lcd_probe_transport" || device == "reconstructed_flash_tail" || device == "ideal_boot_cbus_status" || device == "boot_cbus_latched_data" || device == "assumed_uem_adc_data" || device == "assumed_icu1c8_write" || device == "assumed_sysc50_44_write" || device == "assumed_gpio24_28_write1" || device == "assumed_sysc74_write3" || device == "assumed_register_probe" || device == "assumed_cbus82_readback" || device == "assumed_cbus80_input" || device == "assumed_cbus_input" || device == "assumed_cbus8d_read" || device == "assumed_uem_power_status" || device == "assumed_uem_status36" || device == "assumed_uem_status35" || device == "assumed_timer_status" || device == "assumed_icu_current" || device == "assumed_block14d_probe" || device == "assumed_debug59_write" || device == "assumed_debug59_control" || device == "synthetic_nos_entry_stub" || device == "synthetic_nos_power_model" || device == "assumed_keypad_gpio" || device == "assumed_icu_bank" || device == "assumed_timer_unit" || device == "cdrive_flash" || device == "assumed_irq_halfword_write" || device == "assumed_uif_8000_write" || device == "assumed_uif_0010_write" || device == "assumed_icu46_write" || device == "timer_setup_write" || device == "watched_word_write" || device == "assumed_nos_periph4000" || device == "assumed_asic_rom_stub" || device == "factory_device_id" || device == "flash_pmm_status" || device == "flash_pmm_overlay" || device == "pmm_sector_erased" || device == "pmm_seed_image" || device == "thc_dump_flash_array" || device == "thc_dump_ppm_tail_erased")
            bus_log << std::dec << cycle << '\t' << (bus_fault ? "FETCH_ERROR" : request.write ? "WRITE" : "READ")
                    << "\t0x" << std::hex << std::setw(8) << std::setfill('0') << request.address
                    << "\t0x" << unsigned(request.select) << "\t0x"
                    << std::setw(8) << (request.write ? request.data : data)
                    << '\t' << (request.code ? "code" : "data") << '\t' << device << '\n';
            if (win_lo && cycle >= win_lo && cycle <= win_hi) {
                full_window_log << std::dec << cycle << '\t' << (request.write ? "WRITE" : "READ")
                    << "\t0x" << std::hex << request.address << "\t0x" << unsigned(request.select)
                    << "\t0x" << (request.write ? request.data : data) << '\t' << (request.code ? "code" : "data") << '\t' << device << '\n';
            }
            if (mmu_seen && !request.code) {
                std::ostringstream line;
                line << std::dec << cycle << '\t' << (request.write ? "WRITE" : "READ")
                     << "\t0x" << std::hex << request.address << "\t0x" << unsigned(request.select)
                     << "\t0x" << (request.write ? request.data : data) << '\t' << device;
                memory_tail.push_back(line.str());
                if (memory_tail.size() > 32768) memory_tail.pop_front();
            }
            // Diagnostic probe: record every write into the L1 translation
            // table window (TTB PA 0x0a074000, 16 KiB) with the covered VA.
            if (request.write && request.address >= 0x0a074000u && request.address < 0x0a078000u && l1_log.size() < 65536) {
                std::ostringstream line;
                line << std::dec << cycle << "\t0x" << std::hex << request.address
                     << "\tVA_0x" << ((request.address - 0x0a074000u) / 4) * 0x100000u
                     << "\t0x" << request.data;
                l1_log.push_back(line.str());
            }
            cpu->i_wb_dat = bus_fault ? 0 : data;
            cpu->i_wb_ack = !bus_fault;
            cpu->i_wb_err = bus_fault;
#ifdef NGAGE_HDL_BOARD
            if (hdl_claim && !request.write) cpu->i_wb_dat = hdl_data;
            cpu->i_bus_commit = !bus_fault;   // HDL board registers commit with this ack
#endif
            fetch_faults += bus_fault;
            pending = false;
            ++transactions;
        } else if (pending && !board_wait) --wait;
        cpu->eval();
        if (mmu_seen && cpu->o_branch_valid) {
            std::ostringstream line;
            line << std::dec << cycle << "\t0x" << std::hex << cpu->o_branch_pc
                 << "\t0x" << cpu->o_branch_target << "\t0x" << cpu->o_branch_prediction
                 << '\t' << unsigned(cpu->o_branch_state) << '\t' << unsigned(cpu->o_branch_redirect)
                 << "\t0x" << cpu->o_fetch_pc;
            branch_tail.push_back(line.str());
            if (branch_tail.size() > 4096) branch_tail.pop_front();
        }
        context->timeInc(1);
        cpu->i_clk = 1;
        cpu->eval();
        context->timeInc(1);
        if (board) board->tick();
        if (cpu->o_trace_valid) {
            const std::string trace = trace_text(cpu->o_trace);
            // module-trace: one log line per transition between ROM binaries
            // (offsets from the ROM file table; build-specific, experimental).
            if (module_trace && cpu->o_trace_uop_last && trace.size() > 8) {
                static const struct { uint32_t base; const char* name; } mod_tab[] = {
                    {0x320f9c,"ekern"},{0x348750,"ecust"},{0x34ab20,"ecomm"},{0x34d340,"ramdrive"},
                    {0x34de20,"rtc"},{0x3504a0,"nosstarter"},{0x3505a0,"pnmsg"},{0x350ac0,"isimsg"},
                    {0x36b480,"phonet"},{0x36ce90,"mid36c"},{0x381d30,"cbus"},{0x383e80,"helper"},
                    {0x384990,"medint"},{0x388330,"ELocal"},{0x3971e0,"ELocl"},{0x397d20,"EUser"},
                    {0x3cc5d0,"Hal"},{0x3cdb60,"EFile"},{0x3ddad0,"EFSrv"},{0x3e40c0,"ERam"},
                    {0x3ed5b0,"EKTran"},{0x3ee860,"EStart"},{0x3efad0,"EDISP"},{0x3f0a50,"btldd"},
                    {0x3f3110,"sit"},{0x3f37c0,"audio"},{0x3f3de0,"epbus"},{0x3fd7f0,"medmmc"},
                    {0x3feff0,"lesterdrv"},{0x3ff710,"GD1DRV"},{0x4001e0,"lcd.ldd"},{0x406c90,"LCDDEV"},
                    {0x407270,"scdv"},{0x4184d0,"product_info"},{0x418dd0,"ekeyb"},{0x41b1e0,"end"}};
                static int last_mod = -2;
                uint32_t pc = 0;
                if (sscanf(trace.c_str(), "%x", &pc) == 1) {
                    int m = -1;
                    if (pc >= 0x5149d000 && pc <= 0x5149e100) m = 100;       // nos window
                    else if (pc >= 0x50320f9c && pc < 0x5041b1e0) {
                        for (unsigned k = 0; k < sizeof(mod_tab)/sizeof(*mod_tab); ++k)
                            if (pc - 0x50000000 >= mod_tab[k].base) m = k; else break;
                    }
                    // user-side ROM binaries (servers, TSYs, apps): bucket by
                    // 64KB so their execution windows appear in the timeline
                    // (names via romsyms offline).
                    else if (pc >= 0x5041b1e0 && pc < 0x51500000) m = 200 + int((pc - 0x50400000) >> 16);
                    if (m != last_mod && m >= 0) {
                        instruction_log << std::dec << cycle << "\tMOD\t";
                        if (m == 100) instruction_log << "nos-window";
                        else if (m >= 200) instruction_log << "user+" << std::hex << ((m - 200) << 16) << std::dec;
                        else instruction_log << mod_tab[m].name;
                        instruction_log << "\t" << std::hex << pc << std::dec << '\n';
                        last_mod = m;
                    } else if (m >= 0) last_mod = m;
                }
            }
            const bool instruction_abort = trace.find("<IABT>") != std::string::npos;
            // Exception-vector retirements (0x4 undef, 0xc prefetch abort,
            // 0x10 data abort) are always logged: an MMU translation fault
            // never reaches the bus, and these rows are the only cheap
            // whole-run record of user-thread aborts (KERN-EXEC hunts).
            uint32_t retire_pc = 0;
            const bool vector_hit = cpu->o_trace_uop_last &&
                sscanf(trace.c_str(), "%x", &retire_pc) == 1 &&
                ((retire_pc < 0x20 && retire_pc != 0x8 && retire_pc != 0x18 && retire_pc != 0x1c) ||
                 pc_log.count(retire_pc));
            const bool watched_flag_store = trace.find("STR") != std::string::npos && (trace.find("80618af8") != std::string::npos || trace.find("80618b20") != std::string::npos || trace.find("80618bbc") != std::string::npos || trace.find("80618bf8") != std::string::npos || trace.find("80618878") != std::string::npos || trace.find("80619a98") != std::string::npos || trace.find("80619aa0") != std::string::npos || trace.find("80601a6c") != std::string::npos);
            if (watched_flag_store) instruction_log << std::dec << cycle << '\t' << trace << '\n';
            if (cpu->o_trace_uop_last || instruction_abort || (win_lo && cycle >= win_lo && cycle <= win_hi)) {
                last_trace = trace;
                if (!compact_trace || instruction_abort || vector_hit) instruction_log << std::dec << cycle << '\t' << trace << '\n';
                else if (win_lo && cycle >= win_lo && cycle <= win_hi) instruction_log << std::dec << cycle << '\t' << trace << '\n';
                retired += bool(cpu->o_trace_uop_last);
                if (mmu_seen) {
                    retirement_tail.emplace_back(cycle,trace);
                    if (retirement_tail.size() > 8192) retirement_tail.pop_front();
                }
                // A scheduled interrupt can wake a loop only if the matching
                // mask bit is clear (IRQ bit 7; the unit-0x60 FIQ bit 6).
                const bool self_loop = trace.find("BAL -2>") != std::string::npos && trace.size() >= 8;
                if (board && self_loop) {
                    const std::string pc = trace.substr(0,8);
                    self_loop_count = pc == self_loop_pc ? self_loop_count+1 : 1;
                    self_loop_pc = pc;
                    const auto cpsr = std::stoul(trace.substr(trace.size()-8),nullptr,16);
                    const bool masked = (cpsr & 0xc0) == 0xc0;
                    const bool irq_deliverable = (!(cpsr & 0x80) || !(cpsr & 0x40)) && board->has_scheduled_interrupt();
                    if (self_loop_count >= 32 && !irq_deliverable) {
                        status = masked ? "firmware_loop" : "quiescent_loop";
                        blocked_address = std::stoul(pc,nullptr,16);
                        blocked_reason = masked ? "unconditional self-branch repeated with IRQ and FIQ masked" :
                            "unconditional self-branch; no modeled interrupt can be delivered";
                        break;
                    }
                } else self_loop_count = 0;
            }
            if (board && instruction_abort) {
                status = "instruction_abort";
                blocked_address = std::stoul(trace.substr(0,8), nullptr, 16);
                blocked_reason = "an instruction fetch fault reached architectural execution";
                break;
            }
        }
        if (cpu->o_cp15_done && !previous_cp15_done) {
            const uint32_t word = cpu->o_cp15_word;
            if (!(word & (1u << 20)) && ((word >> 16)&15) == 1 && (cpu->o_cp15_data & 1)) mmu_seen = true;
            cp15_log << std::dec << cycle << '\t' << ((word & (1u << 20)) ? "MRC" : "MCR")
                     << '\t' << ((word >> 21) & 7) << '\t' << ((word >> 16) & 15)
                     << '\t' << (word & 15) << '\t' << ((word >> 5) & 7)
                     << '\t' << ((word >> 12) & 15) << "\t0x"
                     << std::hex << std::setw(8) << std::setfill('0') << cpu->o_cp15_data << '\n';
            ++cp15_transactions;
        }
        previous_cp15_done = cpu->o_cp15_done;
        if (checkpoint_at && cycle == checkpoint_at) {
            VerilatedSave out; out.open((checkpoint_path+".cpu").c_str()); out << context.get() << *cpu; out.close();
            std::ofstream host(checkpoint_path+".host",std::ios::binary); if(!host)throw std::runtime_error("checkpoint host unavailable"); save_host(host);
            std::cout << "CHECKPOINT " << checkpoint_path << " cycle " << cycle << std::endl;
        }
        if (checkpoint_every && cycle && cycle % checkpoint_every == 0 && cycle != checkpoint_at) {
            const std::string stem = checkpoint_path + "-r" + std::to_string(cycle / 1000000);
            VerilatedSave out; out.open((stem+".cpu").c_str()); out << context.get() << *cpu; out.close();
            std::ofstream host(stem+".host",std::ios::binary); if(!host)throw std::runtime_error("checkpoint host unavailable"); save_host(host);
            std::cout << "CHECKPOINT " << stem << " cycle " << cycle << std::endl;
            if (cycle % 1000000000ull != 0) rolling_checkpoints.push_back(stem);
            if (rolling_checkpoints.size() > 30) {
                std::remove((rolling_checkpoints.front()+".cpu").c_str());
                std::remove((rolling_checkpoints.front()+".host").c_str());
                rolling_checkpoints.pop_front();
            }
        }
        if (complete) {
            status = mailbox[0] == success ? "pass" : "diagnostic_failure";
            break;
        }
    }
    // The loop executes cycles [0, limit); save the final completed state
    // when the exclusive limit is also a checkpoint boundary.
    if (status == "timeout" && cycle == limit && checkpoint_every &&
        limit % checkpoint_every == 0 && limit != checkpoint_at) {
        const std::string stem = checkpoint_path + "-r" + std::to_string(limit / 1000000);
        --cycle;
        VerilatedSave out; out.open((stem+".cpu").c_str()); out << context.get() << *cpu; out.close();
        std::ofstream host(stem+".host",std::ios::binary); if(!host)throw std::runtime_error("checkpoint host unavailable"); save_host(host);
        ++cycle;
        std::cout << "FINAL CHECKPOINT " << stem << " after " << cycle << " cycles" << std::endl;
    }
    cpu->final();
    if (compact_trace)
        for (const auto& item : retirement_tail) instruction_log << std::dec << item.first << '\t' << item.second << '\n';
    for (const std::string& line : memory_tail) memory_tail_log << line << '\n';
    {
        const std::string dir = (slash == std::string::npos ? "" : bus_path.substr(0,slash+1));
        if (board) { std::ofstream dma(dir + "lcd-dma.tsv"); board->dump_lcd_dma(dma); }
        std::ofstream l1w(dir + "l1-writes.tsv"), l1f(dir + "l1-final.tsv");
        l1w << "cycle\taddress\tcovered_va\tentry\n";
        for (const std::string& line : l1_log) l1w << line << '\n';
        l1f << "slot_va\tentry\n";
        if (board) for (uint32_t slot = 0; slot < 4096; ++slot) {
            uint32_t value = 0; std::string dev;
            if (!board->access({0x0a074000u + slot*4u, 0, 15, false}, value, dev)) continue;
            if (value) l1f << "0x" << std::hex << slot * 0x100000u << "\t0x" << value << '\n';
        }
    }
    for (const std::string& line : branch_tail) branch_log << line << '\n';
    result << "{\n  \"status\": \"" << status << "\",\n"
           << "  \"cycles\": " << std::dec << cycle << ",\n"
           << "  \"compact_trace\": " << (compact_trace ? "true" : "false") << ",\n"
           << "  \"transactions\": " << transactions << ",\n"
           << "  \"retired_instructions\": " << retired << ",\n"
           << "  \"cp15_transactions\": " << cp15_transactions << ",\n"
           << "  \"rom_bytes\": " << rom_bytes << ",\n"
           << "  \"blocked_address\": " << blocked_address << ",\n"
           << "  \"fetch_bus_faults\": " << fetch_faults << ",\n"
#ifdef NGAGE_HDL_BOARD
           << "  \"hdl_board_claims\": " << hdl_claims << ",\n"
#endif
           << "  \"completion\": " << mailbox[0] << ",\n  \"mailbox\": [";
    for (size_t i = 0; i < mailbox.size(); ++i)
        result << (i ? ", " : "") << mailbox[i];
    result << "],\n  \"blocked_reason\": \"" << blocked_reason << "\",\n  \"boot_profile\": ";
    if (board) board->report(result); else result << "null";
    result << "\n}\n";
    std::cout << "\nRESULT " << status << ": " << std::dec << cycle << " cycles, "
              << retired << " retired instructions, " << transactions << " bus transfers\n";
    if (status != "pass") std::cout << "Last retirement: " << last_trace << '\n';
    if (status == "unmapped_access") std::cout << "Unmapped address: 0x" << std::hex << blocked_address << '\n';
    return status == "pass" ? 0 : (status == "unmapped_access" ? 2 : 1);
}
} // namespace

int main(int argc, char** argv) {
    try { return run(argc, argv); }
    catch (const std::exception& e) { std::cerr << "Simulator error: " << e.what() << '\n'; return 1; }
}
