#include "boot_profile.h"
#include <iomanip>
#include <stdexcept>
#include <cctype>
#include <sstream>

namespace {
constexpr uint32_t code_scratch_base = 0x0c004748;
constexpr uint32_t probe_base = 0x02000000;
uint32_t byte_mask(uint8_t select) {
    uint32_t mask = 0;
    for (unsigned i = 0; i < 4; ++i)
        if (select & (1u << i)) mask |= 0xffu << (8 * i);
    return mask;
}
}

std::map<unsigned, unsigned> BootProfile::parse_adc_inputs(const std::string& options) {
    std::map<unsigned, unsigned> result;
    if (options.empty()) return result;
    auto number = [](const std::string& text) -> unsigned {
        const bool hex = text.size() > 2 && text[0] == '0' && (text[1] == 'x' || text[1] == 'X');
        const auto digits = text.substr(hex ? 2 : 0);
        if (digits.empty()) throw std::runtime_error("invalid ADC integer");
        for (unsigned char c : digits)
            if (!(hex ? std::isxdigit(c) : std::isdigit(c)))
                throw std::runtime_error("invalid ADC integer");
        const auto value = std::stoul(text, nullptr, hex ? 16 : 10);
        if (value > 1023) throw std::runtime_error("ADC integer exceeds range");
        return unsigned(value);
    };
    std::istringstream fields(options);
    std::string field;
    if (options.back() == ',') throw std::runtime_error("empty ADC input");
    while (std::getline(fields, field, ',')) {
        auto equal = field.find('=');
        if (equal == std::string::npos || field.find('=', equal + 1) != std::string::npos)
            throw std::runtime_error("ADC inputs use CHANNEL=VALUE");
        const auto channel = number(field.substr(0, equal)), value = number(field.substr(equal + 1));
        if (channel > 13) throw std::runtime_error("ADC channel must be 0..13");
        if (!result.emplace(channel, value).second) throw std::runtime_error("duplicate ADC channel");
    }
    return result;
}

void BootProfile::tick() {
    if (!timer_irq_delay_) return;
    ++timer_elapsed_;
    if (timer_remaining_ && --timer_remaining_ == 0) {
        timer_irq_pending_ = true;
        timer_irq_cycle_ = timer_elapsed_;
    }
}

uint32_t BootProfile::word(size_t offset) const {
    if (offset + 4 > rom_bytes_) throw std::runtime_error("truncated boot bank table");
    return uint32_t(rom_[offset]) | uint32_t(rom_[offset+1]) << 8 |
           uint32_t(rom_[offset+2]) << 16 | uint32_t(rom_[offset+3]) << 24;
}

