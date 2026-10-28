"""Explicit, reproducible analog inputs for the bounded UEM experiment."""
import hashlib
import re


def parse_inputs(options):
    values = {}
    for option in options:
        parts = option.split("=")
        if len(parts) != 2 or any(not re.fullmatch(r"(?:0[xX][0-9a-fA-F]+|[0-9]+)", p) for p in parts):
            raise ValueError("ADC inputs use CHANNEL=VALUE, decimal or hexadecimal")
        channel, value = (int(p, 16 if p.lower().startswith("0x") else 10) for p in parts)
        if channel > 13 or value > 1023:
            raise ValueError("ADC channel must be 0..13 and sample must be 0..1023")
        if channel in values:
            raise ValueError(f"duplicate ADC channel {channel}")
        values[channel] = value
    return dict(sorted(values.items()))


def encode_inputs(values):
    return ",".join(f"{channel}={value}" for channel, value in sorted(values.items()))


def case_suffix(values):
    if not values:
        return ""
    if len(values) == 1:
        channel, value = next(iter(values.items()))
        return f"-adc{channel}-{value:x}"
    return "-adc-" + hashlib.sha256(encode_inputs(values).encode()).hexdigest()[:12]
