"""Render complete direct LCD frames using the existing RGB444 hypothesis.

Partial transfers and controller addressing are not decoded. Before the first
LCD display-on command a complete frame is held until display-on is observed.
"""
from struct import pack

class DirectLCD:
    HEADER = 0x8924d67f
    WORDS = 176 * 208 // 2
    FB = 0x0a000020

    def __init__(self, lcd):
        self.lcd = lcd
        self.header = None
        self.words = bytearray()
        self.memory_write = False
        self.display_on = False
        self.pending = None

    def feed(self, line):
        fields = line.rstrip('\n').split('\t')
        if len(fields) < 7 or fields[1] != 'WRITE' or fields[6] != 'lcd_probe_transport':
            return None
        cycle = int(fields[0]); addr = int(fields[2],16); value = int(fields[4],16)
        if addr == 0x0c121200:
            self.header = value
            self.words.clear()
        elif addr == 0x0c121208:
            if self.header == 0x09200000:
                if value == 0x5c:
                    self.memory_write = True
                    self.pending = None
                elif value == 0xaf:
                    self.display_on = True
                    if self.pending is not None:
                        pixels = self.pending
                        self.pending = None
                        return self.lcd.apply(cycle,self.FB,pixels)
            elif self.header == self.HEADER and self.memory_write:
                self.words.extend(pack('<I',value))
                if len(self.words) == self.WORDS*4:
                    pixels=bytes(self.words)
                    self.memory_write=False
                    if self.display_on:
                        return self.lcd.apply(cycle,self.FB,pixels)
                    self.pending=pixels
        return None