BootProfile::BootProfile(const std::vector<uint8_t>& rom, size_t rom_bytes, const std::string& kind, bool ideal_clocks, bool lcd_probe, const std::vector<uint8_t>& rom_tail, bool boot_io_probe, const std::map<unsigned, unsigned>& adc_inputs, uint64_t timer_irq_delay, int uem_power_status, int uem_status36, int uem_status35, int extra_cbus_write, int extra_cbus_write2, bool allow_uif_8000, bool allow_icu25, bool gpio210_low_zero, bool gpio21a_zero, bool gpio216_zero, bool uif102_write, bool cbus82_readback, int cbus80_input, bool cbus8d_zero, bool icu46_write, bool pupf00a_zero, bool sysc0c14_zero, const std::map<uint32_t,std::pair<uint32_t,uint8_t>>& probe_regs, bool gpio214_low_zero, bool pupf004_low_zero, bool gpio206_extra_write)
    : rom_(rom), rom_bytes_(rom_bytes), rom_tail_(rom_tail), kind_(kind), ideal_clocks_(ideal_clocks), lcd_probe_(lcd_probe), boot_io_probe_(boot_io_probe), adc_inputs_(adc_inputs), timer_irq_delay_(timer_irq_delay) {
    allow_uif_8000_ = allow_uif_8000; allow_icu25_ = allow_icu25; gpio210_low_zero_ = gpio210_low_zero; gpio21a_zero_ = gpio21a_zero; gpio216_zero_ = gpio216_zero; gpio214_low_zero_ = gpio214_low_zero; pupf004_low_zero_ = pupf004_low_zero; gpio206_extra_write_ = gpio206_extra_write; uif102_write_ = uif102_write; cbus82_readback_ = cbus82_readback; cbus80_input_ = cbus80_input; cbus8d_zero_ = cbus8d_zero; icu46_write_ = icu46_write; pupf00a_zero_ = pupf00a_zero; sysc0c14_zero_ = sysc0c14_zero;
    if (sysc0c14_zero_ && !pupf00a_zero_) throw std::runtime_error("system control probe requires PUP probe");
    if (pupf00a_zero_ && !icu46_write_) throw std::runtime_error("PUP input probe requires ICU46 probe");
    if (icu46_write_ && !cbus8d_zero_) throw std::runtime_error("ICU46 probe requires CBUS8d probe");
    if (cbus8d_zero_ && cbus80_input_ != 0x400) throw std::runtime_error("CBUS8d probe requires CBUS80=0x400");
    if (cbus80_input_ < -1 || cbus80_input_ > 65535 || (cbus80_input_ >= 0 && !cbus82_readback_)) throw std::runtime_error("CBUS80 input requires readback probe and 16-bit value");
    if (cbus82_readback_ && extra_cbus_write2 != 0x82) throw std::runtime_error("CBUS 82 readback requires explicit write option");
    if (uif102_write_ && !gpio216_zero_) throw std::runtime_error("UIF102 probe requires GPIO 216 probe");
    if (gpio216_zero_ && !gpio21a_zero_) throw std::runtime_error("GPIO 216 probe requires GPIO 21a probe");
    if (gpio21a_zero_ && !gpio210_low_zero_) throw std::runtime_error("GPIO 21a probe requires GPIO 210 probe");
    if (gpio210_low_zero_ && !allow_icu25_) throw std::runtime_error("GPIO input probe requires ICU probe");
    if (allow_icu25_ && !allow_uif_8000_) throw std::runtime_error("ICU25 probe requires UIF write probe");
    if (allow_uif_8000_ && !boot_io_probe_) throw std::runtime_error("UIF write probe requires boot I/O");
    uem_power_status_ = uem_power_status; uem_status36_ = uem_status36; uem_status35_ = uem_status35; extra_cbus_write_ = extra_cbus_write; extra_cbus_write2_ = extra_cbus_write2;
    if (extra_cbus_write2_ < -1 || extra_cbus_write2_ > 255 || (extra_cbus_write2_ >= 0 && !boot_io_probe_)) throw std::runtime_error("invalid second CBUS write");
    if (extra_cbus_write_ < -1 || extra_cbus_write_ > 63 || (extra_cbus_write_ >= 0 && !boot_io_probe_))
        throw std::runtime_error("extra CBUS write must be a register 0..63 and requires boot probe");
    if (uem_status35_ < -1 || uem_status35_ > 65535 || (uem_status35_ >= 0 && !timer_irq_delay_))
        throw std::runtime_error("UEM 0x35 input requires timer experiment and 16-bit value");
    if (uem_status36_ < -1 || uem_status36_ > 65535 || (uem_status36_ >= 0 && !timer_irq_delay_))
        throw std::runtime_error("UEM 0x36 input requires timer experiment and 16-bit value");
    if (uem_power_status_ < -1 || uem_power_status_ > 65535 || (uem_power_status_ >= 0 && !timer_irq_delay_))
        throw std::runtime_error("UEM status needs timer experiment and a 16-bit value");
    for (const auto& item : probe_regs) {
        if (!sysc0c14_zero_ || item.first < 0x0c120000 || item.first >= 0x0c160000 || (item.first & 3) ||
            (item.second.second != 3 && item.second.second != 12 && item.second.second != 15))
            throw std::runtime_error("invalid explicit register probe");
        probe_regs_[item.first] = {item.second.first, item.second.first, item.second.second};
    }
    if (timer_irq_delay_ && !boot_io_probe_)
        throw std::runtime_error("timer IRQ experiment requires the boot-I/O probe");
    if (!adc_inputs_.empty() && !boot_io_probe_)
        throw std::runtime_error("explicit ADC inputs require the boot-I/O experiment");
    for (const auto& input : adc_inputs_)
        if (input.first > 13 || input.second > 1023)
            throw std::runtime_error("ADC channel must be 0..13 and sample must be 0..1023");
    if (rom_bytes > rom.size()) throw std::runtime_error("invalid ROM size");
    if (kind == "intel8") {
        table_ = 0x744; manufacturer_ = 0x89; device_ = 0x8872;
    } else if (kind == "amd8") {
        table_ = 0x744; manufacturer_ = 1; device_ = 0x22d1;
    } else if (kind == "amd16") {
        table_ = 0x638; manufacturer_ = 1; device_ = 0x227e;
    } else throw std::runtime_error("unknown experimental boot profile");
    // CS0/CS2 use the AM29N643/Am29BDS643G identity from the NEM-4
    // schematic and AMD datasheet. CS1 remains the selected hypothesis.
    // The handshake option is explicit model configuration, not a phone read.
    flash_[0] = {0, 1, 0x227e, 0x2202, 0x2200, 0x43, false, true};
    flash_[1] = {probe_base, manufacturer_, device_, 0x2202, 0x2200, 0x43, false, true};
    flash_[2] = {0x04000000, 1, 0x227e, 0x2202, 0x2200, 0x43, false, true};
    const uint32_t count = word(table_);
    if (!count || count > 64) throw std::runtime_error("invalid boot bank count");
    size_t rom_offset = 0;
    for (uint32_t i = 0; i < count; ++i) {
        const size_t entry = table_ + 8 + i * 16;
        const uint32_t address = word(entry), size = word(entry+4), flags = word(entry+8);
        if (!size || uint64_t(address) + size > 0x100000000ull)
            throw std::runtime_error("invalid boot bank range");
        if ((flags & 31) == 1) {
            banks_.push_back({address, size, rom_offset});
            rom_offset += size;
        } else if ((flags & 31) == 2) {
            if (!ram_.empty() || size > 64 * 1024 * 1024)
                throw std::runtime_error("unsupported boot RAM banks");
            ram_base_ = address;
            ram_.resize(size, 0);
        }
    }
    if (banks_.empty() || ram_.empty()) throw std::runtime_error("missing boot memory banks");
    if (!rom_tail_.empty() && (kind != "amd16" || rom_bytes_ % 4 || rom_tail_.size() % 4 ||
        rom_bytes_ + rom_tail_.size() > rom_offset))
        throw std::runtime_error("reconstructed tail exceeds selected ROM banks or has invalid alignment/profile");
    // These exact write sites/widths occur at file offsets 0xb6c..0xbc0.
    for (uint32_t address : {0x08000000u,0x08000004u,0x08000008u,
                             0x08000010u,0x08000014u,0x08000018u})
        latches_.emplace(address, Latch{});
    latches_[0x0c150004].allowed = 3;
    // Word writes in ROM 0x37a8 and 0x36dc; status is a separate opt-in
    // experiment because no UPP_WD2 programming manual has been located.
    latches_.emplace(0x0c120004, Latch{});
    latches_.emplace(0x0c120008, Latch{});
    for (uint32_t address : {0x0c120014u,0x0c120018u,0x0c120034u,0x0c120038u,0x0c149000u})
        latches_.emplace(address, Latch{});
    if (lcd_probe_) {
        // ROM 0x617c performs three halfword RMWs before starting the LCD
        // interface. Zero reset is an explicit probe assumption, not evidence.
        latches_[0x0c14f008] = {0, 0x0000ffff, 3};
        latches_[0x0c15020c] = {0, 0xffff0000, 12};
        latches_[0x0c14f010] = {0, 0x0000ffff, 3};
        // ROM 0x630c/0x62d0 writes these halfwords to toggle panel reset.
        latches_[0x0c150204].allowed = 3;
        latches_[0x0c150200].allowed = 12;
    }
    if (boot_io_probe_) {
        // Explicit cold-boot hypotheses; only these selected bits are known.
        latches_[0x0c150210] = {0, 0xffff0000, 12};
        latches_[0x0c150000] = {0, 0x0000ffff, 3};
        latches_[0x0c0047fc] = {0, 0xffffff00, 14};
        // ROM 0x352c copies 19 halfwords into a software register shadow.
        // These bytes become known only when written; the two-byte gap before
        // the existing executable scratch remains unmapped.
        for (uint32_t address = 0x0c004720; address < 0x0c004744; address += 4)
            latches_.emplace(address, Latch{});
        latches_[0x0c004744].allowed = 3;
        latches_[0x0c150034].allowed = 3;
        latches_[0x0c150420].allowed = 15;
        latches_[0x0c150424].allowed = 12;
    }
}

