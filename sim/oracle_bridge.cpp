// SPDX-License-Identifier: GPL-3.0-or-later
// C ABI for sharing the board model with an independent software ARM engine.
#include "boot_profile.h"
#include <fstream>
#include <iterator>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
thread_local std::string error;
std::vector<uint8_t> load(const char* path) {
    std::ifstream file(path, std::ios::binary);
    if (!file) throw std::runtime_error("cannot open oracle ROM");
    return {std::istreambuf_iterator<char>(file), {}};
}
struct State {
    std::vector<uint8_t> rom, tail;
    BootProfile board;
    std::string device, report;
    State(const char* path, const char* profile, bool clocks, bool lcd, const char* tail_path, bool boot_io, const char* adc_inputs)
        : rom(load(path)), tail(tail_path ? load(tail_path) : std::vector<uint8_t>{}),
          board(rom, rom.size(), profile, clocks, lcd, tail, boot_io, BootProfile::parse_adc_inputs(adc_inputs ? adc_inputs : "")) {}
};
}
extern "C" {
const char* ngage_model_error() { return error.c_str(); }
void* ngage_model_create(const char* path, const char* profile, int clocks, int lcd, const char* tail_path, int boot_io, const char* adc_inputs) {
    try { return new State(path, profile, clocks != 0, lcd != 0, tail_path, boot_io != 0, adc_inputs); }
    catch (const std::exception& e) { error = e.what(); return nullptr; }
}
void ngage_model_destroy(void* state) { delete static_cast<State*>(state); }
int ngage_model_access(void* opaque, uint32_t address, uint8_t select,
                       int write, uint32_t value, uint32_t* data) {
    try {
        auto& state = *static_cast<State*>(opaque);
        const bool accepted = state.board.access({address,value,select,write != 0}, *data, state.device);
        error = accepted ? "" : state.board.reason();
        return accepted ? 1 : 0;
    } catch (const std::exception& e) { error = e.what(); return -1; }
}
const char* ngage_model_device(void* opaque) {
    return static_cast<State*>(opaque)->device.c_str();
}
const char* ngage_model_report(void* opaque) {
    auto& state = *static_cast<State*>(opaque);
    std::ostringstream output;
    state.board.report(output);
    state.report = output.str();
    return state.report.c_str();
}
}
