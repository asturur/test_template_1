#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <map>
#include <ostream>
#include <istream>
#include <string>
#include <vector>

struct BootBusRequest {
    uint32_t address, data;
    uint8_t select;
    bool write;
};

// An explicit experiment driven by the 4.03 startup tables. This is not
// a verified UPP_WD2 model. Unknown addresses and unwritten latch bits stop.
class BootProfile {
public:
    BootProfile(const std::vector<uint8_t>& rom, size_t rom_bytes, const std::string& kind, bool ideal_clocks = false, bool lcd_probe = false, const std::vector<uint8_t>& rom_tail = {}, bool boot_io_probe = false, const std::map<unsigned, unsigned>& adc_inputs = {}, uint64_t timer_irq_delay = 0, int uem_power_status = -1, int uem_status36 = -1, int uem_status35 = -1, int extra_cbus_write = -1, int extra_cbus_write2 = -1, bool allow_uif_8000 = false, bool allow_icu25 = false, bool gpio210_low_zero = false, bool gpio21a_zero = false, bool gpio216_zero = false, bool uif102_write = false, bool cbus82_readback = false, int cbus80_input = -1, bool cbus8d_zero = false, bool icu46_write = false, bool pupf00a_zero = false, bool sysc0c14_zero = false, const std::map<uint32_t,std::pair<uint32_t,uint8_t>>& probe_regs = {}, bool gpio214_low_zero = false, bool pupf004_low_zero = false, bool gpio206_extra_write = false, bool sysc74_write3 = false);
    static std::map<unsigned, unsigned> parse_adc_inputs(const std::string& options);
    bool access(const BootBusRequest& request, uint32_t& data, std::string& device);
    void tick();
    bool timer_irq() const { return timer_irq_pending_ && timer_irq_enabled_; }
    bool has_scheduled_interrupt() const { return timer_irq_delay_ && (timer_remaining_ || timer_irq_pending_); }
    void report(std::ostream& output) const;
    void save_state(std::ostream& out) const;
    void load_state(std::istream& in);
    const std::string& reason() const { return reason_; }
private:
    struct Bank { uint32_t address, size; size_t offset; };
    struct Latch { uint32_t value = 0, written = 0; uint8_t allowed = 15; };
    const std::vector<uint8_t>& rom_;
    size_t rom_bytes_;
    std::vector<uint8_t> rom_tail_;
    uint64_t rom_tail_reads_ = 0;
    std::string kind_, reason_;
    bool ideal_clocks_, lcd_probe_, boot_io_probe_, allow_uif_8000_, allow_icu25_, gpio210_low_zero_, gpio21a_zero_, gpio216_zero_, gpio214_low_zero_, pupf004_low_zero_, gpio206_extra_write_, sysc74_write3_, uif102_write_, cbus82_readback_, cbus8d_zero_, icu46_write_, pupf00a_zero_, sysc0c14_zero_, uif_written_ = false, icu25_written_ = false;
    uint16_t pupf004_low_value_ = 0;
    unsigned cbus_stage_ = 0, cbus_transactions_ = 0;
    uint16_t cbus_config_ = 0, cbus_command_ = 0;
    int uem_adc_channel_ = -1, uem_power_status_ = -1, uem_status36_ = -1, uem_status35_ = -1, cbus80_input_ = -1, extra_cbus_write_ = -1, extra_cbus_write2_ = -1;
    std::map<unsigned, unsigned> adc_inputs_;
    uint64_t adc_result_reads_ = 0;
    uint64_t timer_irq_delay_ = 0, timer_remaining_ = 0, timer_elapsed_ = 0, timer_irq_cycle_ = 0;
    bool timer_started_ = false, timer_irq_enabled_ = false, timer_irq_pending_ = false;
    std::map<uint16_t,uint16_t> cbus_written_;
    uint32_t lcd_header_ = 0, lcd_control_ = 0;
    bool lcd_header_written_ = false, lcd_control_written_ = false;
    uint64_t lcd_headers_ = 0, lcd_data_words_ = 0, lcd_status_reads_ = 0;
    uint32_t table_, ram_base_ = 0;
    uint16_t manufacturer_, device_;
    struct Flash {
        uint32_t base;
        uint16_t manufacturer, device, id2, id3, handshake;
        bool intel, extended;
        bool identify = false;
        unsigned unlock = 0;
        uint32_t burst_configuration = 0;
        bool burst_configured = false;
    };
    std::array<Flash, 3> flash_{};
    std::vector<Bank> banks_;
    std::vector<uint8_t> ram_;
    // Exact flash-routine destination observed in ROM 0x57f0; no surrounding
    // device window is treated as memory. Unwritten bytes remain unknown.
    std::array<uint8_t, 0x9c> code_scratch_{}, code_scratch_written_{};
    std::map<uint32_t, Latch> latches_;
    struct ProbeReg { uint32_t initial, current; uint8_t select; };
    std::map<uint32_t, ProbeReg> probe_regs_;
    uint32_t word(size_t offset) const;
    bool flash_command(Flash& flash, const BootBusRequest& request);
    bool flash_identify(const Flash& flash, const BootBusRequest& request, uint32_t& data);
};
