#include "boot_profile.h"
#include "nos_stub_blob.h"
#include <cstdio>
#include <iomanip>
#include <stdexcept>
#include <cctype>
#include <sstream>

namespace {
constexpr uint32_t code_scratch_base = 0x0c004748;
constexpr uint32_t probe_base = 0x02000000;
// Cycles from unit-0x60 arm (or counter re-arm) to compare match. The real
// compare is 0x186 ticks of an unknown prescale; the FIQ pump is purely
// event-driven, so any delay is functionally correct. Chosen small because
// LFFS's first-boot block stamping programs tens of thousands of halfwords,
// each paying this delay (2.5e9-budget run measured ~2800 cycles/halfword at
// delay 2000, storm unfinished; 128 keeps the pump past medint's arm
// sequence while making the storm ~5x faster).
constexpr uint64_t kUnit60Delay = 128;
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
    ++cycles_;
    // Unit 0x60 countdown is independent of the boot one-shot timer model so
    // the hypothesis is testable without a timer-irq-delay configuration.
    if (unit60_remaining_ && --unit60_remaining_ == 0) {
        unit60_pending_ = true;
        ++unit60_irqs_;
    }
    if (unit1_running_ && ++unit1_elapsed_ >= unit1_compare_) {
        unit1_running_ = false; unit1_elapsed_ = 0;
        uem_irq_pending_ = true;            // shared ICU source-1 pending
        ++unit1_irqs_;
    }
    if (!timer_irq_delay_) return;
    ++timer_elapsed_;
    if (timer_remaining_ && --timer_remaining_ == 0) {
        timer_irq_pending_ = true;
        timer_irq_cycle_ = timer_elapsed_;
    }
    // Periodic hypothesis: reschedule immediately on expiry (6600 nk_bus_tick
    // style) and present status bit 0; acknowledgement clears only the status.
    if (periodic_remaining_ && --periodic_remaining_ == 0) {
        timer_irq_pending_ = true;
        timer_irq_cycle_ = timer_elapsed_;
        ++periodic_irqs_;
        auto status = latches_.find(0x0c120a08);
        if (status != latches_.end()) status->second.value = 1;
        periodic_remaining_ = periodic_period_;
    }
}

uint32_t BootProfile::word(size_t offset) const {
    if (offset + 4 > rom_bytes_) throw std::runtime_error("truncated boot bank table");
    return uint32_t(rom_[offset]) | uint32_t(rom_[offset+1]) << 8 |
           uint32_t(rom_[offset+2]) << 16 | uint32_t(rom_[offset+3]) << 24;
}

BootProfile::BootProfile(const std::vector<uint8_t>& rom, size_t rom_bytes, const std::string& kind, bool ideal_clocks, bool lcd_probe, const std::vector<uint8_t>& rom_tail, bool boot_io_probe, const std::map<unsigned, unsigned>& adc_inputs, uint64_t timer_irq_delay, int uem_power_status, int uem_status36, int uem_status35, int extra_cbus_write, int extra_cbus_write2, bool allow_uif_8000, bool allow_icu25, bool gpio210_low_zero, bool gpio21a_zero, bool gpio216_zero, bool uif102_write, bool cbus82_readback, int cbus80_input, bool cbus8d_zero, bool icu46_write, bool pupf00a_zero, bool sysc0c14_zero, const std::map<uint32_t,std::pair<uint32_t,uint8_t>>& probe_regs, bool gpio214_low_zero, bool pupf004_low_zero, bool gpio206_extra_write, bool sysc74_write3, bool gpio24_28_write1, bool timer_compare_probe, bool sysc50_44_probe, bool icu1c8_probe, bool timer_periodic, bool block14d_probe, bool debug59_sink, const std::map<int,int>& cbus_inputs, bool nos_entry_stub, bool keypad_gpio, bool icu_banks, bool timer_units, bool cdrive_flash, bool unit60_irq3, const std::vector<uint8_t>& nos_image, bool uem_irq_source1, bool epbus_clkblk, const std::vector<uint8_t>& cdrive_image, const std::map<uint32_t,uint32_t>& nos_iat, bool nos_periph4000)
    : rom_(rom), rom_bytes_(rom_bytes), rom_tail_(rom_tail), kind_(kind), ideal_clocks_(ideal_clocks), lcd_probe_(lcd_probe), boot_io_probe_(boot_io_probe), adc_inputs_(adc_inputs), timer_irq_delay_(timer_irq_delay) {
    allow_uif_8000_ = allow_uif_8000; allow_icu25_ = allow_icu25; gpio210_low_zero_ = gpio210_low_zero; gpio21a_zero_ = gpio21a_zero; gpio216_zero_ = gpio216_zero; gpio214_low_zero_ = gpio214_low_zero; pupf004_low_zero_ = pupf004_low_zero; gpio206_extra_write_ = gpio206_extra_write; sysc74_write3_ = sysc74_write3; gpio24_28_write1_ = gpio24_28_write1; timer_compare_probe_ = timer_compare_probe; sysc50_44_probe_ = sysc50_44_probe; icu1c8_probe_ = icu1c8_probe; uif102_write_ = uif102_write; cbus82_readback_ = cbus82_readback; cbus80_input_ = cbus80_input; cbus8d_zero_ = cbus8d_zero; icu46_write_ = icu46_write; pupf00a_zero_ = pupf00a_zero; sysc0c14_zero_ = sysc0c14_zero; timer_periodic_ = timer_periodic; block14d_probe_ = block14d_probe; nos_periph4000_ = nos_periph4000; debug59_sink_ = debug59_sink; cbus_inputs_ = cbus_inputs; nos_entry_stub_ = nos_entry_stub; keypad_gpio_ = keypad_gpio;
    if (nos_entry_stub_) {
        // off0 vptr -> all-ret0 vtable; off0x10/0x14 empty self-linked queue
        // head (&object+0x10); off0x18 queue iOffset = 4; everything else zero.
        power_model_[0] = 0x5149d0c0u;          // vptr (iface_vt)
        power_model_[4] = 0x5149e000u + 0x10;   // queue head next -> &head
        power_model_[5] = 0x5149e000u + 0x10;   // queue head prev -> &head
        power_model_[6] = 4;                      // iOffset
        power_model_init_ = true;
    } icu_banks_ = icu_banks; timer_units_ = timer_units; cdrive_flash_ = cdrive_flash; unit60_irq3_ = unit60_irq3; uem_irq_source1_ = uem_irq_source1; epbus_clkblk_ = epbus_clkblk;
    cdrive_image_ = cdrive_image; nos_iat_ = nos_iat;
    if (!cdrive_image_.empty()) { cdrive_.assign(0x400000, 0xff); size_t n = cdrive_image_.size() < cdrive_.size() ? cdrive_image_.size() : cdrive_.size(); for (size_t i=0;i<n;++i) cdrive_[i]=cdrive_image_[i]; }
    nos_image_ = nos_image;
    // nos-image + nos-entry-stub now COEXIST (2026-10-30): the stub keeps the
    // boot-time windows it has proven (blob [0x9d000,0x9d288) incl. the entry
    // B at 0x9d284, power model at 0x9e000), and the real THC NOS image
    // serves the module body past the blob — nosdriver.ldd statically imports
    // two NOS body functions (IAT [0x511b4028]=NOS+0x37d0 register_handler,
    // [0x511b4030]=NOS+0x414c ctor) that only real code can provide.
    if (!nos_image_.empty() && !timer_periodic_)
        throw std::runtime_error("nos-image requires the periodic timer experiment");
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
    if (timer_periodic_ && !(icu1c8_probe_ && timer_compare_probe_ && timer_irq_delay_))
        throw std::runtime_error("periodic timer hypothesis requires the timer, compare and ICU1c8 probes");
    if (block14d_probe_ && !timer_periodic_)
        throw std::runtime_error("block 0x14d probe requires the periodic timer hypothesis");
    if (debug59_sink_ && !block14d_probe_)
        throw std::runtime_error("debug output sink requires the block 0x14d probe");
    if (nos_entry_stub_ && !timer_periodic_)
        throw std::runtime_error("NOS entry stub requires the periodic timer experiment");
    for (const auto& item : cbus_inputs_)
        if (item.first < 0 || item.first > 0xff || item.second < 0 || item.second > 65535 || !timer_periodic_)
            throw std::runtime_error("CBUS inputs require the periodic timer, register 0..0xff and 16-bit values");
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
        table_ = 0x830; manufacturer_ = 1; device_ = 0x257e;
    } else throw std::runtime_error("unknown experimental boot profile");
    // CS0/CS2 use the AM29N643/Am29BDS643G identity from the NEM-4
    // schematic and AMD datasheet. CS1 remains the selected hypothesis.
    // The handshake option is explicit model configuration, not a phone read.
    flash_[0] = {0, 1, 0x257e, 0x2502, 0x2500, 0x42, false, true};
    flash_[1] = {probe_base, manufacturer_, device_, 0x2502, 0x2500, 0x42,
                 kind == "intel8", kind == "amd16"};
    flash_[2] = {0x04000000, 1, 0x257e, 0x2502, 0x2500, 0x42, false, true};
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
    // Boot-latch register 0x40: read (never written first) by a kernel
    // hw-info query after nosdriver init (latch-read ordinal 0x50324e1c,
    // observed cycle 3.431e9). Zero reset is a hypothesis.
    latches_.emplace(0x08000040, Latch{0, 0xffffffff, 15});
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

// C: drive flash sector map (type 4, 4 MiB: two 2 MiB dies, each 64 KiB sectors
// with 4x16 KiB boot sectors at the die top). Returns [base,end) of the sector
// containing byte offset `off`. Matches medint's 0x50385380 geometry.
void BootProfile::cdrive_sector(uint32_t off, uint32_t& base, uint32_t& end) const {
    const uint32_t die = off & 0x200000;              // which 2 MiB die
    const uint32_t in = off - die;                    // offset within die
    if (in >= 0x1f0000) {                             // top 64 KiB = 4x16 KiB
        base = die + 0x1f0000 + ((in - 0x1f0000) & ~0x3fffu);
        end = base + 0x4000;
    } else {
        base = die + (in & ~0xffffu);
        end = base + 0x10000;
    }
}

