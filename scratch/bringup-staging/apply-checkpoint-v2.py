#!/usr/bin/env python3
"""Apply board-checkpoint v2: serialize all current device-model state so
checkpoint/restore works with the full modern flag set. Run only when no
hash-checked simulation is in flight."""
from pathlib import Path
root = Path(__file__).resolve().parents[2]
p = root/'scratch/boot-v15-nosprobe/boot_profile.cpp'
s = p.read_text()

old_save = s[s.index('void BootProfile::save_state'):s.index('void BootProfile::load_state')]
old_load = s[s.index('void BootProfile::load_state'):]
old_load = old_load[:old_load.index('\n}\n')+3]

new_code = '''void BootProfile::save_state(std::ostream& out) const {
    // v2: full device-model state. Maps are written as count + (key,value).
    const uint32_t version = 0x4e470002; state_write(out, version);
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
    if (!out) throw std::runtime_error("failed to save board checkpoint");
}
'''

new_load = '''void BootProfile::load_state(std::istream& in) {
    uint32_t version=0; state_read(in,version); if (version != 0x4e470002) throw std::runtime_error("board checkpoint version mismatch");
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
    state_read(in,uif_written_); state_read(in,icu25_written_); state_read(in,sysc74_written_);
    state_read(in,pupf004_low_value_);
    state_read(in,periodic_period_); state_read(in,periodic_remaining_); state_read(in,periodic_irqs_);
    state_read(in,n); if(n>4096) throw std::runtime_error("invalid checkpoint probe entries"); probe_regs_.clear();
    for(uint64_t i=0;i<n;++i){uint32_t k;ProbeReg v;state_read(in,k);state_read(in,v);probe_regs_[k]=v;}
    state_read(in,n); if(n>4096) throw std::runtime_error("invalid checkpoint block14d entries"); block14d_.clear();
    for(uint64_t i=0;i<n;++i){uint32_t k,v;state_read(in,k);state_read(in,v);block14d_[k]=v;}
    state_read(in,n); if(n>4096) throw std::runtime_error("invalid checkpoint keypad entries"); keypad_regs_.clear();
    for(uint64_t i=0;i<n;++i){uint32_t k,v;state_read(in,k);state_read(in,v);keypad_regs_[k]=v;}
    state_read(in,n); if(n>4096) throw std::runtime_error("invalid checkpoint timer-unit entries"); timer_unit_regs_.clear();
    for(uint64_t i=0;i<n;++i){uint32_t k,v;state_read(in,k);state_read(in,v);timer_unit_regs_[k]=v;}
    state_read(in,icu_enable_); state_read(in,icu_bank_accesses_);
    state_read(in,icu_mask2_);
    state_read(in,unit60_remaining_); state_read(in,unit60_irqs_); state_read(in,unit60_pending_);
    state_read(in,n); if(n && n!=4u<<20) throw std::runtime_error("invalid checkpoint C: overlay size");
    cdrive_.resize(n); if(n) in.read(reinterpret_cast<char*>(cdrive_.data()),n);
    state_read(in,cdrive_unlock_); state_read(in,cdrive_autoselect_); state_read(in,cdrive_program_);
    state_read(in,cdrive_erase_armed_); state_read(in,cdrive_erase_base_); state_read(in,cdrive_erase_end_);
    state_read(in,cdrive_erase_reads_); state_read(in,cdrive_writes_); state_read(in,cdrive_erases_);
    state_read(in,power_model_); state_read(in,power_model_init_);
    state_read(in,nos_stub_fetches_); state_read(in,nos_image_reads_);
    state_read(in,debug59_writes_);
    state_read(in,n); if(n>1u<<20) throw std::runtime_error("invalid checkpoint debug59 length");
    debug59_bytes_.resize(n); if(n) in.read(&debug59_bytes_[0],n);
    if (!in) throw std::runtime_error("truncated board checkpoint");
}
'''

s = s.replace(old_save, new_code)
s = s.replace(old_load, new_load)
assert '0x4e470002' in s and 'post-UIF' not in s
p.write_text(s)
print('boot_profile.cpp checkpoint v2 applied')
