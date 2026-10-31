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
    bool code = false;
};

// An explicit experiment driven by the 4.03 startup tables. This is not
// a verified UPP_WD2 model. Unknown addresses and unwritten latch bits stop.
class BootProfile {
public:
    BootProfile(const std::vector<uint8_t>& rom, size_t rom_bytes, const std::string& kind, bool ideal_clocks = false, bool lcd_probe = false, const std::vector<uint8_t>& rom_tail = {}, bool boot_io_probe = false, const std::map<unsigned, unsigned>& adc_inputs = {}, uint64_t timer_irq_delay = 0, int uem_power_status = -1, int uem_status36 = -1, int uem_status35 = -1, int extra_cbus_write = -1, int extra_cbus_write2 = -1, bool allow_uif_8000 = false, bool allow_icu25 = false, bool gpio210_low_zero = false, bool gpio21a_zero = false, bool gpio216_zero = false, bool uif102_write = false, bool cbus82_readback = false, int cbus80_input = -1, bool cbus8d_zero = false, bool icu46_write = false, bool pupf00a_zero = false, bool sysc0c14_zero = false, const std::map<uint32_t,std::pair<uint32_t,uint8_t>>& probe_regs = {}, bool gpio214_low_zero = false, bool pupf004_low_zero = false, bool gpio206_extra_write = false, bool sysc74_write3 = false, bool gpio24_28_write1 = false, bool timer_compare_probe = false, bool sysc50_44_probe = false, bool icu1c8_probe = false, bool timer_periodic = false, bool block14d_probe = false, bool debug59_sink = false, const std::map<int,int>& cbus_inputs = {}, bool nos_entry_stub = false, bool keypad_gpio = false, bool icu_banks = false, bool timer_units = false, bool cdrive_flash = false, bool unit60_irq3 = false, const std::vector<uint8_t>& nos_image = {}, bool uem_irq_source1 = false, bool epbus_clkblk = false, const std::vector<uint8_t>& cdrive_image = {}, const std::map<uint32_t,uint32_t>& nos_iat = {}, bool nos_periph4000 = false);
    static std::map<unsigned, unsigned> parse_adc_inputs(const std::string& options);
    bool access(const BootBusRequest& request, uint32_t& data, std::string& device);
    void tick();
    // Unit-0x60 compare match delivers FIQ, not IRQ (medint FIQ pump
    // 0x503851bc installed at [0x800004e4]; vector VA 0x1c reads it). Gated
    // by the FIQ-ICU bank-0 enable bit 3 (enable-set 0x0c1201c8, pump reads
    // pending 0x0c1201d0 and expects bit 3).
    bool unit60_fiq() const { return unit60_pending_ && (icu_mask2_[0] >> 3 & 1); }
    bool uem_irq() const { return uem_irq_pending_ && (icu_enable_[0] >> 1 & 1); }
    // LCD DMA done (channel 0x0c120340; display driver enables IRQ bank-0
    // bit 7 before starting a frame transfer, observed 2.3002e9 2026-10-31).
    bool dma_irq() const { return dma_done_pending_ && (icu_enable_[0] >> 7 & 1); }
    bool timer_irq() const { return (timer_irq_pending_ && timer_irq_enabled_) || uem_irq() || dma_irq(); }
    bool has_scheduled_interrupt() const { return timer_irq_delay_ && (timer_remaining_ || timer_irq_pending_ || periodic_remaining_ || unit60_remaining_ || unit60_pending_ || uem_irq_pending_ || unit1_running_); }
    void report(std::ostream& output) const;
    // Writes DMA-transferred LCD frames in bus.tsv row format so
    // render_lcd_frame.py reads the file unchanged.
    void dump_lcd_dma(std::ostream& out) const;
    void set_nos_iat_region(std::vector<uint8_t> v) { nos_iat_region_ = std::move(v); }
    void set_watch_word(uint32_t v) { watch_word_ = v; watch_word_set_ = true; }
    void set_rom_va_dump() { rom_va_dump_ = true; }
    void set_phys2dump(std::map<uint32_t,uint32_t> m) { phys2dump_ = std::move(m); }
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
    bool ideal_clocks_, lcd_probe_, boot_io_probe_, allow_uif_8000_, allow_icu25_, gpio210_low_zero_, gpio21a_zero_, gpio216_zero_, gpio214_low_zero_, pupf004_low_zero_, gpio206_extra_write_, sysc74_write3_, gpio24_28_write1_, timer_compare_probe_, sysc50_44_probe_, icu1c8_probe_, uif102_write_, cbus82_readback_, cbus8d_zero_, icu46_write_, pupf00a_zero_, sysc0c14_zero_, uif_written_ = false, icu25_written_ = false;
    uint16_t pupf004_low_value_ = 0;
    bool sysc74_written_ = false;
    unsigned cbus_stage_ = 0, cbus_transactions_ = 0;
    uint16_t cbus_config_ = 0, cbus_command_ = 0;
    int uem_adc_channel_ = -1, uem_power_status_ = -1, uem_status36_ = -1, uem_status35_ = -1, cbus80_input_ = -1, extra_cbus_write_ = -1, extra_cbus_write2_ = -1;
    std::map<unsigned, unsigned> adc_inputs_;
    uint64_t adc_result_reads_ = 0;
    uint64_t timer_irq_delay_ = 0, timer_remaining_ = 0, timer_elapsed_ = 0, timer_irq_cycle_ = 0;
    bool timer_started_ = false, timer_irq_enabled_ = false, timer_irq_pending_ = false;
    // Explicit periodic-tick hypothesis modeled on the Nokia 6600 recompiler's
    // nk_bus_tick; armed only by the observed ICU 0x1c8 write using the latched
    // compare value. Not verified N-Gage hardware. Not part of checkpoint state:
    // the saved checkpoint precedes the arming write.
    bool timer_periodic_ = false;
    uint64_t periodic_period_ = 0, periodic_remaining_ = 0, periodic_irqs_ = 0;
    // Explicit zero-reset read/write probe for the unidentified UPP block the
    // kernel initializes after the first tick (0x5815053c/0x58150538 and
    // 0x5814d000..0x5814d010, routine 0x5032430c). Function unverified; not
    // checkpoint state (all accesses occur after the restored checkpoint).
    bool block14d_probe_ = false;
    bool nos_periph4000_ = false;  // 0x0c004xxx RW-latch region (stored in block14d_, savestate-compatible)
    std::map<uint32_t, uint32_t> block14d_;
    // Write-only sink for the kernel character-output device at VA 0x59000000
    // (physical 0x0de00000, routine 0x503243a8 with CR/LF handling). The bytes
    // are retained for the report; reads stop. Device identity unverified.
    bool debug59_sink_ = false;
    // Explicit UEM register read inputs for the kernel phase (first seen on
    // the RTC path, command 0x124). Values are hypotheses, not measurements.
    std::map<int, int> cbus_inputs_;
    // SYNTHETIC: the NOS/baseband entry (PA 0x0009d284, called by nosstarter
    // through the kernel's VA 0x51400000 raw-flash window) lives in the
    // hardware-descrambled region whose plaintext exists in no available file
    // (scratch/nem440-flash-extract/out/cipher-analysis.json). This opt-in
    // serves one cache line of MOV R0,#0; BX LR for CODE fetches at the entry
    // line only; nosstarter discards the return value. Not authentic hardware.
    bool nos_entry_stub_ = false;
    uint64_t nos_stub_fetches_ = 0;
    // REAL NOS/GSM module payload from the THC live-device dump (see
    // docs/references.md), served read-only at PA 0x9d280+ in place of the
    // synthetic entry stub (mutually exclusive). The content is authentic
    // running-phone bytes; that our board's raw CS0 window would present the
    // same bytes (descrambler path) is an assumption, not verified silicon.
    std::vector<uint8_t> nos_image_;
    uint64_t nos_image_reads_ = 0;
    // Minimal kernel power-model object, board-backed RW RAM in the NOS window
    // (PA 0x9e000, VA 0x5149e000, supervisor-RW mapped). Pre-initialised as an
    // empty self-linked power-handler queue with an all-ret0 vtable; the stub
    // installs it via ekern ordinal 394. The kernel writes its fields later.
    uint32_t power_model_[16] = {0};
    bool power_model_init_ = false;
    // Keypad GPIO block (ekeyb configures halfword registers 0x0c150400/02/04/08).
    // Zero-reset RW latches: config writes read back; unwritten/input reads are
    // zero = no keys pressed (idle). Standard GPIO-bank model, opt-in.
    bool keypad_gpio_ = false;
    std::map<uint32_t,uint32_t> keypad_regs_;
    // IRQ-ICU enable banks (drivers enable their interrupt sources). Three
    // 32-bit banks: +0x08/+0x48/+0x88 enable-set, +0x0c/+0x4c/+0x8c clear,
    // +0x10/+0x50/+0x90 pending. No asynchronous sources beyond the timer are
    // modelled, so pending reads are zero. Opt-in.
    bool icu_banks_ = false;
    uint32_t icu_enable_[4] = {0,0,0,0};
    uint32_t icu_global_enable_ = 0;
    uint64_t icu_bank_accesses_ = 0;
    // Timer units 1..4 (unit 0 is the modelled periodic tick). RW register
    // latches; status (reg +0x08) reads 0 = not expired. No IRQ from these
    // units yet; if the kernel waits on one a hang will show. Opt-in.
    bool timer_units_ = false;
    std::map<uint32_t,uint32_t> timer_unit_regs_;
    // Flash-program timer hypothesis: medint.pdd's multi-halfword program path
    // enables IRQ source 3 through the kernel Interrupt API mask banks at
    // 0x0c1201c0/0x200/0x240 (+0x0c enable-set, +0x08 enable-clear; disasm
    // 0x503248f0/0x503248a4, pools 0x1201cc/0x12020c/0x12024c and 0x1201c8/
    // 0x120208/0x120248) and programs hw timer unit 0x60 (0x0c120a60). A
    // nonzero unit-0x60 register write while source 3 is enabled raises IRQ
    // source 3 after a fixed assumed delay; any unit-0x60 write acknowledges a
    // pending one; status +0x08 reads 1 while pending. Delay, start/ack
    // register roles and mask readback are hypotheses, not silicon. Opt-in.
    // UEM interrupt hypothesis: the UEM IRQ line is ICU source 1 (driver-init
    // enable 0x0c120108=2 observed at 729M). Opt-in: a kernel-phase CBUS write
    // to UEM reg 0x30 (epbus power-up tail 0x2b=0x81, 0x30=0x40) raises the
    // source; ICU current 0x114 reads 2; bank0 +0x0c bit-1 write acknowledges.
    // Trigger register and source number are hypotheses. Transient: NOT board-
    // checkpoint state; checkpoints must not straddle a pending UEM IRQ.
    bool uem_irq_source1_ = false, uem_irq_pending_ = false;
    uint64_t uem_irqs_ = 0;
    // LCD DMA channel (0x0c120340 block): registers live in keypad_regs_
    // (the generic 0x0c120300 latch bank); this is the transfer/IRQ state.
    bool dma_done_pending_ = false;
    bool watch_word_set_ = false; uint32_t watch_word_ = 0;
    bool rom_va_dump_ = false;   // rom_ is the real-phone VA snapshot (THC dump)
    std::map<uint32_t,uint32_t> phys2dump_;  // phys page -> dump VA offset (real captured map)
    uint64_t lcd_dma_transfers_ = 0;
    std::vector<std::pair<uint32_t,std::vector<uint32_t>>> lcd_dma_frames_;  // (header at arm, words)
    void run_lcd_dma();
    // epbus clock/power sub-block 0x0c120600..0x0c1206ff: epbus sweeps it
    // during peripheral init (writes 0x280 to +0x14, touches +0x04/+0x10/
    // +0x18/+0x24...). Modeled as RW word latches, reset 0 (unwritten reads 0).
    // Register semantics unknown; this unblocks the sweep. Opt-in. Serialized
    // in checkpoint v4.
    bool epbus_clkblk_ = false;
    std::map<uint32_t,uint32_t> epbus_clk_regs_;
    // Timer unit 1 (0x0c120a20): epbus settle-delay timer raising ICU source 1
    // (observed 1.30796e9: control 0x0a24=1, compare 0x0a30=0x7fffffff parked
    // then 0x6590, ICU 0x108=2 re-enable). Counts CPU cycles up to the compare
    // latch; expiry sets the shared source-1 pending. Unit scale unverified.
    // Serialized in board checkpoint v3.
    bool unit1_running_ = false;
    uint64_t unit1_elapsed_ = 0, unit1_compare_ = 0, unit1_irqs_ = 0;
    // Free-running model clock for the 0x0c150112 counter. NOT serialized:
    // the counter is read as deltas only, so restore offset is harmless and
    // old checkpoints stay loadable.
    uint64_t cycles_ = 0;
    bool unit60_irq3_ = false;
    uint32_t icu_mask2_[3] = {0,0,0};
    uint64_t unit60_remaining_ = 0, unit60_irqs_ = 0;
    bool unit60_pending_ = false;
    // Internal user flash = C: drive (LFFS), AMD x16 at PA 0x02400000, 4 MiB.
    // RAM overlay (lazily 0xFF) + a minimal AMD command FSM: reset, blind 0x60
    // sector lock, autoselect (protect-verify reads 0), single-halfword program,
    // sector erase with DQ poll status. Opt-in. Not verified silicon; models
    // only what medint.pdd/LFFS exercises so C: mounts and formats.
    bool cdrive_flash_ = false;
    std::vector<uint8_t> cdrive_;            // 4 MiB overlay, 0xFF = erased
    // Pre-formatted C: LFFS image (from ngvm HLE: build/firmware/thc/
    // cdrive-formatted-1mib.img). Loaded into the overlay at construction so
    // the real firmware's LFFS mount finds a valid volume instead of scanning
    // blank flash to KErrCorrupt. Opt-in cdrive-image=.
    std::vector<uint8_t> cdrive_image_;
    unsigned cdrive_unlock_ = 0;             // AMD unlock cycle counter
    bool cdrive_autoselect_ = false, cdrive_program_ = false, cdrive_erase_armed_ = false;
    uint32_t cdrive_erase_base_ = 0, cdrive_erase_end_ = 0; unsigned cdrive_erase_reads_ = 0;
    uint64_t cdrive_writes_ = 0, cdrive_erases_ = 0;
    void cdrive_sector(uint32_t off, uint32_t& base, uint32_t& end) const;
    bool cdrive_access(const BootBusRequest& request, uint32_t& data, std::string& device);
    uint64_t debug59_writes_ = 0;
    std::string debug59_bytes_;
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
    // Executable scratch 0x0c004748..0x0c0047f3: the boot copies identify
    // stubs here; the kernel Variant registration later stores the interface
    // pointer at 0x0c0047f0 (routine 0x50324248, pool 0x5032429c). Reads of
    // never-written bytes still stop the run.
    // 0x0c004748..0x0c0047fc: covers the kernel fault-dump handoff's three
    // scratch words 0x47f0/f4/f8 (0x50324240) so a panic is captured as
    // latched state instead of killing the run at the second word. Ends at
    // 0x47fc, which the separate cold-boot flag model owns.
    std::array<uint8_t, 0xb4> code_scratch_{}, code_scratch_written_{};
    std::map<uint32_t,uint32_t> nos_iat_;
    // Plaintext import region [0x6e030,0x725c0) from the Nokia data package;
    // set directly after construction (no constructor-signature churn).
    std::vector<uint8_t> nos_iat_region_;
    std::map<uint32_t, Latch> latches_;
    struct ProbeReg { uint32_t initial, current; uint8_t select; };
    std::map<uint32_t, ProbeReg> probe_regs_;
    uint32_t word(size_t offset) const;
    bool flash_command(Flash& flash, const BootBusRequest& request);
    bool flash_identify(const Flash& flash, const BootBusRequest& request, uint32_t& data);
};