// Internal user flash (C: drive, LFFS). Minimal AMD x16 command FSM over a 4 MiB
// RAM overlay (0xFF = erased). Models only what medint.pdd exercises.
bool BootProfile::cdrive_access(const BootBusRequest& request, uint32_t& data, std::string& device) {
    if (cdrive_.empty()) cdrive_.assign(0x400000, 0xff);
    // Array read (any byte select): the x16 flash is mapped so the aligned
    // 32-bit word carries two adjacent cells and the bus byte lanes pick out
    // halfword or byte reads (LFFS whole-word volume reads, and byte reads
    // of file data, observed at 1.5176e9). Only valid in array-read mode (no
    // pending command/autoselect/erase, which are halfword-protocol).
    if (!request.write &&
        !cdrive_autoselect_ && cdrive_unlock_ == 0 &&
        !(cdrive_erase_end_ > cdrive_erase_base_)) {
        const uint32_t off = (request.address & ~3u) - 0x02400000;
        data = uint32_t(cdrive_[off]) | uint32_t(cdrive_[off+1]) << 8 |
               uint32_t(cdrive_[off+2]) << 16 | uint32_t(cdrive_[off+3]) << 24;
        device = "cdrive_flash"; return true;
    }
    // Bare word-width array write (LFFS, 1.51763e9: word 6 to 0x02400540 in
    // read mode): AMD command cycles are halfword, so a word write is never
    // a command; the chip ignores it and the array is unchanged (programming
    // physically requires the unlock+A0 sequence). Accepted and ignored only
    // in plain read mode; mid-protocol word writes still stop the run.
    if (request.write && request.select == 15 &&
        !cdrive_program_ && cdrive_unlock_ == 0 && !cdrive_autoselect_ &&
        !cdrive_erase_armed_ && !(cdrive_erase_end_ > cdrive_erase_base_)) {
        device = "cdrive_flash"; return true;
    }
    if (request.select != 3 && request.select != 12) {
        reason_ = "C: flash access width outside the halfword protocol"; return false;
    }
    const unsigned shift = request.select == 12 ? 16 : 0;
    const uint32_t off = ((request.address & ~3u) + shift / 8) - 0x02400000;
    const uint16_t value = (request.data >> shift) & 0xffff;
    device = "cdrive_flash";
    if (request.write) {
        if (cdrive_program_) {                        // data cycle of a program
            cdrive_[off] = value & 0xff; cdrive_[off+1] = value >> 8;
            cdrive_program_ = false; cdrive_unlock_ = 0; ++cdrive_writes_; return true;
        }
        if (value == 0xf0 || value == 0xff) {         // reset -> read array
            cdrive_unlock_ = 0; cdrive_autoselect_ = false; cdrive_erase_armed_ = false; return true;
        }
        if (value == 0x60) return true;               // blind sector lock/unlock
        if (value == 0xb0) {                          // erase suspend -> finish now
            if (cdrive_erase_end_ > cdrive_erase_base_) {
                for (uint32_t a = cdrive_erase_base_; a < cdrive_erase_end_; ++a) cdrive_[a] = 0xff;
                cdrive_erase_base_ = cdrive_erase_end_ = 0; cdrive_erase_reads_ = 0;
            }
            return true;
        }
        if (value == 0x30 && cdrive_erase_armed_ && cdrive_unlock_ == 2) {
            cdrive_sector(off, cdrive_erase_base_, cdrive_erase_end_);
            cdrive_erase_reads_ = 0; cdrive_erase_armed_ = false; cdrive_unlock_ = 0; ++cdrive_erases_;
            return true;                              // status reads drive the actual erase
        }
        if ((off & 0xfff) == 0xaaa && value == 0xaa) { cdrive_unlock_ = 1; return true; }
        if (cdrive_unlock_ == 1 && (off & 0xfff) == 0x554 && value == 0x55) { cdrive_unlock_ = 2; return true; }
        if (cdrive_unlock_ == 2 && (off & 0xfff) == 0xaaa && value == 0x90) { cdrive_autoselect_ = true; cdrive_unlock_ = 0; return true; }
        if (cdrive_unlock_ == 2 && value == 0xa0) { cdrive_program_ = true; cdrive_unlock_ = 0; return true; }
        if (cdrive_unlock_ == 2 && (off & 0xfff) == 0xaaa && value == 0x80) { cdrive_erase_armed_ = true; cdrive_unlock_ = 0; return true; }
        reason_ = "unmodeled C: flash command"; return false;
    }
    // Reads.
    const uint32_t mask = shift ? 0xffff0000u : 0x0000ffffu;
    if (cdrive_autoselect_) {                          // protect-verify: SA+4 must read 0
        const unsigned so = off & 0xf;
        const uint16_t id = so == 0 ? 0x0001 : so == 2 ? 0x257e : 0x0000;
        data = uint32_t(id) << shift; (void)mask; return true;
    }
    if (cdrive_erase_end_ > cdrive_erase_base_ && off >= cdrive_erase_base_ && off < cdrive_erase_end_) {
        if (cdrive_erase_reads_ == 0) {               // first poll: DQ7=0,DQ3=1 (busy-but-progressing)
            ++cdrive_erase_reads_; data = uint32_t(0x0008) << shift; return true;
        }
        for (uint32_t a = cdrive_erase_base_; a < cdrive_erase_end_; ++a) cdrive_[a] = 0xff;
        cdrive_erase_base_ = cdrive_erase_end_ = 0; cdrive_erase_reads_ = 0;
    }
    data = (uint32_t(cdrive_[off]) | uint32_t(cdrive_[off+1]) << 8) << shift;
    return true;
}