bool BootProfile::flash_command(Flash& flash, const BootBusRequest& request) {
    if (request.select != 3 && request.select != 12) {
        reason_ = "flash command width is outside the observed halfword protocol";
        return false;
    }
    const unsigned shift = request.select == 12 ? 16 : 0;
    const uint32_t address = (request.address & ~3u) + shift / 8 - flash.base;
    const uint16_t value = (request.data >> shift) & 0xffff;
    if (value == 0xff || value == 0xf0) {
        flash.identify = false; flash.unlock = 0; return true;
    }
    if (flash.intel) {
        if (value == 0x90) { flash.identify = true; return true; }
    } else {
        if (address == 0xaaa && value == 0xaa) {
            flash.unlock = 1; return true;
        }
        if (flash.unlock == 1 && address == 0x554 && value == 0x55) {
            flash.unlock = 2; return true;
        }
        if (flash.unlock == 2 && address == 0xaaa && value == 0x90) {
            flash.identify = true; flash.unlock = 0; return true;
        }
        // AMD datasheet Table 8/10: C0 after two unlock cycles latches
        // burst mode/wait states from address A16..A12, not array data.
        const uint32_t word_address = address >> 1;
        if (flash.unlock == 2 && value == 0xc0 && (word_address & 0xfff) == 0x555 &&
            ((word_address >> 12) & 7) <= 5) {
            flash.burst_configuration = word_address & 0x1f000;
            flash.burst_configured = true;
            flash.unlock = 0;
            return true;
        }
        // Firmware tries Intel commands before the AMD sequence. These
        // ineffective commands leave the AMD array readable.
        if ((address == 0xaaaa || address == 0) && value == 0x90 && flash.unlock == 0)
            return true;
    }
    reason_ = "unmodeled flash command or unlock sequence";
    return false;
}

bool BootProfile::flash_identify(const Flash& flash, const BootBusRequest& request,
                                 uint32_t& data) {
    const uint32_t offset = (request.address & ~3u) - flash.base;
    // Validate only selected halfwords: an LDRH of the handshake register
    // must not silently invent the neighboring sector-lock status.
    for (unsigned half = 0; half < 2; ++half) {
        if (!(request.select & (3u << (half * 2)))) continue;
        const uint32_t at = offset + half * 2;
        uint16_t value;
        if (at == 0) value = flash.manufacturer;
        else if (at == 2) value = flash.device;
        else if (flash.extended && at == 0x1c) value = flash.id2;
        else if (flash.extended && at == 0x1e) value = flash.id3;
        else if (flash.extended && at == 6) value = flash.handshake;
        else {
            reason_ = "unmodeled flash identification offset"; return false;
        }
        data |= uint32_t(value) << (16 * half);
    }
    return true;
}

