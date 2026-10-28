#include "Vngage_cpu_sim.h"
#include "boot_profile.h"
#include <verilated.h>
#include <verilated_save.h>
#include <algorithm>
#include <array>
#include <cstdint>
#include <cerrno>
#include <cstring>
#include <deque>
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
    const std::string profile_name = argc >= 9 ? argv[8] : "none";
    bool ideal_clocks = false, lcd_probe = false, compact_trace = false, boot_io_probe = false, allow_uif_8000 = false, allow_icu25 = false, gpio210_low_zero = false, gpio21a_zero = false, gpio216_zero = false, gpio214_low_zero = false, pupf004_low_zero = false, gpio206_extra_write = false, sysc74_write3 = false, gpio24_28_write1 = false, timer_compare_probe = false, sysc50_44_probe = false, uif102_write = false, cbus82_readback = false, cbus8d_zero = false, icu46_write = false, pupf00a_zero = false, sysc0c14_zero = false;
    std::vector<uint8_t> rom_tail;
    std::map<unsigned,unsigned> adc_inputs;
    std::map<uint32_t,std::pair<uint32_t,uint8_t>> probe_regs;
    uint64_t timer_irq_delay = 0, checkpoint_at = 0;
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
        else if (std::string(argv[i]) == "uif102-write") uif102_write = true;
        else if (std::string(argv[i]) == "cbus82-readback") cbus82_readback = true;
        else if (std::string(argv[i]) == "cbus8d-zero") cbus8d_zero = true;
        else if (std::string(argv[i]) == "icu46-write") icu46_write = true;
        else if (std::string(argv[i]) == "pupf00a-zero") pupf00a_zero = true;
        else if (std::string(argv[i]) == "sysc0c14-zero") sysc0c14_zero = true;
        else if (std::string(argv[i]) == "+ngage-compact-trace") compact_trace = true;
        else if (std::string(argv[i]).rfind("checkpoint-at=", 0) == 0) checkpoint_at = std::stoull(std::string(argv[i]).substr(14));
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
        } else if (std::string(argv[i]).rfind("probe-register=", 0) == 0) {
            const std::string v=std::string(argv[i]).substr(15); size_t a=v.find(':'), b=v.find(':',a+1);
            if (a==std::string::npos || b==std::string::npos || v.find(':',b+1)!=std::string::npos) throw std::runtime_error("register probe format ADDRESS:VALUE:SELECT");
            auto number=[](const std::string& x){size_t n=0;auto u=std::stoull(x,&n,0);if(n!=x.size() || u>0xffffffffull)throw std::runtime_error("invalid register probe number");return uint32_t(u);};
            auto address=number(v.substr(0,a)),value=number(v.substr(a+1,b-a-1)),select=number(v.substr(b+1));
            if (select>15 || !probe_regs.emplace(address,std::make_pair(value,uint8_t(select))).second) throw std::runtime_error("invalid or duplicate register probe");
        } else if (std::string(argv[i]).rfind("uem-adc=", 0) == 0) {
            if (!adc_inputs.empty()) throw std::runtime_error("duplicate ADC input option");
            adc_inputs = BootProfile::parse_adc_inputs(std::string(argv[i]).substr(8));
        } else if (std::string(argv[i]).rfind("rom-extension=", 0) == 0) {
            std::ifstream tail(std::string(argv[i]).substr(14), std::ios::binary);
            if (!tail) throw std::runtime_error("cannot open reconstructed ROM tail");
            rom_tail.assign(std::istreambuf_iterator<char>(tail), {});
            if (rom_tail.empty()) throw std::runtime_error("reconstructed ROM tail is empty");
        } else throw std::runtime_error("unknown board option");
    }
    std::unique_ptr<BootProfile> board;
    if (profile_name != "none") board = std::make_unique<BootProfile>(rom, rom_bytes, profile_name, ideal_clocks, lcd_probe, rom_tail, boot_io_probe, adc_inputs, timer_irq_delay, uem_power_status, uem_status36, uem_status35, extra_cbus_write, extra_cbus_write2, allow_uif_8000, allow_icu25, gpio210_low_zero, gpio21a_zero, gpio216_zero, uif102_write, cbus82_readback, cbus80_input, cbus8d_zero, icu46_write, pupf00a_zero, sysc0c14_zero, probe_regs, gpio214_low_zero, pupf004_low_zero, gpio206_extra_write, sysc74_write3, gpio24_28_write1, timer_compare_probe, sysc50_44_probe);
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
    bool mmu_seen = false;
    unsigned self_loop_count = 0;
    std::string self_loop_pc;
    std::deque<std::pair<uint64_t,std::string>> retirement_tail;
    std::deque<std::string> memory_tail, branch_tail;
    if ((checkpoint_at && checkpoint_path.empty()) || (!checkpoint_at && !checkpoint_path.empty()) ||
        (!restore_path.empty() && checkpoint_at)) throw std::runtime_error("invalid checkpoint options");
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
        if (!board) throw std::runtime_error("counterfactual requires the experimental board");
        const uint32_t expected[4] = {0,4,0,2};
        for (unsigned i=0;i<4;i++) {
            uint32_t value=0; std::string device;
            if (!board->access({0x0a01200cu+4*i,0,15,false},value,device) || value!=expected[i])
                throw std::runtime_error("unexpected pre-intervention variant-table contents");
        }
        uint32_t value=0; std::string device;
        if (!board->access({0x0a012010u,0,15,true},value,device)) throw std::runtime_error("counterfactual write failed");
        std::cerr << "COUNTERFACTUAL: changed physical 0x0a012010 from class 4 to 0 after checkpoint restore" << std::endl;
    }

    for (; cycle < limit && !context->gotFinish(); ++cycle) {
        cpu->i_clk = 0;
        cpu->i_irq = board && board->timer_irq();
        cpu->i_wb_ack = 0;
        cpu->i_wb_err = 0;
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
        if (pending && wait == 0) {
            const uint32_t address = request.address & ~uint32_t(3);
            uint32_t data = 0;
            uint8_t* memory = nullptr;
            bool readonly = false, bus_fault = false;
            std::string device;
            if (board) {
                if (!board->access({request.address, request.data, request.select, request.write}, data, device)) {
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
            if (!compact_trace || bus_fault || device == "flash_command" || device == "flash_identify" ||
                device == "observed_boot_latch" || device == "ideal_clock_status" ||
                device == "ideal_pll_status" || device == "lcd_probe_transport" || device == "reconstructed_flash_tail" || device == "ideal_boot_cbus_status" || device == "boot_cbus_latched_data" || device == "assumed_uem_adc_data" || device == "assumed_sysc50_44_write" || device == "assumed_gpio24_28_write1" || device == "assumed_sysc74_write3" || device == "assumed_register_probe" || device == "assumed_cbus82_readback" || device == "assumed_cbus80_input" || device == "assumed_cbus8d_read" || device == "assumed_uem_power_status" || device == "assumed_uem_status36" || device == "assumed_uem_status35" || device == "assumed_timer_status" || device == "assumed_irq_halfword_write" || device == "assumed_uif_8000_write" || device == "assumed_uif_0010_write" || device == "assumed_icu46_write" || device == "timer_setup_write")
            bus_log << std::dec << cycle << '\t' << (bus_fault ? "FETCH_ERROR" : request.write ? "WRITE" : "READ")
                    << "\t0x" << std::hex << std::setw(8) << std::setfill('0') << request.address
                    << "\t0x" << unsigned(request.select) << "\t0x"
                    << std::setw(8) << (request.write ? request.data : data)
                    << '\t' << (request.code ? "code" : "data") << '\t' << device << '\n';
            if (mmu_seen && !request.code) {
                std::ostringstream line;
                line << std::dec << cycle << '\t' << (request.write ? "WRITE" : "READ")
                     << "\t0x" << std::hex << request.address << "\t0x" << unsigned(request.select)
                     << "\t0x" << (request.write ? request.data : data) << '\t' << device;
                memory_tail.push_back(line.str());
                if (memory_tail.size() > 32768) memory_tail.pop_front();
            }
            cpu->i_wb_dat = bus_fault ? 0 : data;
            cpu->i_wb_ack = !bus_fault;
            cpu->i_wb_err = bus_fault;
            fetch_faults += bus_fault;
            pending = false;
            ++transactions;
        } else if (pending) --wait;
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
            const bool instruction_abort = trace.find("<IABT>") != std::string::npos;
            if (cpu->o_trace_uop_last || instruction_abort) {
                last_trace = trace;
                if (!compact_trace || instruction_abort) instruction_log << std::dec << cycle << '\t' << trace << '\n';
                retired += bool(cpu->o_trace_uop_last);
                if (mmu_seen) {
                    retirement_tail.emplace_back(cycle,trace);
                    if (retirement_tail.size() > 8192) retirement_tail.pop_front();
                }
                // A scheduled IRQ can wake a loop only if IRQ is unmasked.
                // No FIQ source is modeled.
                const bool self_loop = trace.find("BAL -2>") != std::string::npos && trace.size() >= 8;
                if (board && self_loop) {
                    const std::string pc = trace.substr(0,8);
                    self_loop_count = pc == self_loop_pc ? self_loop_count+1 : 1;
                    self_loop_pc = pc;
                    const auto cpsr = std::stoul(trace.substr(trace.size()-8),nullptr,16);
                    const bool masked = (cpsr & 0xc0) == 0xc0;
                    const bool irq_deliverable = !(cpsr & 0x80) && board->has_scheduled_interrupt();
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
        if (complete) {
            status = mailbox[0] == success ? "pass" : "diagnostic_failure";
            break;
        }
    }
    cpu->final();
    if (compact_trace)
        for (const auto& item : retirement_tail) instruction_log << std::dec << item.first << '\t' << item.second << '\n';
    for (const std::string& line : memory_tail) memory_tail_log << line << '\n';
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