bool BootProfile::flash_command(Flash& flash, const BootBusRequest& request) {
    if (request.select != 3 && request.select != 12) {
        reason_ = "flash command width is outside the observed halfword protocol";
        return false;
    }
    const unsigned shift = request.select == 12 ? 16 : 0;
    const uint32_t address = (request.address & ~3u) + shift / 8 - flash.base;
    const uint16_t value = (request.data >> shift) & 0xffff;
    // NOS PMM driver (0x5167edxx..0x5167f0xx, Intel CUI on this array):
    // 0x40 program setup -> data cycle; status-register reads until bit 7;
    // 0x50 clear status; 0x60 lock-op setup then 0x01 set / 0xD0 clear;
    // 0xFF/0xF0 back to array. State + programmed halfwords live in
    // block14d_ (serialized map) so the Flash struct layout is unchanged:
    // state word key 0xff000000|base (bit0 SR-mode, bit1 program-pending,
    // bit2 lock-op), overlay key 0x80000000|halfword-address.
    uint32_t& pmm = block14d_[0xff000000u | flash.base];
    // DATA cycles take priority over any command-value decoding: a program
    // data halfword may hold command-looking values (observed: the PMM
    // driver programs 0x0060 at 0x7f003e; v1 of this model misread it as a
    // lock-op and the driver's verify failed -> "PMM Write failed").
    if (flash.unlock == 6) {     // AMD program data cycle
        uint32_t& cell = block14d_[0x80000000u | (flash.base + (address & ~1u))];
        const bool had = (cell >> 16) == 1;
        cell = 0x00010000u | (had ? (cell & value & 0xffffu) : value);
        flash.unlock = 0; return true;
    }
    if (pmm & 2u) {              // Intel program data cycle
        uint32_t& cell = block14d_[0x80000000u | (flash.base + (address & ~1u))];
        const bool had = (cell >> 16) == 1;
        cell = 0x00010000u | (had ? (cell & value & 0xffffu) : value);
        pmm = (pmm & ~2u) | 1u;  // status-register mode until 0xFF/0xF0/0x50
        return true;
    }
    if (value == 0xff || value == 0xf0) {
        flash.identify = false; flash.unlock = 0; pmm = 0; return true;
    }
    if (value == 0x40) { pmm |= 2u; return true; }
    if (value == 0x50) { pmm &= ~1u; return true; }
    if (value == 0x60) { pmm |= 4u; return true; }
    if ((pmm & 4u) && (value == 0x01 || value == 0xd0)) { pmm &= ~4u; return true; }
    if (flash.intel) {
        if (value == 0x90) { flash.identify = true; return true; }
    } else {
        // Unlock-cycle addresses decode A10:0 only (boot code writes the
        // short 0xaaa/0x554 form, the NOS PMM driver 0xaaa/0x1554 - both
        // are the same A10:0 pattern; observed boot-v15-auth7 800966412).
        if ((address & 0x7ff) == 0x2aa && value == 0xaa) {
            flash.unlock = 1; return true;
        }
        if (flash.unlock == 1 && (address & 0x7ff) == 0x554 && value == 0x55) {
            flash.unlock = 2; return true;
        }
        if (flash.unlock == 2 && (address & 0x7ff) == 0x2aa && value == 0x90) {
            flash.identify = true; flash.unlock = 0; return true;
        }
        // AMD program: AA/55/A0 then the data halfword at the target
        // address (NOS PMM driver, boot-v15-auth7 800966453). The data
        // cycle itself is handled at the top of this function.
        if (flash.unlock == 2 && (address & 0x7ff) == 0x2aa && value == 0xa0) {
            flash.unlock = 6; return true;
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
        // Authentic path (real descrambled NOS, 2026-10-31): two observed
        // waits under control 0x40-then-0x20:
        //  - NOS bring-up 0x514a5b60, loop 0x514a5b80..8c TST #0x02000000
        //    (bit 25; raw word e3100402);
        //  - second bring-up 0x514c138c (boot-v15-clockloop2, 800.85M),
        //    loop 0x514c13ac..b2 ANDs #0x04000000 (bit 26; movs #0x80,
        //    lsls #19) and spun 38.8M cycles on bit 25 alone.
        // Model both locks set; each loop tests only its own bit.
        else if (control.value == 0x20 || control.value == 0x40) data = 0x06000000;
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
                mode != 0x02140000 && request.data != 0x07800000 && mode != 0x07840000) {
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
        // 0x0784 is a display READBACK header (lcd.ldd 0x50400978: command
        // 0x66 then two data-register reads; the checked byte must be
        // <= 0x7f). No panel is modeled, so reads return 0 (check passes).
        if (address == 0x0c121208 && !request.write && lcd_header_written_ &&
            (lcd_header_ & 0xffff0000) == 0x07840000) {
            data = 0; ++lcd_status_reads_; return true;
        }
        reason_ = "unmodeled LCD transport read or transfer state"; return false;
    }
    if (icu46_write_ && icu25_written_ && cbus_written_.count(0x8d) && address == 0x0c120148 &&
        request.write && request.select == 15 && request.data == 0x4000) {
        device = "assumed_icu46_write"; return true;
    }
    // ICU enable-set/clear writes to 0x0c120108/0x10c that are not the timer-0
    // specific values (enable source 0 = 1, ICU25 = 0x02000000, handler clear =
    // 1) are generic interrupt-enable writes (e.g. enabling IrqTimer1 = bit 1 =
    // value 2); let the ICU enable-bank model handle them instead of the
    // timer-0 handler below.
    const bool defer_to_icu_bank = icu_banks_ && request.write && request.select == 15 &&
        ((address == 0x0c120108 && request.data != 1 && request.data != 0x02000000) ||
         // 0x12010c enable-CLEAR: only data==1 is the timer handler's ack;
         // everything else (incl. 0x02000000, the display driver clearing its
         // ICU25 line at teardown) is an ordinary bank0 clear.
         (address == 0x0c12010c && request.data != 1));
    if (boot_io_probe_ && !defer_to_icu_bank && (address == 0x0c120a04 || address == 0x0c120a08 ||
        address == 0x0c120a10 || address == 0x0c120a18 || address == 0x0c120108 || address == 0x0c12010c)) {
        // ROM 0x3200 writes these exact timer/ICU setup values. Capturing
        // writes does not make a running counter, readback, IRQ or reset state.
        device = "timer_setup_write";
        if (!request.write) {
            if (timer_irq_delay_ && address == 0x0c120a08 && timer_irq_cycle_ && latches_.count(address) && request.select == 15) { data = latches_.at(address).value; device = "assumed_timer_status"; return true; }
            if (timer_irq_delay_ && timer_irq_cycle_ && address == 0x0c120a04 && request.select == 15 && latches_.count(address) && latches_.at(address).value == 2) { data = 2; device = "assumed_timer_status"; return true; }
            // Dispatcher-exit entropy read of timer compare (disassembly
            // 0x503228c8 path reads 0x58120a10; only bit 0 is consumed).
            if (timer_periodic_ && address == 0x0c120a10 && request.select == 15 && latches_.count(address)) { data = latches_.at(address).value; device = "assumed_timer_status"; return true; }
            reason_ = "timer/interrupt register read semantics are not modeled"; return false;
        }
        const uint32_t expected = address == 0x0c120a04 ? 2 : address == 0x0c120108 ? 1 :
                                  address == 0x0c120a08 ? 0 : 0x0115b5c0;
        const bool irq_ack = timer_irq_delay_ && address == 0x0c120a08 &&
                             request.data == 1 && timer_irq_pending_;
        const bool kernel_reload = timer_irq_delay_ && timer_irq_cycle_ && address == 0x0c120a18 &&
                                   request.data == 0x632ea && latches_.count(0x0c120a04) &&
                                   latches_.at(0x0c120a04).value == 2;
        const bool compare_probe = timer_compare_probe_ && sysc74_written_ && timer_irq_cycle_ &&
            address == 0x0c120a10 && request.data == 0x632ea;
        const bool icu25_write = allow_icu25_ && uif_written_ && timer_irq_cycle_ &&
                                  address == 0x0c120108 && request.data == 0x02000000;
        const bool handler_write = timer_irq_delay_ && timer_irq_cycle_ &&
            (((address == 0x0c120a18 || address == 0x0c120a10 || address == 0x0c120a04) && request.data == 0) ||
             (address == 0x0c12010c && request.data == 1));
        if (request.select != 15 || (request.data != expected && !irq_ack && !handler_write && !kernel_reload && !icu25_write && !compare_probe) ||
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
        if (timer_periodic_) {
            // Kernel tick arming (disassembly 0x50322690): reload 0x632ea with
            // control 2 starts the free-running periodic counter. The stale
            // early-boot enable is treated as cleared here; the kernel's own
            // 0x0c120108=1 enable-set delivers the first visible tick. Any
            // accepted status write (the ISR writes 0 at 0x503225c0, the early
            // handler wrote 1) clears a pending expiry.
            if (kernel_reload) { periodic_period_ = request.data; periodic_remaining_ = request.data; timer_irq_enabled_ = false; }
            if (address == 0x0c120a08) timer_irq_pending_ = false;
        }
        latches_[address] = {request.data, 0xffffffff, 15};
        return true;
    }
    // Timer units 1..5 (0x0c120a20..0x0c120abf): RW register latches; the
    // status byte (+0x08) reads 0 (not expired). Unit 0 keeps its periodic-tick
    // model (handled above). No IRQ is generated from these units. Opt-in.
    // Unit 5 (0xaa0..0xabf) observed 2026-10-31: the NOS writes +0x04 = 1
    // right after its clock bring-up (boot-v15-auth7 cycle 729423744).
    if (timer_units_ && request.select == 15 &&
        address >= 0x0c120a20 && address < 0x0c120ac0) {
        const uint32_t slot = (address - 0x0c120a00) & 0x1f;
        const bool unit60 = unit60_irq3_ && address >= 0x0c120a60 && address < 0x0c120a80;
        const bool unit1 = uem_irq_source1_ && address >= 0x0c120a20 && address < 0x0c120a40;
        if (request.write) {
            timer_unit_regs_[address] = request.data;
            // Unit-0x60 flash-pump timer (medint disassembly 0x503865b0 arm,
            // FIQ pump 0x503851bc step): +0x04 control (2 = run, written via
            // kernel helper 0x50324958), +0x08 counter (the pump writes 0
            // here each FIQ step to clear the match and re-arm), +0x10
            // compare (0x186). Compare match = pending level until a counter
            // or control write. The real prescale is unknown; a fixed delay
            // stands in for counting to 0x186.
            if (unit60) {
                unit60_pending_ = false;
                if (slot == 0x04) unit60_remaining_ = request.data == 2 ? kUnit60Delay : 0;
                if (slot == 0x08 && timer_unit_regs_[0x0c120a64] == 2) unit60_remaining_ = kUnit60Delay;
            }
            if (unit1) {
                if (slot == 0x04) { unit1_running_ = request.data != 0; unit1_elapsed_ = 0; }
                if (slot == 0x10) { unit1_compare_ = request.data; unit1_elapsed_ = 0; }
            }
        }
        data = slot == 0x08 ? ((unit60 && unit60_pending_) || (unit1 && uem_irq_pending_) ? 1 : 0) : timer_unit_regs_[address];
        device = "assumed_timer_unit"; return true;
    }
    // IRQ-ICU current registers (disassembly 0x5032287c dispatcher): +0x14
    // reports source+1 for the single modeled pending source, +0x54/+0x94
    // report no secondary-bank sources. Explicit periodic hypothesis only.
    if (timer_periodic_ && timer_irq_cycle_ && !request.write && request.select == 15 &&
        (address == 0x0c120114 || address == 0x0c120154 || address == 0x0c120194)) {
        data = 0;
        if (address == 0x0c120114) {
            if (timer_irq_pending_ && timer_irq_enabled_) data = 1;       // source 0 + 1
            else if (uem_irq()) data = 2;                                 // source 1 + 1
            else if (dma_irq()) data = 8;                                 // source 7 + 1 (LCD DMA done)
        }
        device = "assumed_icu_current"; return true;
    }
    // ICU global interrupt enable-clear/set (0x0c120064 / 0x0c120068): the
    // kernel's global-interrupt helper (0x50324d04) writes 1<<bit here to
    // disable/enable a source across all banks (observed when the display
    // driver sets up its vsync/transfer interrupt, cycle 3.629e9). Modeled as
    // a RW latch pair; no source is driven from it.
    if (icu_banks_ && request.select == 15 &&
        (address == 0x0c120064 || address == 0x0c120068)) {
        if (request.write) {
            if (address == 0x0c120068) icu_global_enable_ |= request.data;   // set
            else icu_global_enable_ &= ~request.data;                        // clear
        }
        data = icu_global_enable_;
        ++icu_bank_accesses_;
        device = "assumed_icu_bank"; return true;
    }
    // ICU config/control registers the display driver programs during frame
    // setup (word accesses via the kernel I/O helpers 0x50324b94/0x50324d04,
    // cycle 3.629e9): the low control block 0x0c120040..0x0c1200ff and the
    // 0x0c120300..0x0c1203ff bank, excluding ranges already handled above
    // (current 0x114/154/194, banks 0x100..0x200, FIQ 0x1c0..0x260, timer
    // units 0xa00+). Modeled as plain RW latches; no interrupt is driven.
    if (icu_banks_ && request.select == 15 &&
        // 0x0c120074 is the SYSC74 register with its own handler (it sets
        // sysc74_written_, which gates the timer compare); never steal it.
        address != 0x0c120074 &&
        ((address >= 0x0c120040 && address < 0x0c120100 && periodic_period_ != 0) ||
         (address >= 0x0c120300 && address < 0x0c120400))) {
        uint32_t& reg = keypad_regs_[address];
        if (request.write) reg = request.data;
        data = reg;
        ++icu_bank_accesses_;
        // LCD DMA channel inside this bank (0x0c120340 block; display driver
        // frame setup observed at 2.3002e9 2026-10-31): 0x354 source PA
        // (SDRAM), 0x360 destination (0x10121208 = LCD data port through the
        // DMA bus window), 0x36c word count - 1 (0x477f = one 176x208 frame),
        // and 0x348 = 2 starts the transfer. The engine copies the frame and
        // raises IRQ source 7 (driver pre-enables bank-0 bit 7 via 0x108).
        // Burst/width registers 0x350/0x358/0x35c/0x364/0x368 are latched
        // but not interpreted. Transfer is instantaneous (ideal clocks).
        if (address == 0x0c120348 && request.write && request.data == 2) run_lcd_dma();
        device = "assumed_icu_bank"; return true;
    }
    // IRQ-ICU enable-set/clear and pending banks (e.g. ekeyb enabling its
    // keypad interrupt). Bank b at base+0x40*b: +0x08 set, +0x0c clear, +0x10
    // pending (read 0, no modelled non-timer source). Timer-specific 0x108/0x10c
    // and the current registers are handled above and never reach here.
    if (icu_banks_ && request.select == 15 && address >= 0x0c120100 && address < 0x0c120200) {
        const uint32_t off = address - 0x0c120100;
        const unsigned bank = off / 0x40, slot = off % 0x40;
        if (bank <= 2 && (slot == 0x08 || slot == 0x0c || slot == 0x10)) {
            if (slot == 0x08) { if (request.write) icu_enable_[bank] |= request.data; data = icu_enable_[bank]; }
            else if (slot == 0x0c) {
                if (request.write) {
                    icu_enable_[bank] &= ~request.data;
                    // The dispatcher acknowledges a taken source by writing
                    // 1<<source here (timer handler writes 1); clear the
                    // matching pending state. Unit 0x60 is a FIQ source and
                    // never appears in these IRQ banks.
                    if (uem_irq_source1_ && bank == 0 && (request.data >> 1 & 1)) uem_irq_pending_ = false;
                    // LCD DMA done ack (source 7)
                    if (bank == 0 && (request.data >> 7 & 1)) dma_done_pending_ = false;
                }
                data = icu_enable_[bank];
            }
            else data = bank == 0 && dma_done_pending_ ? 0x80u : 0;   // +0x10 pending
            ++icu_bank_accesses_;
            device = "assumed_icu_bank"; return true;
        }
    }
    // FIQ fast-status register (FIQ dispatcher 0x5032299c: reads it, tst #7;
    // bit 1 enqueues the fast DFC [0x8000001c]; a nonzero read is acked by
    // writing the value back). No fast source is modeled, so reads return 0
    // (sending the dispatcher to the FIQ-ICU current scan and the DFC-drain
    // check) and ack writes are accepted. Opt-in with the FIQ pump model.
    if (unit60_irq3_ && request.select == 15 && address == 0x0c120050) {
        data = 0;
        device = "assumed_fiq_status"; return true;
    }
    // FIQ-ICU banks (kernel enable ordinal 0x50324898 writes 1<<src to
    // +0x08 at 0x0c1201c8/0x208/0x248; disable ordinal 0x503248f0 writes
    // +0x0c; the medint FIQ pump 0x503851bc reads pending at +0x10 and tests
    // bit 3, and the IRQ-side dispatcher 0x503229a0 reads current at +0x14,
    // value = source+1). So +0x08 is enable-SET and +0x0c enable-CLEAR —
    // the earlier model had the polarity inverted, which kept the unit-0x60
    // source gated off. The boot-time 0x1201c8=0x08000000 write (bit 27,
    // FiqAPIIOAbort) now latches into the mask; no bit-27 source is modeled.
    if (unit60_irq3_ && request.select == 15 &&
        address >= 0x0c1201c0 && address < 0x0c120260 &&
        ((address & 0x3f) == 0x08 || (address & 0x3f) == 0x0c ||
         (address & 0x3f) == 0x10 || (address & 0x3f) == 0x14)) {
        const unsigned bank = (address - 0x0c1201c0) / 0x40, slot = address & 0x3f;
        uint32_t& mask = icu_mask2_[bank];
        const uint32_t pending = bank == 0 && unit60_pending_ ? 8u : 0u;
        if (slot == 0x08) { if (request.write) mask |= request.data; data = mask; }
        else if (slot == 0x0c) { if (request.write) mask &= ~request.data; data = mask; }
        else if (slot == 0x10) data = pending;                  // raw pending bits
        else data = pending ? 4 : 0;                            // current = source + 1
        device = "assumed_icu_mask"; return true;
    }
    // epbus clock/power sub-block: RW word latches, reset 0. Opt-in.
    if (epbus_clkblk_ && request.select == 15 &&
        address >= 0x0c120600 && address < 0x0c120700) {
        uint32_t& reg = epbus_clk_regs_[address];
        if (request.write) reg = request.data;
        data = reg;
        device = "assumed_epbus_clk"; return true;
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
                // 0x01 observed from the NOS UEM client (boot-v15-auth7 801406480)
                if (value != 0x10 && value != 8 && value != 7 && value != 0xf && value != 0x8f && value != 0x01) {
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
                const bool extra_rtc_read = (value & 0x100) && cbus_inputs_.count(value & 0xff) && !(value & ~0x1ffu);
                if (extra_write || extra_read || extra_rmw || extra_rtc_read) recognized = true;
                for (uint16_t reg : known) recognized |= (value & 0xff) == reg;
                // Boot-time strictness validates the exact command set. Once
                // the kernel tick is running (periodic_period_), the display
                // and power drivers issue many more UEM/CBUS commands (e.g.
                // 0xa6 with config 0xf during frame setup, cycle 3.645e9);
                // accept any well-formed command then and record the write,
                // rather than enumerate every late register.
                const bool kernel_phase = periodic_period_ != 0;
                if (!kernel_phase &&
                    (cbus_stage_ != 1 || ((value & ~0x13fu) && value != 0x239 && !extra_write && !extra_read && !extra_rmw && !extra_rtc_read) || !recognized)) {
                    reason_ = "unmodeled boot control-bus command"; return false;
                }
                if (kernel_phase && cbus_stage_ != 1) cbus_stage_ = 1;
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
                // UEM IRQ hypothesis: the epbus power-up tail write (reg 0x30)
                // raises the UEM interrupt line (ICU source 1). Kernel phase only.
                if (uem_irq_source1_ && periodic_period_ && (cbus_command_ & 0xff) == 0x30) {
                    uem_irq_pending_ = true; ++uem_irqs_;
                }
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
                    // The NOS triggers conversions through regs 0x2d/0x26
                    // (not the boot code's 0x39 select; observed 822779810).
                    // All supplied channels are mid-scale 512, so serve 512
                    // for untracked conversions rather than refusing.
                    device = "assumed_uem_adc_data";
                    data = 512u << 16;
                    ++adc_result_reads_;
                    return true;
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
            if (auto input = cbus_inputs_.find(cbus_command_ & 0xff); input != cbus_inputs_.end() && !cbus_written_.count(cbus_command_ & 0xff)) {
                device = "assumed_cbus_input"; data = uint32_t(input->second) << 16; return true;
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
    // ekeyb reads GPIO-group registers (e.g. keypad column inputs at the low
    // halfword of 0x0c150218) that an earlier probe latched at a narrower width.
    // Widen any already-latched GPIO-group register to the accessed width; the
    // newly-exposed bytes read zero (idle input). Opt-in with the keypad model.
    if (keypad_gpio_ && latches_.count(address) &&
        ((address >= 0x0c120c00 && address < 0x0c120c20) ||
         (address >= 0x0c14f000 && address < 0x0c14f100) ||
         (address >= 0x0c150000 && address < 0x0c150500))) {
        Latch& gpio = latches_.at(address);
        if (request.select & ~gpio.allowed) {
            gpio.allowed |= request.select;
            gpio.written |= byte_mask(request.select);  // value stays 0 = idle
        }
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
    // Exact observed write-only probe; function and side effects are unknown.
    if (sysc74_write3_ && icu46_write_ && cbus_written_.count(0x8d) &&
        address == 0x0c120074 && request.select == 15 && request.write && request.data == 3) {
        sysc74_written_ = true; device = "assumed_sysc74_write3"; return true;
    }
    // Exact observed/predicted writes only; device effects remain unknown.
    if (gpio24_28_write1_ && sysc74_written_ && request.write && request.select == 3 &&
        (address == 0x0c150024 || address == 0x0c150028) && (request.data & 0xffff) == 1) {
        device = "assumed_gpio24_28_write1"; return true;
    }
    // Exact writes observed in the synthetic post-VARIANT continuation only.
    if (sysc50_44_probe_ && sysc74_written_ && request.write && request.select == 15 &&
        ((address == 0x0c120050 && request.data == 7) || (address == 0x0c120044 && request.data == 2))) {
        device = "assumed_sysc50_44_write"; return true;
    }
    // Synthetic-only write sink; interrupt effects are not modeled.
    // Board GPIO banks configured by ekeyb (the keypad driver): the main group
    // at 0x0c150000..0x0c15001f and the keypad group at 0x0c150400..0x0c15041f.
    // Halfword/word RW latches, zero reset: config writes read back; input
    // reads are zero (idle, no keys). Addresses already modelled elsewhere
    // (the specific latches_ entries and the 0x0c150010 UIF write, both handled
    // earlier) are left to those handlers. Opt-in standard GPIO-bank model.
    // 0x0c150540..0x0c1505ff joined 2026-10-31: euart1 (NOS serial link,
    // reached once ecust+0x90=3 from boot) pin-muxes via halfword 0x0c15056a
    // (ekern VA-translation helper 0x50324608, offset literal 0x0015056a);
    // same zero-reset latch hypothesis, function unverified.
    if (keypad_gpio_ && !latches_.count(address) && !probe_regs_.count(address) &&
        ((address >= 0x0c120c00 && address < 0x0c120c20) ||
         (address >= 0x0c14f000 && address < 0x0c14f100) ||
         // 0x0c148000: NOS init writes a board-keyed halfword here (table
         // walker 0x514c1e10 -> 0x515b7e88(0x58148000,b1,b2); observed
         // halfword 0x2000 at boot-v15-auth7 730117115). Same zero-reset
         // latch hypothesis; block width unknown, 0x20 bytes allowed.
         (address >= 0x0c148000 && address < 0x0c148020) ||
         // Sibling peripheral-unit blocks the NOS init touches after
         // 0x148000 (literal sweep: 0x58142000-0c, 0x5814a000, 0x5814b000-4,
         // 0x5814c000; first write observed 0x0c142000 at 800000406).
         // Plain zero-reset latches; lock-bit semantics only added where a
         // poll is observed.
         (address >= 0x0c142000 && address < 0x0c142020) ||
         (address >= 0x0c14a000 && address < 0x0c14a020) ||
         (address >= 0x0c14b000 && address < 0x0c14b020) ||
         (address >= 0x0c14c000 && address < 0x0c14c020) ||
         // Upload RAMs: NOS init 0x514c1c30 copies halfword tables from
         // VA 0x5140a000 = PA 0xa000 (START of the scrambled window, read
         // through the descrambler) into 0x0c06ff00.. and 0x0c030100..
         // Parsed: count1=0xfe (<=0xff guard), count2=0x2000, and more
         // contiguous sections follow (ASCII version strings visible in
         // the stream) - a DSP program image. 64KB window; every written
         // byte stays in bus.tsv as evidence.
         // Plus clock reg 0x0c120034 (word 0xf written at 0x514c1d38).
         (address >= 0x0c06ff00 && address < 0x0c070000) ||
         (address >= 0x0c030000 && address < 0x0c040000) ||
         address == 0x0c120034 ||
         // 0x0c150800-0x0c1508ff: second UART-ish port block (NOS literals
         // 0x58150800..0x58150814; first write observed 817240746).
         (address >= 0x0c150800 && address < 0x0c150900) ||
         // 0x0c100000-0x0c10ffff: NOS peripheral block (scattered regs
         // 0x0/0x1f4/0x3e8-0x3f4/0x418/0x42a/0x43e/0x650/0xfe0 in the
         // literal sweep; first write 0 to 0x0c1003e8 at 817409089).
         (address >= 0x0c100000 && address < 0x0c110000) ||
         (address >= 0x0c150000 && address < 0x0c150600))) {
        if (request.select != 3 && request.select != 12 && request.select != 15 &&
            request.select != 1 && request.select != 2 && request.select != 4 && request.select != 8) {
            reason_ = "unobserved keypad GPIO access width"; return false;
        }
        const uint32_t mask = byte_mask(request.select);
        uint32_t& reg = keypad_regs_[address];
        if (request.write) reg = (reg & ~mask) | (request.data & mask);
        data = reg & mask;
        // Free-running counter at 0x0c150112 (halfword, bits 31:16 of word
        // 0x0c150110) and its window constant at 0x0c150114. OBSERVED
        // (boot-v15-poweroff instruction trace): the NOS delay calibration
        // 0x514c19fc reads [0x114] as a tick target and busy-counts
        // iterations until [0x112] advances by target/2, then divides
        // iterations*64 by elapsed ticks (thunk 0x516c7594). Zero latches
        // made that 0/0 -> euser division panic USER-EXEC 3 -> system halt
        // at 730.12M. Model: 0x112 counts one tick per 3174 CPU cycles
        // (32.768 kHz at 104 MHz, hypothesis) and 0x114 reads 0x0080 until
        // the NOS writes it (setup 0x514adce4 writes 0x9f). The computed
        // factor is a rate RATIO, so the window size choice only affects
        // boot time, not the calibration result.
        if (address == 0x0c150110 && !request.write)
            data = (data & 0xffffu) | (uint32_t((cycles_ / 3174) & 0xffff) << 16);
        if (address == 0x0c150114 && !request.write && !(reg & 0xffffu) && (mask & 0xffffu))
            data = (data & ~0xffffu) | 0x0080u;
        // 0x0c148000 clock-unit lock bit: after the NOS writes its config
        // (0x2000 then 0x2490) it polls halfword bit 0 for lock (checker
        // 0x515b7ef0: ldrh; ands #1; a zero latch spun 99.9% of the bus
        // from 760M, boot-v15-auth7). Ideal-clock hypothesis like the PLL
        // 0x0c149000 |1 model: the unit locks instantly.
        if (address == 0x0c148000 && !request.write)
            data |= 0x1u & mask;
        // euart1 TX status (PA 0x0c150514): the NOS's baseband-UART send
        // loop polls bit 2 (euart1 0x510e8a14 tst #4) for "TX idle" and a
        // zero latch spins it forever (boot-v15-stall1, 5.9e9). The modeled
        // modem UART always drains: bit 2 reads set. Hypothesis from the
        // polling disassembly; the real bit meaning is unverified.
        if (address == 0x0c150514 && !request.write) data |= 0x4u & mask;
        // FBUS UART status halfword 0x0c150504 (low half): the TX path
        // requires (value & 0x1C0) == 0x1C0 (0x515bb720; assert
        // Fbus_drv.c:502 otherwise) and the flag reader 0x515bb6bc also
        // reports bit 0x10. Modeled always drained: bits 0x1D0 set.
        if (address == 0x0c150504 && !request.write) data |= 0x1d0u & mask;
        // MBUS command strobe halfword 0x0c15021c: writers strobe bits
        // (0x8000/0x1000/0x800/0x10/0x8 at 0x515b9dxx) and the poll loop
        // 0x515ba000 waits for them to SELF-CLEAR. Reads of the low
        // halfword return 0 (strobe consumed instantly); the config
        // halfword 0x21e keeps latch semantics.
        if (address == 0x0c15021c && !request.write) data &= ~0xffffu;
        // System-type strap on GPIO halfword 0x0c150002 (word bit 22): the
        // getter 0x514c1604 maps bit 0x40 -> type 1 (GSM); with no strap it
        // falls to ROM header [0x176] bit15 (0 in this dump) and returns 0,
        // which hw_mbus_bitrate_set asserts on (Hw_mbus.c:742). Hypothesis:
        // NEM-4 straps GSM; reads see bit 0x40 set, writes still latch.
        if (address == 0x0c150000 && !request.write) data |= 0x00400000u & mask;
        // FBUS UART status halfword 0x0c15056a: the FBUS driver asserts
        // (value & 6) == 6 before TX ("/FBUS/Fbus_drv.c line 502,
        // fbus_reg_tmp & HW_FBUS_TX_BUFF_EMPTY"; checker 0x515bb5f0,
        // boot-v15-fbustest). Modeled TX always drained: bits 1+2 set.
        if (address == 0x0c150568 && !request.write) data |= 0x60000u & mask;
        // (A 2026-10-31 experiment mirrored the host handshake bit on the
        // 0x0c150208 sense half; screen timelines proved it changed NOTHING
        // (boot-v15-cts2 == baseline cycle for cycle), so it was removed:
        // the poll is not the TX gate.)
        device = "assumed_keypad_gpio"; return true;
    }
    // REAL NOS/GSM module payload (THC live-device dump, docs/references.md),
    // read-only for code fetches and data reads at PA 0x9d280+. Writes stop
    // the run (flash is not writable through this window). That the board's
    // raw CS0 window presents these bytes is an assumption (descrambler path
    // unverified); the bytes themselves are authentic phone content.
    // Gated on the kernel periodic tick being armed: the boot-time MD5 digest
    // sweeps PA 0x9d280+ as DATA reads at ~139M cycles and must see the RAW
    // flash bytes or validation halts at 0x50003290 (observed twice,
    // 2026-10-29); nosstarter EXECUTES the entry (code fetches) at ~729M,
    // after the kernel tick arming at ~452M. Descrambler-enable timing is a
    // hypothesis, not verified hardware.
    // Synthesized NOS IAT words: the NOS module's import slots live in
    // scrambled flash (PA 0x6e030-0x725c0; plaintext exists in no available
    // file), so each entry is ONE slot resolved by reverse-engineering its
    // call site against the same-build kernel/euser exports (resolutions
    // documented in docs/status.md). Kernel-tick gated like the image window
    // (the boot digest must hash the raw scrambled bytes).
    if (!nos_iat_.empty() && periodic_period_ && !request.write) {
        auto iat = nos_iat_.find(address & ~3u);
        if (iat != nos_iat_.end()) {
            data = iat->second & byte_mask(request.select);
            device = "synthesized_nos_iat"; return true;
        }
    }
    // AUTHENTIC NOS import region [0x6e030,0x725c0): plaintext recovered from
    // the user's Nokia NEM-4 4.03 data package (firmware/MCU nem440.3c1,
    // de-framed to nos-iat-region-0x6e030.bin; anchor slot 0x71c38 matches
    // the independently reverse-engineered 0x503a2f64). Serves ROM-build-
    // resolved import tables the THC dump holds only scrambled. Same kernel-
    // tick gating as the image window (the boot digest hashes raw flash).
    // Explicit nos-iat= words above take precedence for A/B comparisons.
    if (!nos_iat_region_.empty() && periodic_period_ && !request.write &&
        address >= 0x0006e030 && uint64_t(address) + 4 <= 0x0006e030 + nos_iat_region_.size()) {
        const size_t off = address - 0x0006e030;
        data = (uint32_t(nos_iat_region_[off]) | uint32_t(nos_iat_region_[off+1]) << 8 |
                uint32_t(nos_iat_region_[off+2]) << 16 | uint32_t(nos_iat_region_[off+3]) << 24) &
               byte_mask(request.select);
        device = "authentic_nos_iat_region"; return true;
    }
    // With the synthetic stub also enabled, the stub keeps its proven blob
    // window [0x9d000,0x9d288) (incl. the nosstarter entry B at 0x9d284) and
    // the image serves only the module body past it; without the stub the
    // image serves from its true base 0x9d280.
    if (!nos_image_.empty() && periodic_period_ &&
        address >= (nos_entry_stub_ ? 0x0009d288u : 0x0009d280u) &&
        address + 4 <= 0x0009d280 + nos_image_.size() &&
        !(nos_entry_stub_ && address + 4 > kNosPowerBase &&
          address < kNosPowerBase + sizeof(power_model_))) {
        if (request.write) { reason_ = "write into the NOS image window"; return false; }
        const uint32_t off = address - 0x0009d280;
        data = uint32_t(nos_image_[off]) | uint32_t(nos_image_[off+1]) << 8 |
               uint32_t(nos_image_[off+2]) << 16 | uint32_t(nos_image_[off+3]) << 24;
        data &= byte_mask(request.select);
        ++nos_image_reads_;
        device = "nos_image_thc"; return true;
    }
    // SYNTHETIC NOS variant-interface provider (nos_stub_blob.h). Served
    // read-only for both code fetches and data reads over the blob's window:
    // the nosstarter entry at 0x0009d284 trampolines into a routine that
    // registers interface #3/#6 with the kernel Variant singleton and sets the
    // readiness bits, so product_info and the kernel interface waiter see a
    // non-NULL, non-faulting object. Not authentic baseband code.
    // Gated on the kernel tick like the nos-image window: SYM.ROM embeds the
    // blob and power-model words, and the boot-time MD5 digest must hash those
    // ROM bytes (editing the blob without the gate failed validation at
    // 0x50003290, observed 2026-10-29). nosstarter executes the stub at ~729M,
    // after the tick arms at ~452M.
    if (nos_entry_stub_ && periodic_period_ && !request.write &&
        address >= kNosStubBase && address + 4 <= kNosStubBase + kNosStubSize) {
        const uint32_t off = address - kNosStubBase;
        data = uint32_t(kNosStubBlob[off]) | uint32_t(kNosStubBlob[off+1]) << 8 |
               uint32_t(kNosStubBlob[off+2]) << 16 | uint32_t(kNosStubBlob[off+3]) << 24;
        data &= byte_mask(request.select);
        ++nos_stub_fetches_;
        device = "synthetic_nos_entry_stub"; return true;
    }
    // Power-model object: board RW RAM at PA 0x9e000 (VA 0x5149e000). The kernel
    // reads the vptr/queue and writes +4/+8/+0xc/queue links during boot.
    if (nos_entry_stub_ && periodic_period_ && address >= kNosPowerBase && address + 4 <= kNosPowerBase + sizeof(power_model_)) {
        const uint32_t idx = (address - kNosPowerBase) / 4;
        const uint32_t mask = byte_mask(request.select);
        if (request.write) power_model_[idx] = (power_model_[idx] & ~mask) | (request.data & mask);
        data = power_model_[idx] & mask;
        device = "synthetic_nos_power_model"; return true;
    }
    // Kernel character-output device (VA 0x59000000, routine 0x503243a8).
    // Write-only: bytes are retained as evidence, nothing is invented for
    // reads, and no side effects are modeled. Device identity unverified.
    // 0x0d space: NOS peripheral windows at scattered 0x0dXX0000 bases
    // (observed 0x0d010000, 0x0d000000, 0x0d6d0000 at 801.8-816.6M).
    // Zero-reset RW latches in the serialized block14d_ map for the whole
    // space EXCEPT the established debug/trace sinks, which keep their
    // text-capture handlers below.
    if (debug59_sink_ && address >= 0x0d000000 && address < 0x0e000000 &&
        !(address >= 0x0de00000 && address < 0x0de01000) &&
        !(address >= 0x0def0000 && address < 0x0def1000) &&
        !(address >= 0x0dfd0000 && address < 0x0dfd0010)) {
        device = "assumed_nos_periph4000";
        uint32_t& reg0d = block14d_[address & ~3u];
        const uint32_t mask0d = byte_mask(request.select);
        if (request.write) reg0d = (reg0d & ~mask0d) | (request.data & mask0d);
        data = reg0d & mask0d;
        return true;
    }
    // 0x0def0000: NOS-side trace window in the debug space. Writes carry
    // ASCII text at any width (observed: byte 0xc3 framing, then word
    // "MTC:" at boot-v15-auth7 800742521). Write-only sink; all enabled
    // bytes are captured in bus order.
    if (debug59_sink_ && request.write && address >= 0x0def0000 && address < 0x0def1000) {
        ++debug59_writes_;
        for (unsigned i = 0; i < 4; ++i)
            if ((request.select & (1u << i)) && debug59_bytes_.size() < 65536)
                debug59_bytes_.push_back(char((request.data >> (8 * i)) & 0xff));
        device = "assumed_debug59_write"; return true;
    }
    if (debug59_sink_ && request.write && ((address >= 0x0de00000 && address < 0x0de01000) ||
        (address >= 0x0dfd0000 && address < 0x0dfd0010))) {
        const uint8_t select = request.select;
        if (select != 1 && select != 2 && select != 4 && select != 8) {
            reason_ = "unobserved debug-output access width"; return false;
        }
        unsigned byte = select == 1 ? 0 : select == 2 ? 1 : select == 4 ? 2 : 3;
        const bool control = address >= 0x0dfd0000;
        ++debug59_writes_;
        // Control-window writes (VA 0x591d0000, 0xe0 on newline) are kept as
        // line breaks in the captured text; the raw value stays in bus.tsv.
        if (debug59_bytes_.size() < 65536)
            debug59_bytes_.push_back(control ? '\n' : char((request.data >> (8 * byte)) & 0xff));
        device = control ? "assumed_debug59_control" : "assumed_debug59_write"; return true;
    }
    // ASIC-resident ROM services at PA 0x0c000000 (no dump available): the
    // NOS calls entry points 0x58000001+offset (halfword offset table
    // 0x516cd980+0xc: 0x3de/0xcf4/0xf28/0x260/...; call site 0x514befd2,
    // dispatcher 0x515305b8 BX R12) passing comm-RAM buffers. Observed
    // call (boot-v15-jumptrace 800760646): in = 0x0c004400 len 0x28 all
    // 0xFF (blank personalization), out = 0x0c004428 len 0x20; the return
    // value is discarded by the wrapper (0x514befe8 overwrites r0).
    // EXPLICIT STUB HYPOTHESIS: every halfword in the page reads 0x4770
    // (Thumb BX LR) - any entry returns immediately, outputs stay zero.
    if (nos_periph4000_ && address >= 0x0c000000 && address < 0x0c001000) {
        if (request.write) { reason_ = "write into ASIC-ROM stub page"; return false; }
        device = "assumed_asic_rom_stub";
        data = 0x47704770u;
        return true;
    }
    // NOS-side peripheral block 0x0c004000-0x0c004fff (observed first touch
    // boot-v15-auth7 cycle 730120842: halfword 0x001a to 0x0c00428c during
    // the NOS hardware-init burst). The NOS references dozens of registers
    // here (0x4000-0x4060, 0x4080, 0x40c0, 0x4180, 0x4200-0x4298: literal
    // sweep of nos-image.bin; users include the UEM/energy code 0x515c1xxx
    // and the startup manager 0x51506xxx). Explicit zero-reset RW-latch
    // hypothesis like block14d; every access still lands in bus.tsv as
    // evidence. Registers share block14d_ storage (address-keyed) so the
    // savestate layout is unchanged.
    if (nos_periph4000_ && address >= 0x0c004000 && address < 0x0c005000) {
        device = "assumed_nos_periph4000";
        uint32_t& reg = block14d_[address & ~3u];
        const uint32_t mask = byte_mask(request.select);
        if (request.write) reg = (reg & ~mask) | (request.data & mask);
        data = reg & mask;
        return true;
    }
    // Unidentified UPP block initialized by kernel routine 0x5032430c after
    // the first tick. Explicit zero-reset read/write probe; no side effects
    // are modeled and the device function remains unverified.
    if (block14d_probe_ && sysc74_written_ && (address == 0x0c150538 || address == 0x0c15053c ||
        (address >= 0x0c14d000 && address <= 0x0c14d010 && !(address & 3)))) {
        device = "assumed_block14d_probe";
        uint32_t& reg = block14d_[address];
        const uint32_t mask = byte_mask(request.select);
        if (request.write) reg = (reg & ~mask) | (request.data & mask);
        data = reg & mask;
        return true;
    }
    // Disassembly: 0x0c1201c8 is the FIQ-ICU enable-set (FiqAPIIOAbort, bit 27),
    // unrelated to the timer tick. No FIQ source is modeled; exact write sink.
    if (icu1c8_probe_ && sysc74_written_ && request.write && request.select == 15 &&
        address == 0x0c1201c8 && request.data == 0x08000000) {
        device = "assumed_icu1c8_write"; return true;
    }
    auto probe = probe_regs_.find(address);
    if (probe != probe_regs_.end() && address == 0x0c150204 && probe->second.select == 12 && request.select == 12) {
        // gpio206-extra-write values: ekeyb 0x0006 and epbus 0x0001 (routine
        // 0x503f5bbc writes halfword 1 to byte 0x0c150206 during init);
        // 0x0200 observed from the NOS hardware-init burst right after its
        // clock bring-up (boot-v15-auth7 cycle 729428678, 2026-10-31).
        // 2026-10-31 night: the NOS keeps writing new values here (0x0200
        // at 729.4M, 0x0004 at 816.98M, ...) - this is a general pin-config
        // halfword, not a fixed-value latch. Accept any value once the
        // boot-phase gates passed; every write stays in bus.tsv.
        if (!icu46_write_ || !cbus_written_.count(0x8d) || !request.write) {
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
        // System-type strap (see keypad-section comment): GPIO 0x0c150002
        // bit 0x40 reads set - this word lives in latches_, so the OR-in
        // happens here on the latch read path.
        if (keypad_gpio_ && address == 0x0c150000 && !request.write)
            data |= 0x00400000u;
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
        // Diagnostic word watch (watch-word= option): a full-word RAM write
        // of the watched value is tagged so it appears in compact bus logs.
        // Used to catch the kernel copying a panic category ("KERN-EXEC"
        // first word 0x0045004b) into a fresh heap record, which no PC- or
        // vector-level instrument sees (2026-10-31 EtelServer hunt).
        if (watch_word_set_ && request.write && request.select == 15 && request.data == watch_word_)
            device = "watched_word_write";
        const size_t offset = address - ram_base_;
        for (unsigned i = 0; i < 4; ++i) {
            if (request.write && (request.select & (1u << i)))
                ram_[offset+i] = (request.data >> (8*i)) & 255;
            data |= uint32_t(ram_[offset+i]) << (8*i);
        }
        return true;
    }
    // Internal user flash (C: drive, LFFS) at PA 0x02400000..0x027fffff. Handled
    // before the code-flash chips because flash_[1]'s 16 MiB window overlaps it.
    if (cdrive_flash_ && address >= 0x02400000 && address < 0x02800000)
        return cdrive_access(request, data, device);
    for (Flash& flash : flash_) {
        if (address < flash.base || address - flash.base >= 0x01000000) continue;
        if (request.write) {
            device = "flash_command";
            return flash_command(flash, request);
        }
        // PMM program status: after a program data cycle reads return the
        // Intel status register (ready, no errors) until 0xFF/0xF0/0x50.
        if (auto st = block14d_.find(0xff000000u | flash.base);
            st != block14d_.end() && (st->second & 1u)) {
            device = "flash_pmm_status";
            data = 0x00800080u & byte_mask(request.select);
            return true;
        }
        // After a 0x60 lock-op setup the PMM driver READS the sector lock
        // status (observed 0x60 -> read,read -> 0xF0 at 818481834; erased
        // 0xFFFF made it print "PMM Write failed" + hw_reset_generate).
        // Hypothesis: reads in lock-op mode return 0x0001 = protected.
        if (auto st = block14d_.find(0xff000000u | flash.base);
            st != block14d_.end() && (st->second & 4u)) {
            device = "flash_pmm_status";
            data = 0x00010001u & byte_mask(request.select);
            return true;
        }
        if (flash.identify) {
            device = "flash_identify";
            return flash_identify(flash, request, data);
        }
        // Programmed-overlay readback (PMM verify does ldrh of what it
        // wrote). Serve only if every requested halfword is in the
        // overlay; untouched flash falls through to the dump banks.
        {
            const uint32_t w = address & ~3u;
            auto lo = block14d_.find(0x80000000u | w);
            auto hi = block14d_.find(0x80000000u | (w + 2));
            const bool need_lo = request.select & 0x3, need_hi = request.select & 0xc;
            const bool have_lo = lo != block14d_.end() && (lo->second >> 16) == 1;
            const bool have_hi = hi != block14d_.end() && (hi->second >> 16) == 1;
            if ((need_lo && have_lo && (!need_hi || have_hi)) ||
                (need_hi && have_hi && (!need_lo || have_lo))) {
                device = "flash_pmm_overlay";
                data = (have_lo ? (lo->second & 0xffffu) : 0u) |
                       (have_hi ? (hi->second & 0xffffu) << 16 : 0u);
                return true;
            }
            if ((need_lo && have_lo) != (need_hi && have_hi) && need_lo && need_hi) {
                reason_ = "flash read mixes programmed overlay and array halfwords";
                return false;
            }
        }
        break;
    }
    // THC-dump mode: rom_ is the real phone's VA-0x50000000 snapshot, not a
    // physical-flash image. Serve physical flash-bank reads by translating the
    // physical address to the dump's VA offset via the verified bank map
    // (scratch/nem440-flash-extract/verify.py): CS0 identity, CS1 at +0x700000,
    // CS2 at +0xb00000, CS0-PPM bank at +0x1300000. The scrambled window's
    // physical reads land on the dump's post-remap content (the descrambled
    // twin) - acceptable, and the point of using the real dump.
    if (rom_va_dump_) {
        for (const Bank& bank : banks_) {
            if (address < bank.address || uint64_t(address - bank.address) + 4 > bank.size) continue;
            if (request.write) { reason_ = "unmodeled write to a ROM bank"; return false; }
            // Physical-CHIP -> dump-content map (scratch/nem440-flash-extract/
            // verify.py): CS0 identity, CS1 at +0x700000, CS2 at +0xb00000, CS0
            // PPM bank at +0x1300000. NOTE: this is the physical chip->dump
            // relationship, NOT the captured MMU VA->phys map (ngage-virt-phys-
            // map.txt) - that one is the steady-state MMU view and gives 0xFF
            // for raw physical pages, which breaks reset-time physical reads
            // (boot-v15-thcv5 died at cycle 2166). Physical reads hit the chips
            // directly, so the chip layout is the correct source.
            const uint32_t pa = address;
            uint64_t off;
            if (pa < 0x00700000u)                           off = pa;                                  // CS0
            else if (pa >= 0x00700000u && pa < 0x007f0000u) off = uint64_t(pa) - 0x00700000u + 0x01300000u; // CS0 PPM bank
            else if (pa >= 0x007f0000u && pa < 0x00800000u) {
                // Top 64KB of CS0 = the NOS PMM/security sector, not part of
                // the 20.3MB dump. Factory-fresh hypothesis: erased flash;
                // halfwords the NOS programs are served by the overlay above.
                device = "pmm_sector_erased"; data = 0xffffffffu; return true;
            }
            else if (pa >= 0x02000000u && pa < 0x02400000u) off = uint64_t(pa) - 0x02000000u + 0x00700000u; // CS1
            else if (pa >= 0x04000000u && pa < 0x04800000u) off = uint64_t(pa) - 0x04000000u + 0x00b00000u; // CS2
            else { reason_ = "physical address not in the THC-dump bank map"; return false; }
            if (off + 4 > rom_bytes_) {
                // PPM-bank tail (physical ~0x76c000..0x7f0000) is erased/pristine
                // flash beyond the 20.3MB dump; the factory path served 0xFF too.
                if (pa >= 0x0076c000u && pa < 0x007f0000u) {
                    device = "thc_dump_ppm_tail_erased"; data = 0xffffffffu; return true;
                }
                reason_ = "THC-dump has no bytes for this physical bank"; return false;
            }
            device = "thc_dump_flash_array";
            for (unsigned i = 0; i < 4; ++i) data |= uint32_t(rom_[off+i]) << (8*i);
            return true;
        }
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
    // Top 64KB of CS0 (0x7f0000..0x7fffff) = the NOS PMM/security sector,
    // outside the firmware bank table and the dump. Factory-fresh
    // hypothesis: erased flash; programmed halfwords are served by the
    // overlay in the flash dispatch above.
    if (!request.write && address >= 0x007f0000u && address < 0x00800000u) {
        device = "pmm_sector_erased"; data = 0xffffffffu; return true;
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
           << ",\"timer_periodic_assumed\":" << (timer_periodic_ ? "true" : "false")
           << ",\"timer_periodic_period\":" << periodic_period_
           << ",\"timer_periodic_remaining\":" << periodic_remaining_
           << ",\"timer_periodic_irqs\":" << periodic_irqs_
           << ",\"block14d_probe_assumed\":" << (block14d_probe_ ? "true" : "false")
           << ",\"block14d_registers\":" << block14d_.size()
           << ",\"cbus_inputs_assumed\":[" << [this]{ std::string out; for (const auto& item : cbus_inputs_) { if (!out.empty()) out += ","; out += "[" + std::to_string(item.first) + "," + std::to_string(item.second) + "]"; } return out; }() << "]"
           << ",\"keypad_gpio_assumed\":" << (keypad_gpio_ ? "true" : "false")
           << ",\"keypad_registers\":" << keypad_regs_.size()
           << ",\"icu_banks_assumed\":" << (icu_banks_ ? "true" : "false")
           << ",\"icu_bank_accesses\":" << icu_bank_accesses_
           << ",\"timer_units_assumed\":" << (timer_units_ ? "true" : "false")
           << ",\"timer_unit_registers\":" << timer_unit_regs_.size()
           << ",\"uem_irq_source1_assumed\":" << (uem_irq_source1_ ? "true" : "false")
           << ",\"uem_irqs\":" << uem_irqs_
           << ",\"unit1_irqs\":" << unit1_irqs_
           << ",\"epbus_clk_regs\":" << epbus_clk_regs_.size()
           << ",\"uem_irq_pending\":" << (uem_irq_pending_ ? "true" : "false")
           << ",\"unit60_irq3_assumed\":" << (unit60_irq3_ ? "true" : "false")
           << ",\"unit60_irqs\":" << unit60_irqs_
           << ",\"unit60_pending\":" << (unit60_pending_ ? "true" : "false")
           << ",\"icu_mask_banks\":[" << icu_mask2_[0] << "," << icu_mask2_[1] << "," << icu_mask2_[2] << "]"
           << ",\"cdrive_flash_assumed\":" << (cdrive_flash_ ? "true" : "false")
           << ",\"cdrive_writes\":" << cdrive_writes_
           << ",\"cdrive_erases\":" << cdrive_erases_
           << ",\"nos_image_bytes\":" << nos_image_.size()
           << ",\"nos_image_reads\":" << nos_image_reads_
           << ",\"nos_entry_stub_synthetic\":" << (nos_entry_stub_ ? "true" : "false")
           << ",\"nos_power_model_installed\":" << (power_model_init_ ? "true" : "false")
           << ",\"nos_stub_fetches\":" << nos_stub_fetches_
           << ",\"debug59_sink_assumed\":" << (debug59_sink_ ? "true" : "false")
           << ",\"debug59_writes\":" << debug59_writes_
           << ",\"debug59_text\":\"" << [this]{ std::string out; for (char c : debug59_bytes_) { if (c=='"'||c=='\\') { out+='\\'; out+=c; } else if (c=='\n') out+="\\n"; else if (c=='\r') out+="\\r"; else if (c=='\t') out+="\\t"; else if (c>=0x20 && c<0x7f) out+=c; else { char hex[8]; snprintf(hex,sizeof hex,"\\u%04x",(unsigned char)c); out+=hex; } } return out; }() << "\""
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
void BootProfile::run_lcd_dma() {
    // Perform the armed transfer: 0x354 source PA, 0x360 destination,
    // 0x36c = words-1. Only the observed shape (SDRAM -> LCD data port) is
    // modeled; anything else stops the run so the new use is seen, not
    // silently mis-served.
    const uint32_t src = keypad_regs_[0x0c120354];
    const uint32_t dst = keypad_regs_[0x0c120360];
    const uint32_t count = keypad_regs_[0x0c12036c] + 1;
    // The destination is the LCD data port through the DMA bus window:
    // 0x10000000 + (PA - 0x0c000000) (observed 0x10121208); a plain PA is
    // accepted too.
    if (!(dst == 0x10121208 || dst == 0x0c121208) || count > 0x40000 ||
        src < 0x0a000000 || uint64_t(src - 0x0a000000) + 4ull*count > ram_.size()) {
        reason_ = "unmodeled DMA channel programming"; return;
    }
    std::vector<uint32_t> words(count);
    for (uint32_t i = 0; i < count; ++i) {
        const size_t off = (src - 0x0a000000) + 4ull*i;
        words[i] = uint32_t(ram_[off]) | uint32_t(ram_[off+1])<<8 |
                   uint32_t(ram_[off+2])<<16 | uint32_t(ram_[off+3])<<24;
    }
    lcd_data_words_ += count;
    if (lcd_dma_frames_.size() < 64)
        lcd_dma_frames_.emplace_back(lcd_header_, std::move(words));
    ++lcd_dma_transfers_;
    dma_done_pending_ = true;
}

void BootProfile::dump_lcd_dma(std::ostream& out) const {
    // bus.tsv-compatible rows (header write then data words per transfer),
    // so render_lcd_frame.py reads this file unchanged. Cycle is a synthetic
    // sequence number; the real arm cycles are in bus.tsv's 0x348 writes.
    out << "cycle\toperation\taddress\tbyte_enable\tdata\tchannel\tdevice\n";
    uint64_t seq = 1;
    for (const auto& frame : lcd_dma_frames_) {
        out << std::dec << seq++ << "\tWRITE\t0x0c121200\t0xf\t0x"
            << std::hex << std::setw(8) << std::setfill('0') << frame.first
            << "\tdata\tlcd_probe_transport\n";
        for (uint32_t w : frame.second)
            out << std::dec << seq++ << "\tWRITE\t0x0c121208\t0xf\t0x"
                << std::hex << std::setw(8) << std::setfill('0') << w
                << "\tdata\tlcd_probe_transport\n";
    }
}

void BootProfile::save_state(std::ostream& out) const {
    // v2: full device-model state. Maps are written as count + (key,value).
    const uint32_t version = 0x4e470006; state_write(out, version);
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
    // v2 additions
    state_write(out, uif_written_); state_write(out, icu25_written_); state_write(out, sysc74_written_);
    state_write(out, pupf004_low_value_);
    state_write(out, periodic_period_); state_write(out, periodic_remaining_); state_write(out, periodic_irqs_);
    n=probe_regs_.size(); state_write(out,n); for (const auto& item:probe_regs_) {state_write(out,item.first);state_write(out,item.second);}
    n=block14d_.size(); state_write(out,n); for (const auto& item:block14d_) {state_write(out,item.first);state_write(out,item.second);}
    n=keypad_regs_.size(); state_write(out,n); for (const auto& item:keypad_regs_) {state_write(out,item.first);state_write(out,item.second);}
    n=timer_unit_regs_.size(); state_write(out,n); for (const auto& item:timer_unit_regs_) {state_write(out,item.first);state_write(out,item.second);}
    state_write(out, icu_enable_); state_write(out, icu_bank_accesses_);
    state_write(out, icu_mask2_);
    state_write(out, unit60_remaining_); state_write(out, unit60_irqs_); state_write(out, unit60_pending_);
    n=cdrive_.size(); state_write(out,n); out.write(reinterpret_cast<const char*>(cdrive_.data()),n);
    state_write(out, cdrive_unlock_); state_write(out, cdrive_autoselect_); state_write(out, cdrive_program_);
    state_write(out, cdrive_erase_armed_); state_write(out, cdrive_erase_base_); state_write(out, cdrive_erase_end_);
    state_write(out, cdrive_erase_reads_); state_write(out, cdrive_writes_); state_write(out, cdrive_erases_);
    state_write(out, power_model_); state_write(out, power_model_init_);
    state_write(out, nos_stub_fetches_); state_write(out, nos_image_reads_);
    state_write(out, debug59_writes_);
    n=debug59_bytes_.size(); state_write(out,n); out.write(debug59_bytes_.data(),n);
    // v3: ICU source-1 / settle-timer state
    state_write(out, uem_irq_pending_); state_write(out, uem_irqs_);
    state_write(out, unit1_running_); state_write(out, unit1_elapsed_); state_write(out, unit1_compare_); state_write(out, unit1_irqs_);
    n=epbus_clk_regs_.size(); state_write(out,n); for (const auto& item:epbus_clk_regs_) {state_write(out,item.first);state_write(out,item.second);}
    // v6: LCD DMA engine state (captured frames are evidence, not firmware-
    // visible state, and are NOT checkpointed; a resume re-captures).
    state_write(out, dma_done_pending_); state_write(out, lcd_dma_transfers_);
    if (!out) throw std::runtime_error("failed to save board checkpoint");
}
void BootProfile::load_state(std::istream& in) {
    uint32_t version=0; state_read(in,version); if (version < 0x4e470002 || version > 0x4e470006) throw std::runtime_error("board checkpoint version mismatch");
    state_read(in,rom_tail_reads_); state_read(in,cbus_stage_); state_read(in,cbus_transactions_);
    state_read(in,cbus_config_); state_read(in,cbus_command_); state_read(in,uem_adc_channel_);
    state_read(in,adc_result_reads_); state_read(in,timer_remaining_); state_read(in,timer_elapsed_);
    state_read(in,timer_irq_cycle_); state_read(in,timer_started_); state_read(in,timer_irq_enabled_); state_read(in,timer_irq_pending_);
    state_read(in,lcd_header_); state_read(in,lcd_control_); state_read(in,lcd_header_written_); state_read(in,lcd_control_written_);
    state_read(in,lcd_headers_); state_read(in,lcd_data_words_); state_read(in,lcd_status_reads_);
    state_read(in,flash_);
    // v4 and earlier saved 0xac-byte scratch arrays (window ended at 0x47f4,
    // which truncated kernel fault dumps); v5 saves the grown 0xb8 arrays.
    if (version >= 0x4e470005) { state_read(in,code_scratch_); state_read(in,code_scratch_written_); }
    else {
        code_scratch_.fill(0); code_scratch_written_.fill(0);
        in.read(reinterpret_cast<char*>(code_scratch_.data()),0xac);
        in.read(reinterpret_cast<char*>(code_scratch_written_.data()),0xac);
    }
    uint64_t n=0; state_read(in,n); if (n!=ram_.size()) throw std::runtime_error("checkpoint RAM size mismatch"); in.read(reinterpret_cast<char*>(ram_.data()),n);
    state_read(in,n); if(n>1024) throw std::runtime_error("invalid checkpoint CBUS entries"); cbus_written_.clear();
    for(uint64_t i=0;i<n;++i){uint16_t k,v;state_read(in,k);state_read(in,v);cbus_written_[k]=v;}
    // Like the probe merge below: latches the CONSTRUCTOR seeds that are
    // missing from the snapshot keep their fresh defaults, so a resume can
    // carry a newly modeled latch register (e.g. boot-latch 0x40).
    const auto seeded_latches = latches_;
    state_read(in,n); if(n>8192) throw std::runtime_error("invalid checkpoint latch entries"); latches_.clear();
    for(uint64_t i=0;i<n;++i){uint32_t k;Latch v;state_read(in,k);state_read(in,v);latches_[k]=v;}
    for (const auto& kv : seeded_latches) latches_.emplace(kv.first, kv.second);
    state_read(in,uif_written_); state_read(in,icu25_written_); state_read(in,sysc74_written_);
    state_read(in,pupf004_low_value_);
    state_read(in,periodic_period_); state_read(in,periodic_remaining_); state_read(in,periodic_irqs_);
    // Merge probe values into the CONFIGURED probe set: registers added to the
    // configuration after the checkpoint keep their initial values, so a
    // resume can carry a newly probed register (the usual iteration step).
    state_read(in,n); if(n>4096) throw std::runtime_error("invalid checkpoint probe entries");
    for(uint64_t i=0;i<n;++i){uint32_t k;ProbeReg v;state_read(in,k);state_read(in,v);auto it=probe_regs_.find(k);if(it!=probe_regs_.end())it->second=v;}
    state_read(in,n); if(n>262144) throw std::runtime_error("invalid checkpoint block14d entries"); block14d_.clear();
    for(uint64_t i=0;i<n;++i){uint32_t k,v;state_read(in,k);state_read(in,v);block14d_[k]=v;}
    state_read(in,n); if(n>262144) throw std::runtime_error("invalid checkpoint keypad entries"); keypad_regs_.clear();
    for(uint64_t i=0;i<n;++i){uint32_t k,v;state_read(in,k);state_read(in,v);keypad_regs_[k]=v;}
    state_read(in,n); if(n>4096) throw std::runtime_error("invalid checkpoint timer-unit entries"); timer_unit_regs_.clear();
    for(uint64_t i=0;i<n;++i){uint32_t k,v;state_read(in,k);state_read(in,v);timer_unit_regs_[k]=v;}
    state_read(in,icu_enable_); state_read(in,icu_bank_accesses_);
    state_read(in,icu_mask2_);
    state_read(in,unit60_remaining_); state_read(in,unit60_irqs_); state_read(in,unit60_pending_);
    state_read(in,n); if(n && n!=4u<<20) throw std::runtime_error("invalid checkpoint C: overlay size");
    // The saved overlay IS the flash content (LFFS stamps blocks in place);
    // the cdrive image seeds the array at construction only. Re-applying it
    // here wiped restored stamps and diverged flash from LFFS's RAM state
    // (bug found 2026-10-30 resuming mid-storm from idle-c2600). Current
    // checkpoints already embed the image in their saved overlay.
    cdrive_.resize(n); if(n) in.read(reinterpret_cast<char*>(cdrive_.data()),n);
    state_read(in,cdrive_unlock_); state_read(in,cdrive_autoselect_); state_read(in,cdrive_program_);
    state_read(in,cdrive_erase_armed_); state_read(in,cdrive_erase_base_); state_read(in,cdrive_erase_end_);
    state_read(in,cdrive_erase_reads_); state_read(in,cdrive_writes_); state_read(in,cdrive_erases_);
    state_read(in,power_model_); state_read(in,power_model_init_);
    state_read(in,nos_stub_fetches_); state_read(in,nos_image_reads_);
    state_read(in,debug59_writes_);
    state_read(in,n); if(n>1u<<20) throw std::runtime_error("invalid checkpoint debug59 length");
    debug59_bytes_.resize(n); if(n) in.read(&debug59_bytes_[0],n);
    if (version >= 0x4e470003) {
        state_read(in,uem_irq_pending_); state_read(in,uem_irqs_);
        state_read(in,unit1_running_); state_read(in,unit1_elapsed_); state_read(in,unit1_compare_); state_read(in,unit1_irqs_);
    }
    if (version >= 0x4e470004) {
        state_read(in,n); if(n>4096) throw std::runtime_error("invalid checkpoint epbus-clk entries"); epbus_clk_regs_.clear();
        for(uint64_t i=0;i<n;++i){uint32_t k,v;state_read(in,k);state_read(in,v);epbus_clk_regs_[k]=v;}
    }
    if (version >= 0x4e470006) { state_read(in,dma_done_pending_); state_read(in,lcd_dma_transfers_); }
    else { dma_done_pending_ = false; lcd_dma_transfers_ = 0; }
    // Pre-v6 checkpoints predate the DMA engine: a transfer armed before the
    // save (0x348 latched 2) was never served, and the driver is still
    // blocked on it. Serve it now so the resume delivers the done IRQ.
    if (version < 0x4e470006 && !lcd_dma_transfers_ && !dma_done_pending_) {
        auto it = keypad_regs_.find(0x0c120348);
        if (it != keypad_regs_.end() && it->second == 2) run_lcd_dma();
    }
    if (!in) throw std::runtime_error("truncated board checkpoint");
}
