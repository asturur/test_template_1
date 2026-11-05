#pragma once
#include <cstdint>
#include <deque>

// Diagnostic model: bit meanings follow firmware dispatch; FIFO/ack behavior
// is provisional until checked against a real UPP. No card bytes are implied.
class SimIfProbe {
public:
    static constexpr uint16_t rx_event = 0x10;
    static constexpr uint16_t group_bit = 0x04;
    static constexpr uint32_t fiq_bit = 1u << 26;
    void set_group_enable(bool enabled) { enabled_ = enabled; }
    void receive(uint8_t byte) { fifo_.push_back(byte); status_ |= rx_event; }
    uint16_t status() const { return status_; }
    uint16_t group_status() const { return status_ ? group_bit : 0; }
    uint32_t fiq_pending() const { return enabled_ && status_ ? fiq_bit : 0; }
    void acknowledge(uint16_t bits) { status_ &= ~bits; }
    bool pop(uint8_t& byte) {
        if (fifo_.empty()) return false;
        byte = fifo_.front(); fifo_.pop_front(); return true;
    }
private:
    bool enabled_ = false;
    uint16_t status_ = 0;
    std::deque<uint8_t> fifo_;
};