bool BootProfile::access(const BootBusRequest& request, uint32_t& data, std::string& device) {
    reason_.clear();
    device.clear();
    const uint32_t address = request.address & ~3u;
    data = 0;
    if (address >= code_scratch_base &&
        uint64_t(address - code_scratch_base) + 4 <= code_scratch_.size()) {
        device = "observed_code_scratch";
        const size_t offset = address - code_scratch_base;
        for (unsigned i = 0; i < 4; ++i) {
            if (!(request.select & (1u << i))) continue;
            if (request.write) {
                code_scratch_[offset+i] = (request.data >> (8*i)) & 255;
                code_scratch_written_[offset+i] = 1;
            } else if (!code_scratch_written_[offset+i]) {
                reason_ = "unwritten executable scratch byte"; return false;
            }
        }
        for (unsigned i = 0; i < 4; ++i)
            data |= uint32_t(code_scratch_[offset+i]) << (8*i);
        return true;
    }
    if (address == 0x0c120020 && ideal_clocks_) {
        device = "ideal_clock_status";
        const Latch& control = latches_.at(0x0c120004);
        const Latch& command = latches_.at(0x0c120008);
        if (request.write || control.written != 0xffffffffu) {
            reason_ = "clock status requested before a complete control write"; return false;
        }
        if (control.value == 12) data = 0x04000000;
        else if (control.value == 0x27 && command.written == 0xffffffffu && command.value == 1)
            data = 0x08000000;
        else if (control.value == 3 && latches_.at(0x0c149000).written == 0xffffffffu &&
                 latches_.at(0x0c149000).value == 0x2210) data = 0x08000000;
        else { reason_ = "unmodeled clock control/status combination"; return false; }
        return true;
    }
    if (lcd_probe_ && address >= 0x0c121200 && address <= 0x0c121208) {
        device = "lcd_probe_transport";
        if (request.select != 15) {
            reason_ = "unobserved LCD transport width"; return false;
        }
        if (address == 0x0c121204 && request.write) {
            if (request.data != 1 && request.data != 2) {
                reason_ = "unmodeled LCD control command"; return false;
            }
            lcd_control_ = request.data; lcd_control_written_ = true;
            if (request.data == 2) lcd_header_written_ = false;
            return true;
        }
        if (!lcd_control_written_ || lcd_control_ != 1) {
            reason_ = "LCD transport used before observed enable sequence"; return false;
        }
        if (address == 0x0c121200 && request.write) {
            const uint32_t mode = request.data & 0xffff0000;
            if (request.data != 0x4f300000 && request.data != 0x49200000 &&
                request.data != 0x09200000 && mode != 0x09240000 && mode != 0x89240000 &&
                mode != 0x02140000 && request.data != 0x07800000) {
                reason_ = "unmodeled LCD transfer header"; return false;
            }
            lcd_header_ = request.data; lcd_header_written_ = true; ++lcd_headers_;
            return true;
        }
        if (address == 0x0c121204 && !request.write) {
            // ROM 0x6724 polls bit 2. An immediate sink assumes it is ready.
            data = 4; ++lcd_status_reads_; return true;
        }
        if (address == 0x0c121200 && !request.write && lcd_header_written_ && lcd_header_ == 0x49200000) {
            // ROM 0x6cf8 polls bit 30 after this exact header.
            data = 0x40000000; ++lcd_status_reads_; return true;
        }
        if (address == 0x0c121208 && request.write && lcd_header_written_) {
            ++lcd_data_words_; return true;
        }
        reason_ = "unmodeled LCD transport read or transfer state"; return false;
    }
    if (icu46_write_ && icu25_written_ && cbus_written_.count(0x8d) && address == 0x0c120148 &&
        request.write && request.select == 15 && request.data == 0x4000) {
        device = "assumed_icu46_write"; return true;
    }
    if (boot_io_probe_ && (address == 0x0c120a04 || address == 0x0c120a08 ||
        address == 0x0c120a10 || address == 0x0c120a18 || address == 0x0c120108 || address == 0x0c12010c)) {
        // ROM 0x3200 writes these exact timer/ICU setup values. Capturing
        // writes does not make a running counter, readback, IRQ or reset state.
        device = "timer_setup_write";
        if (!request.write) {
            if (timer_irq_delay_ && address == 0x0c120a08 && timer_irq_cycle_ && latches_.count(address) && request.select == 15) { data = latches_.at(address).value; device = "assumed_timer_status"; return true; }
            if (timer_irq_delay_ && timer_irq_cycle_ && address == 0x0c120a04 && request.select == 15 && latches_.count(address) && latches_.at(address).value == 2) { data = 2; device = "assumed_timer_status"; return true; }
            reason_ = "timer/interrupt register read semantics are not modeled"; return false;
        }
        const uint32_t expected = address == 0x0c120a04 ? 2 : address == 0x0c120108 ? 1 :
                                  address == 0x0c120a08 ? 0 : 0x0115b5c0;
        const bool irq_ack = timer_irq_delay_ && address == 0x0c120a08 &&
                             request.data == 1 && timer_irq_pending_;
        const bool kernel_reload = timer_irq_delay_ && timer_irq_cycle_ && address == 0x0c120a18 &&
                                   request.data == 0x632ea && latches_.count(0x0c120a04) &&
                                   latches_.at(0x0c120a04).value == 2;
        const bool icu25_write = allow_icu25_ && uif_written_ && timer_irq_cycle_ &&
                                  address == 0x0c120108 && request.data == 0x02000000;
        const bool handler_write = timer_irq_delay_ && timer_irq_cycle_ &&
            (((address == 0x0c120a18 || address == 0x0c120a10 || address == 0x0c120a04) && request.data == 0) ||
             (address == 0x0c12010c && request.data == 1));
        if (request.select != 15 || (request.data != expected && !irq_ack && !handler_write && !kernel_reload && !icu25_write) ||
            (address == 0x0c12010c && !handler_write)) {
            reason_ = "unobserved timer/interrupt setup width or value"; return false;
        }
        if (icu25_write) icu25_written_ = true;
        if (timer_irq_delay_) {
            if (address == 0x0c120a04 && request.data == 2) timer_started_ = true;
            if (address == 0x0c120a18 && timer_started_ && request.data == 0x0115b5c0) timer_remaining_ = timer_irq_delay_;
            if (address == 0x0c120108 && request.data == 1) timer_irq_enabled_ = true;
            if (irq_ack) timer_irq_pending_ = false;
        }
        latches_[address] = {request.data, 0xffffffff, 15};
        return true;
    }
    // Firmware IRQ path at 0x2f44 writes this exact halfword after UEM reads.
    // Its peripheral semantics remain unknown; no readback is invented.
    if (boot_io_probe_ && timer_irq_delay_ && timer_irq_cycle_ && address == 0x0c150100 &&
        request.write && request.select == 3 && (request.data & 0xffff) == 0x8000) {
        device = "assumed_irq_halfword_write";
        return true;
    }
    // Exact observed write after UEM 0x27; peripheral semantics remain unknown.
    if (boot_io_probe_ && allow_uif_8000_ && timer_irq_cycle_ && cbus_written_.count(0x27) &&
        address == 0x0c150010 && request.write && request.select == 12 && (request.data >> 16) == 0x8000) {
        uif_written_ = true; device = "assumed_uif_8000_write"; return true;
    }
    if (uif102_write_ && icu25_written_ && address == 0x0c150100 && request.select == 12 && request.write &&
        (request.data >> 16) == 0x10 && latches_.count(0x0c150214)) {
        device = "assumed_uif_0010_write"; return true;
    }
    if (boot_io_probe_ && (address == 0x0c150420 || address == 0x0c150424)) {
        device = "observed_boot_latch";
        if ((request.select != 3 && request.select != 12) ||
            (address == 0x0c150424 && request.select != 12)) {
            reason_ = "unobserved boot control-bus width"; return false;
        }
        const uint16_t value = request.data >> (request.select == 12 ? 16 : 0);
        if (request.write) {
            if (address == 0x0c150420 && request.select == 3) {
                if (value != 0x10 && value != 8 && value != 7 && value != 0xf && value != 0x8f) {
                    reason_ = "unmodeled boot control-bus configuration"; return false;
                }
                cbus_config_ = value; cbus_stage_ = 1;
            } else if (address == 0x0c150420) {
                // Register set from the firmware's 19-halfword lookup at
                // 0x6d80, plus the explicit 0x35 reset-status access.
                static const uint16_t known[] = {0,0x2a,0x29,0x2b,0x2c,0x2d,0x2e,0x2f,0x30,0x31,
                                                0x32,0x33,0x37,0x38,0x39,0x3a,0x3b,0x26,0x36,0x35};
                bool recognized = timer_irq_delay_ && value == 0x13f;
                const bool extra_write = (extra_cbus_write_ >= 0 && value == unsigned(extra_cbus_write_)) ||
                                         (extra_cbus_write2_ >= 0 && value == unsigned(extra_cbus_write2_));
                const bool extra_read = cbus82_readback_ && cbus_written_.count(0x82) &&
                    (value == 0x182 || (value == 0x180 && cbus80_input_ >= 0));
                const bool extra_rmw = cbus8d_zero_ && cbus_written_.count(0x82) && (value == 0x18d || value == 0x8d);
                if (extra_write || extra_read || extra_rmw) recognized = true;
                for (uint16_t reg : known) recognized |= (value & 0xff) == reg;
                if (cbus_stage_ != 1 || ((value & ~0x13fu) && value != 0x239 && !extra_write && !extra_read && !extra_rmw) || !recognized) {
                    reason_ = "unmodeled boot control-bus command"; return false;
                }
                cbus_command_ = value;
                cbus_stage_ = (value & 0x100) ? 3 : 2;
                if (value & 0x100) ++cbus_transactions_;
            } else {
                if (cbus_stage_ != 2 || (cbus_command_ & 0x100)) {
                    reason_ = "boot control-bus payload has no write command"; return false;
                }
                // Bits 8/9 are transfer direction, not device/register bits.
                // ROM 0x3138 starts a UEM ADC conversion with command 0x239.
                cbus_written_[cbus_command_ & 0xff] = value;
                if ((cbus_command_ & 0xff) == 0x39)
                    uem_adc_channel_ = (value & 0x0800) ? value >> 12 : -1;
                cbus_stage_ = 3; ++cbus_transactions_;
            }
        } else if (address == 0x0c150420 && request.select == 12) {
            if (cbus_stage_ != 3) {
                reason_ = "boot control-bus completion requested before known transaction"; return false;
            }
            device = "ideal_boot_cbus_status";
            data = uint32_t(cbus_command_ | 0x400) << 16;
            return true;
        } else if (address == 0x0c150424 && cbus_stage_ == 3 && (cbus_command_ & 0x100)) {
            if ((cbus_command_ & 0xff) == 0x3a) {
                // UEM register 0x1a is ADC data on read, watchdog on write.
                // A prior write cannot supply an analog conversion result.
                if (uem_adc_channel_ < 0) {
                    reason_ = "UEM ADC read before known conversion"; return false;
                }
                const auto input = adc_inputs_.find(unsigned(uem_adc_channel_));
                if (input == adc_inputs_.end()) {
                    reason_ = "UEM ADC channel " + std::to_string(uem_adc_channel_) + " input is not supplied";
                    return false;
                }
                data = uint32_t(input->second) << 16;
                device = "assumed_uem_adc_data";
                ++adc_result_reads_;
                return true;
            }
            if ((cbus_command_ & 0xff) == 0x3f && timer_irq_delay_) {
                if (uem_power_status_ < 0) { reason_ = "UEM power-key/charger status is not supplied"; return false; }
                device = "assumed_uem_power_status"; data = uint32_t(uem_power_status_) << 16; return true;
            }
            if ((cbus_command_ & 0xff) == 0x35 && timer_irq_delay_) {
                if (uem_status35_ < 0) { reason_ = "UEM 0x35 status is not supplied"; return false; }
                device = "assumed_uem_status35"; data = uint32_t(uem_status35_) << 16; return true;
            }
            if ((cbus_command_ & 0xff) == 0x36 && uem_status36_ >= 0 && !cbus_written_.count(0x36)) {
                device = "assumed_uem_status36"; data = uint32_t(uem_status36_) << 16; return true;
            }
            if ((cbus_command_ & 0xff) == 0x80 && cbus80_input_ >= 0) {
                device = "assumed_cbus80_input"; data = uint32_t(cbus80_input_) << 16; return true;
            }
            if ((cbus_command_ & 0xff) == 0x8d && cbus8d_zero_) {
                auto it = cbus_written_.find(0x8d);
                device = "assumed_cbus8d_read"; data = uint32_t(it == cbus_written_.end() ? 0 : it->second) << 16; return true;
            }
            auto value = cbus_written_.find(cbus_command_ & 0xff);
            if (value == cbus_written_.end()) {
                reason_ = "unknown initial value of boot control-bus device register"; return false;
            }
            device = (cbus82_readback_ && (cbus_command_ & 0xff) == 0x82) ? "assumed_cbus82_readback" : "boot_cbus_latched_data";
            data = uint32_t(value->second) << 16;
            return true;
        } else {
            reason_ = "unmodeled boot control-bus read"; return false;
        }
    }
    // Explicit low-halfword reset hypothesis after the observed ICU write.
    if (gpio210_low_zero_ && icu25_written_ && address == 0x0c150210 && request.select == 3) {
        Latch& gpio = latches_.at(address);
        if (!(gpio.written & 0xffff)) { gpio.allowed = 15; gpio.written |= 0xffff; }
    }
    if (gpio21a_zero_ && icu25_written_ && address == 0x0c150218 && request.select == 12 &&
        (latches_.at(0x0c150210).written & 0xffff) == 0xffff)
        latches_.emplace(address, Latch{0, 0xffff0000, 12});
    if (gpio216_zero_ && icu25_written_ && address == 0x0c150214 && request.select == 12 &&
        latches_.count(0x0c150218) && (latches_.at(0x0c150218).written & 0xffff0000) == 0xffff0000)
        latches_.emplace(address, Latch{0, 0xffff0000, 12});
    // Experimental hypothesis: low GPIO 0x214 starts at zero after the
    // previously observed upper-halfword initialization. Not hardware evidence.
    if (gpio214_low_zero_ && icu25_written_ && address == 0x0c150214 && request.select == 3 &&
        latches_.count(address) && (latches_.at(address).written & 0xffff0000) == 0xffff0000) {
        Latch& gpio = latches_.at(address);
        if (!(gpio.written & 0xffff)) { gpio.allowed |= 3; gpio.written |= 0xffff; }
    }
    if (pupf00a_zero_ && icu46_write_ && cbus_written_.count(0x8d) && address == 0x0c14f008 && request.select == 12) {
        Latch& pup = latches_.at(address);
        if (!(pup.written & 0xffff0000)) { pup.allowed = 15; pup.written |= 0xffff0000; }
    }
    if (sysc0c14_zero_ && address == 0x0c120c14 && icu46_write_ && cbus_written_.count(0x8d) &&
        (latches_.at(0x0c14f008).written & 0xffff0000) == 0xffff0000) {
        if (request.select != 15) { reason_ = "unobserved system-control width"; return false; }
        latches_.emplace(address, Latch{0, 0xffffffff, 15});
    }
    // Separate opt-in reset hypothesis for the low half of 0x0c14f004.
    if (pupf004_low_zero_ && address == 0x0c14f004 && request.select == 3 &&
        icu46_write_ && cbus_written_.count(0x8d) && probe_regs_.count(address)) {
        device = "assumed_pupf004_low";
        if (request.write) pupf004_low_value_ = request.data & 0xffff;
        data = pupf004_low_value_;
        return true;
    }
    auto probe = probe_regs_.find(address);
    if (probe != probe_regs_.end() && address == 0x0c150204 && probe->second.select == 12 && request.select == 12) {
        if (!icu46_write_ || !cbus_written_.count(0x8d) || !request.write || ((request.data & 0xffff0000) != 0x01800000 && !(gpio206_extra_write_ && (request.data & 0xffff0000) == 0x00060000))) {
            reason_ = "unobserved GPIO upper halfword access"; return false;
        }
        device = "assumed_register_probe"; data = 0; return true;
    }
    if (probe != probe_regs_.end() && address != 0x0c150204) {
        if (latches_.count(address)) { reason_ = "register probe overlaps modeled latch"; return false; }
        if (!icu46_write_ || !cbus_written_.count(0x8d) || request.select != probe->second.select) {
            reason_ = "explicit register probe state or width mismatch"; return false;
        }
        device = "assumed_register_probe";
        if (request.write) probe->second.current = request.data;
        data = probe->second.current & byte_mask(request.select); return true;
    }
    auto latch = latches_.find(address);
    if (latch != latches_.end()) {
        device = "observed_boot_latch";
        Latch& reg = latch->second;
        if (request.select & ~reg.allowed) {
            reason_ = "unobserved register access width"; return false;
        }
        const uint32_t mask = byte_mask(request.select);
        if (request.write) {
            reg.value = (reg.value & ~mask) | (request.data & mask);
            reg.written |= mask;
        } else if ((reg.written & mask) != mask) {
            reason_ = "unknown register reset value"; return false;
        }
        data = reg.value;
        if (ideal_clocks_ && address == 0x0c149000 && !request.write) {
            if (reg.value != 0x2210) {
                reason_ = "unmodeled PLL control/status combination"; return false;
            }
            data |= 1;
            device = "ideal_pll_status";
        }
        return true;
    }
    if (address >= ram_base_ && uint64_t(address - ram_base_) + 4 <= ram_.size()) {
        device = "physical_ram";
        const size_t offset = address - ram_base_;
        for (unsigned i = 0; i < 4; ++i) {
            if (request.write && (request.select & (1u << i)))
                ram_[offset+i] = (request.data >> (8*i)) & 255;
            data |= uint32_t(ram_[offset+i]) << (8*i);
        }
        return true;
    }
    for (Flash& flash : flash_) {
        if (address < flash.base || address - flash.base >= 0x01000000) continue;
        if (request.write) {
            device = "flash_command";
            return flash_command(flash, request);
        }
        if (flash.identify) {
            device = "flash_identify";
            return flash_identify(flash, request, data);
        }
        break;
    }
    // Counterfactual: only the two observed CS2 probe halfwords appear erased.
    // The physical contents and dump placement are unknown.
    if (!request.write && address == 0x04000000 && (request.select == 3 || request.select == 12)) {
        device = "assumed_cs2_probe_erased"; data = 0xffffffff; return true;
    }
    for (const Bank& bank : banks_) {
        if (address >= bank.address && uint64_t(address - bank.address) + 4 <= bank.size) {
            device = "physical_flash_array";
            if (request.write) { reason_ = "unmodeled write to a ROM bank"; return false; }
            const size_t offset = bank.offset + address - bank.address;
            if (offset + 4 > rom_bytes_ + rom_tail_.size()) {
                reason_ = "physical ROM bank has no corresponding dump bytes"; return false;
            }
            if (offset >= rom_bytes_) {
                device = "reconstructed_flash_tail";
                ++rom_tail_reads_;
            }
            for (unsigned i = 0; i < 4; ++i)
                data |= uint32_t(offset+i < rom_bytes_ ? rom_[offset+i] : rom_tail_[offset+i-rom_bytes_]) << (8*i);
            return true;
        }
    }
    reason_ = "unmapped physical address";
    return false;
}

