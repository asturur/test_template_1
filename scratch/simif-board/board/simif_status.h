#pragma once
#include <cstdint>
// Synthetic DF GSM fixture (not a dumped SIM); preserved for validation.
inline constexpr uint8_t simif_status_reply[] = {
    0x60, 0,0,0,0,0x7f,0x20,2,0,0,0,0,0,9,0,0, 0x90,0
};
// Counterfactual status-word-first probe, not verified STATUS semantics.
inline constexpr uint8_t simif_status_probe[] = {0x60, 0x9f, 0x0f};
