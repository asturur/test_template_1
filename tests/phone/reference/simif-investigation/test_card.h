#pragma once
#include <array>
#include <cstdint>
#include <deque>

// Diagnostic GSM T=0 card, separate from the unverified SIMIF controller.
// The ICCID and directory metadata are fabricated. Unknown files/commands
// return errors; this intentionally implements only observed commands.
class TestCard {
public:
    struct Snapshot {
        uint16_t selected, directory, file;
        unsigned count, select_bytes, terminal_bytes, output_size;
        std::array<uint8_t,5> header;
        std::array<uint8_t,64> output;
    };
    Snapshot save() const {
        Snapshot v{}; v.selected=selected_; v.directory=directory_; v.file=file_; v.count=count_;
        v.select_bytes=select_bytes_; v.terminal_bytes=terminal_bytes_; v.header=header_;
        v.output_size=unsigned(output_.size());
        if (v.output_size > v.output.size()) v.output_size=v.output.size();
        for (unsigned i=0;i<v.output_size;++i) v.output[i]=output_[i];
        return v;
    }
    bool restore(const Snapshot &v) {
        if (v.count>4 || v.select_bytes>2 || v.terminal_bytes>255 || v.output_size>v.output.size()) return false;
        selected_=v.selected; directory_=v.directory; file_=v.file; count_=v.count; select_bytes_=v.select_bytes; terminal_bytes_=v.terminal_bytes;
        header_=v.header; output_.clear();
        for (unsigned i=0;i<v.output_size;++i) output_.push_back(v.output[i]);
        return true;
    }
    unsigned available() const { return unsigned(output_.size()); }
    void reset() { selected_=0x3f00; directory_=0x3f00; count_=0; select_bytes_=0; terminal_bytes_=0; output_.clear(); }
    void write(uint8_t v) {
        if (terminal_bytes_) { if (--terminal_bytes_ == 0) { emit(0x90); emit(0); } return; }
        if (select_bytes_) {
            file_ = uint16_t((file_ << 8) | v);
            if (--select_bytes_ == 0) {
                if (file_ == 0x3f00 || file_ == 0x7f20 ||
                    (file_ == 0x2fe2 && directory_ == 0x3f00) ||
                    ((file_ == 0x6fb7 || file_ == 0x6f05 || file_ == 0x6fae || file_ == 0x6f38 || file_ == 0x6f7e || file_ == 0x6fad || file_ == 0x6f07 || file_ == 0x6f78) && directory_ == 0x7f20)) {
                    selected_=file_;
                    if (file_ == 0x3f00 || file_ == 0x7f20) directory_=file_;
                    emit(0x9f); emit(file_ == 0x3f00 || file_ == 0x7f20 ? 0x16 : 0x0f);
                } else { emit(0x94); emit(0x04); }
            }
            return;
        }
        header_[count_++]=v;
        if (count_ != 5) return;
        count_=0;
        if (header_[0] != 0xa0) { emit(0x6e); emit(0); return; }
        if (header_[1] == 0x10 && header_[2] == 0 && header_[3] == 0 && header_[4] != 0) { terminal_bytes_=header_[4]; emit(0x10); return; }
        if (header_[1] == 0xa4 && header_[2] == 0 && header_[3] == 0 && header_[4] == 2) {
            file_=0; select_bytes_=2; emit(0xa4); return;
        }
        if (header_[1] == 0xc0 && header_[2] == 0 && header_[3] == 0 && header_[4] == 15 && (selected_ == 0x6fb7 || selected_ == 0x6f05 || selected_ == 0x6fae || selected_ == 0x6f38 || selected_ == 0x6f7e || selected_ == 0x6fad || selected_ == 0x6f07 || selected_ == 0x6f78 || selected_ == 0x2fe2)) {
            // GSM 11.11 transparent EF SELECT response; synthetic file metadata.
            const uint8_t length = selected_ == 0x6fb7 ? 3 : selected_ == 0x6f38 ? 16 : selected_ == 0x6f7e ? 11 : selected_ == 0x6fad ? 4 : selected_ == 0x6f07 ? 9 : selected_ == 0x6f78 ? 2 : selected_ == 0x2fe2 ? 10 : 1;
            const uint8_t info[15] = {0,0,0,length,uint8_t(selected_ >> 8),uint8_t(selected_),4,0,0x0f,0xff,0xff,1,2,0,0};
            emit(0xc0); for (auto c : info) emit(c); emit(0x90); emit(0); return;
        }
        if (header_[1] == 0xf2 && header_[2] == 0 && header_[3] == 0 && (header_[4] == 15 || header_[4] == 22)) {
            const uint8_t info[22] = {0,0,0,0,uint8_t(directory_ >> 8),uint8_t(directory_),directory_ == 0x3f00 ? uint8_t(1) : uint8_t(2),0,0,0,0,0,9,0xb0,0,0,2,0,0x83,0x8a,0x83,0x8a};
            emit(0xf2); for (unsigned i=0; i<header_[4]; ++i) emit(info[i]); emit(0x90); emit(0); return;
        }
        if (header_[1] == 0xb0 && selected_ == 0x2fe2 && header_[2] == 0 && header_[3] == 0 && header_[4] == 10) {
            constexpr uint8_t iccid[10] = {0x98,0x10,0x10,0x32,0x54,0x76,0x98,0x10,0x32,0xf8};
            emit(0xb0); for (auto c : iccid) emit(c); emit(0x90); emit(0); return;
        }
        if (header_[1] == 0xb0 && selected_ == 0x6f78 && header_[2] == 0 && header_[3] == 0 && header_[4] == 2) {
            emit(0xb0); emit(0); emit(1); emit(0x90); emit(0); return;
        }
        if (header_[1] == 0xb0 && selected_ == 0x6f07 && header_[2] == 0 && header_[3] == 0 && header_[4] == 9) {
            const uint8_t imsi[9]={8,0x09,0x10,0x10,0x10,0x32,0x54,0x76,0x98};
            emit(0xb0); for (auto b:imsi) emit(b); emit(0x90); emit(0); return;
        }
        if (header_[1] == 0xb0 && selected_ == 0x6fad && header_[2] == 0 && header_[3] == 0 && header_[4] == 4) {
            emit(0xb0); emit(0); emit(0); emit(0); emit(2); emit(0x90); emit(0); return;
        }
        if (header_[1] == 0xb0 && selected_ == 0x6f7e && header_[2] == 0 && header_[3] == 0 && header_[4] == 11) {
            emit(0xb0); for (unsigned i=0; i<10; ++i) emit(0xff); emit(1); emit(0x90); emit(0); return;
        }
        if (header_[1] == 0xb0 && selected_ == 0x6fae && header_[2] == 0 && header_[3] == 0 && header_[4] == 1) {
            emit(0xb0); emit(0x03); emit(0x90); emit(0); return;
        }
        if (header_[1] == 0xb0 && selected_ == 0x6f38 && header_[2] == 0 && header_[3] == 0 && header_[4] == 16) {
            emit(0xb0); for (unsigned i=0; i<16; ++i) emit(0); emit(0x90); emit(0); return;
        }
        if (header_[1] == 0xb0 && selected_ == 0x6f05 && header_[2] == 0 && header_[3] == 0 && header_[4] == 1) {
            emit(0xb0); emit(0x01); emit(0x90); emit(0); return;
        }
        if (header_[1] == 0xb0 && selected_ == 0x6fb7 && header_[2] == 0 && header_[3] == 0 && header_[4] == 3) {
            emit(0xb0); emit(0x11); emit(0xf2); emit(0xff); emit(0x90); emit(0); return;
        }
        emit(0x6d); emit(0); // unsupported INS/parameters
    }
    bool read(uint8_t &v) { if (output_.empty()) return false; v=output_.front(); output_.pop_front(); return true; }
    uint16_t selected() const { return selected_; }
private:
    void emit(uint8_t v) { output_.push_back(v); }
    uint16_t selected_=0x3f00, directory_=0x3f00, file_=0;
    unsigned count_=0, select_bytes_=0, terminal_bytes_=0;
    std::array<uint8_t,5> header_{};
    std::deque<uint8_t> output_;
};