void BootProfile::report(std::ostream& output) const {
    output << "{\"name\":\"" << kind_ << "\",\"table_offset\":" << std::dec << table_
           << ",\"flash_manufacturer\":" << manufacturer_ << ",\"flash_device\":" << device_
           << ",\"ram_base\":" << ram_base_ << ",\"ram_size\":" << ram_.size()
           << ",\"ideal_clocks\":" << (ideal_clocks_ ? "true" : "false")
           << ",\"boot_io_probe\":" << (boot_io_probe_ ? "true" : "false")
           << ",\"ideal_boot_cbus_transactions\":" << cbus_transactions_
           << ",\"boot_cbus_command\":" << cbus_command_
           << ",\"boot_cbus_configuration\":" << cbus_config_
           << ",\"uem_adc_channel\":" << uem_adc_channel_
           << ",\"uem_adc_result_reads\":" << adc_result_reads_
           << ",\"sysc0c14_zero_assumed\":" << (sysc0c14_zero_ ? "true" : "false")
           << ",\"pupf00a_zero_assumed\":" << (pupf00a_zero_ ? "true" : "false")
           << ",\"icu46_write_assumed\":" << (icu46_write_ ? "true" : "false")
           << ",\"cbus8d_initial_zero_assumed\":" << (cbus8d_zero_ ? "true" : "false")
           << ",\"cbus80_input_assumed\":" << cbus80_input_
           << ",\"cbus82_readback_assumed\":" << (cbus82_readback_ ? "true" : "false")
           << ",\"uif102_write_assumed\":" << (uif102_write_ ? "true" : "false")
           << ",\"gpio216_zero_assumed\":" << (gpio216_zero_ ? "true" : "false")
           << ",\"gpio214_low_zero_assumed\":" << (gpio214_low_zero_ ? "true" : "false")
           << ",\"gpio21a_zero_assumed\":" << (gpio21a_zero_ ? "true" : "false")
           << ",\"gpio210_low_zero_assumed\":" << (gpio210_low_zero_ ? "true" : "false")
           << ",\"icu25_write_assumed\":" << (allow_icu25_ ? "true" : "false")
           << ",\"uif_8000_write_assumed\":" << (allow_uif_8000_ ? "true" : "false")
           << ",\"extra_cbus_write2_assumed\":" << extra_cbus_write2_
           << ",\"extra_cbus_write_assumed\":" << extra_cbus_write_
           << ",\"uem_status35_assumed\":" << uem_status35_
           << ",\"uem_status36_assumed\":" << uem_status36_
           << ",\"uem_power_status_assumed\":" << uem_power_status_
           << ",\"timer_irq_delay\":" << timer_irq_delay_
           << ",\"timer_remaining\":" << timer_remaining_
           << ",\"timer_irq_cycle\":" << timer_irq_cycle_
           << ",\"timer_irq_pending\":" << (timer_irq_pending_ ? "true" : "false")
           << ",\"timer_irq_enabled\":" << (timer_irq_enabled_ ? "true" : "false")
           << ",\"timer_irq_timing_verified\":false"
           << ",\"boot_io_semantics_verified\":false"
           << ",\"reconstructed_tail_bytes\":" << rom_tail_.size()
           << ",\"reconstructed_tail_reads\":" << rom_tail_reads_
           << ",\"extension_metadata_verified\":false"
           << ",\"lcd_probe\":" << (lcd_probe_ ? "true" : "false")
           << ",\"lcd_transport\":{\"headers\":" << lcd_headers_
           << ",\"data_words\":" << lcd_data_words_ << ",\"status_reads\":" << lcd_status_reads_
           << ",\"header\":" << lcd_header_ << ",\"control\":" << lcd_control_
           << ",\"reset_values_verified\":false,\"timing_verified\":false,\"pixel_format_verified\":false}"
           << ",\"rom_mapping_verified\":false,\"register_semantics_verified\":false,\"rom_banks\":[";
    bool first = true;
    for (const Bank& bank : banks_) {
        output << (first ? "" : ",") << "{\"address\":" << bank.address
               << ",\"size\":" << bank.size << ",\"file_offset\":" << bank.offset << "}";
        first = false;
    }
    output << "],\"uem_adc_inputs\":[";
    first = true;
    for (const auto& input : adc_inputs_) {
        output << (first ? "" : ",") << "{\"channel\":" << input.first
               << ",\"value\":" << input.second << ",\"verified\":false}";
        first = false;
    }
    unsigned code_bytes = 0;
    for (uint8_t written : code_scratch_written_) code_bytes += written;
    output << "],\"flash_chips\":[";
    first = true;
    for (const Flash& flash : flash_) {
        output << (first ? "" : ",") << "{\"address\":" << flash.base
               << ",\"manufacturer\":" << flash.manufacturer << ",\"device\":" << flash.device
               << ",\"id2\":" << flash.id2 << ",\"id3\":" << flash.id3
               << ",\"handshake\":" << flash.handshake
               << ",\"burst_configured\":" << (flash.burst_configured ? "true" : "false")
               << ",\"burst_configuration\":" << flash.burst_configuration
               << ",\"identity_verified_on_device\":false}";
        first = false;
    }
    output << "],\"code_scratch\":{\"address\":" << code_scratch_base
           << ",\"size\":" << code_scratch_.size() << ",\"written_bytes\":" << code_bytes
           << ",\"backing_verified\":false},\"explicit_register_probes\":[";
    bool first_probe = true;
    for (const auto& item : probe_regs_) {
        output << (first_probe ? "" : ",") << "{\"address\":" << item.first << ",\"initial\":" << item.second.initial
               << ",\"current\":" << item.second.current << ",\"select\":" << unsigned(item.second.select) << ",\"verified\":false}";
        first_probe = false;
    }
    output << "],\"written_registers\":[";
    first = true;
    for (const auto& item : latches_) if (item.second.written) {
        output << (first ? "" : ",") << "{\"address\":" << item.first
               << ",\"value\":" << item.second.value << ",\"known_mask\":" << item.second.written << "}";
        first = false;
    }
    output << "]}";
}

