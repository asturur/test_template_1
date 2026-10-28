#!/usr/bin/env python3
"""Reject incomplete or unrecognized LCD frames; verify the known clear."""
import csv
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image
import capture_lcd_screen as capture

ROOT = Path(__file__).resolve().parents[1]

class ScreenCaptureTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(dir=ROOT/'scratch', prefix='lcd-capture-test-')
        self.path = Path(self.temp.name)
        self.trace = self.path/'bus.tsv'
        self.out = self.path/'screen'
        (self.path/'result.json').write_text(json.dumps({'status':'unmapped_access'}))

    def tearDown(self):
        self.temp.cleanup()

    def trace_fixture(self, word=0xffffffff, second_command=False, later_command=False):
        with self.trace.open('w',newline='') as f:
            w=csv.writer(f,delimiter='\t')
            w.writerow(['cycle','operation','address','byte_enable','data','channel','device'])
            def write(c,a,d):w.writerow([c,'WRITE',hex(a),'0xf',hex(d),'data','lcd_probe_transport'])
            write(1,0x0c121200,0x09200000);write(2,0x0c121208,0x5c)
            write(3,0x0c121200,capture.HEADER)
            for n in range(capture.WORDS):write(4+n,0x0c121208,word)
            c=4+capture.WORDS
            write(c,0x0c121200,0x09200000);write(c+1,0x0c121208,0xaf)
            if second_command:write(c+2,0x0c121208,0x5c)
            if later_command:write(c+2,0x0c121208,0xae)

    def test_white_clear(self):
        self.trace_fixture();capture.capture(self.trace,self.out)
        with Image.open(self.out/'screen.png') as image:
            self.assertEqual(image.size,(176,208));self.assertEqual(image.getpixel((0,0)),(255,255,255))
        self.assertIn('unverified',json.loads((self.out/'screen.json').read_text())['interpretation'])

    def test_refuses_unknown_pixels_or_later_draw(self):
        for word,again in [(0,False),(0xffffffff,True)]:
            self.trace_fixture(word,again)
            with self.assertRaises(ValueError):capture.capture(self.trace,self.out)

    def test_refuses_unrecognized_later_command(self):
        self.trace_fixture(later_command=True)
        with self.assertRaises(ValueError):capture.capture(self.trace,self.out)

    def test_refuses_incomplete_run(self):
        (self.path/'result.json').write_text('')
        with self.assertRaises(ValueError):capture.capture(self.trace,self.out)

if __name__ == '__main__':unittest.main()