// Local experimental checkpoints: same ABI and identical model configuration only.
namespace {
template<class T> void state_write(std::ostream& out, const T& v) { out.write(reinterpret_cast<const char*>(&v), sizeof(v)); }
template<class T> void state_read(std::istream& in, T& v) { in.read(reinterpret_cast<char*>(&v), sizeof(v)); }
}
void BootProfile::save_state(std::ostream& out) const {
    if (uif_written_ || icu25_written_ || !probe_regs_.empty()) throw std::runtime_error("post-UIF snapshots unsupported by this state version");
    const uint32_t version = 0x4e470001; state_write(out, version);
    state_write(out, rom_tail_reads_); state_write(out, cbus_stage_); state_write(out, cbus_transactions_);
    state_write(out, cbus_config_); state_write(out, cbus_command_); state_write(out, uem_adc_channel_);
    state_write(out, adc_result_reads_); state_write(out, timer_remaining_); state_write(out, timer_elapsed_);
    state_write(out, timer_irq_cycle_); state_write(out, timer_started_); state_write(out, timer_irq_enabled_); state_write(out, timer_irq_pending_);
    state_write(out, lcd_header_); state_write(out, lcd_control_); state_write(out, lcd_header_written_); state_write(out, lcd_control_written_);
    state_write(out, lcd_headers_); state_write(out, lcd_data_words_); state_write(out, lcd_status_reads_);
    state_write(out, flash_); state_write(out, code_scratch_); state_write(out, code_scratch_written_);
    uint64_t n=ram_.size(); state_write(out,n); out.write(reinterpret_cast<const char*>(ram_.data()),n);
    n=cbus_written_.size(); state_write(out,n); for (const auto& item:cbus_written_) {state_write(out,item.first);state_write(out,item.second);}
    n=latches_.size(); state_write(out,n); for (const auto& item:latches_) {state_write(out,item.first);state_write(out,item.second);}
    if (!out) throw std::runtime_error("failed to save board checkpoint");
}
void BootProfile::load_state(std::istream& in) {
    uint32_t version=0; state_read(in,version); if (version != 0x4e470001) throw std::runtime_error("board checkpoint version mismatch");
    state_read(in,rom_tail_reads_); state_read(in,cbus_stage_); state_read(in,cbus_transactions_);
    state_read(in,cbus_config_); state_read(in,cbus_command_); state_read(in,uem_adc_channel_);
    state_read(in,adc_result_reads_); state_read(in,timer_remaining_); state_read(in,timer_elapsed_);
    state_read(in,timer_irq_cycle_); state_read(in,timer_started_); state_read(in,timer_irq_enabled_); state_read(in,timer_irq_pending_);
    state_read(in,lcd_header_); state_read(in,lcd_control_); state_read(in,lcd_header_written_); state_read(in,lcd_control_written_);
    state_read(in,lcd_headers_); state_read(in,lcd_data_words_); state_read(in,lcd_status_reads_);
    state_read(in,flash_); state_read(in,code_scratch_); state_read(in,code_scratch_written_);
    uint64_t n=0; state_read(in,n); if (n!=ram_.size()) throw std::runtime_error("checkpoint RAM size mismatch"); in.read(reinterpret_cast<char*>(ram_.data()),n);
    state_read(in,n); if(n>1024) throw std::runtime_error("invalid checkpoint CBUS entries"); cbus_written_.clear();
    for(uint64_t i=0;i<n;++i){uint16_t k,v;state_read(in,k);state_read(in,v);cbus_written_[k]=v;}
    state_read(in,n); if(n>8192) throw std::runtime_error("invalid checkpoint latch entries"); latches_.clear();
    for(uint64_t i=0;i<n;++i){uint32_t k;Latch v;state_read(in,k);state_read(in,v);latches_[k]=v;}
    if (!in) throw std::runtime_error("truncated board checkpoint");
}
