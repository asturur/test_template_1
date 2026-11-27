#!/usr/bin/env python3
"""Synthetic checks for comparison integrity and the physical-only CPU boundary."""
import contextlib
import csv
import io
import json
from pathlib import Path
import struct
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

import oracle


class OracleChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        scratch = oracle.ROOT / 'scratch'
        scratch.mkdir(exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix='oracle-checks-', dir=scratch)
        cls.directory = Path(cls.temporary.name)
        cls.build = cls.directory / 'build'
        cls.build.mkdir()

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    def fixture(self, code):
        image = bytearray(0x1000)
        def word(at, value):
            struct.pack_into('<I', image, at, value)
        for index, value in enumerate(code):
            word(index * 4, value)
        word(0x830, 2)
        word(0x834, 1)
        for index, value in enumerate((0,0x1000,1,0,0x0a000000,0x800000,2,0)):
            word(0x838 + index * 4, value)
        path = self.directory / 'synthetic.bin'
        path.write_bytes(image)
        return path

    def reference(self, rows, metadata):
        path = self.directory / 'bus.tsv'
        fields = ['cycle','operation','address','byte_enable','data','channel','device']
        with path.open('w') as stream:
            writer = csv.DictWriter(stream, fields, delimiter='\t')
            writer.writeheader()
            for operation, address, select, data, device in rows:
                writer.writerow(dict(cycle=0,operation=operation,address=hex(address),
                                     byte_enable=hex(select),data=hex(data),channel='data',device=device))
        path.with_name('result.json').write_text(json.dumps(metadata))
        return path

    def comparison_fixture(self):
        profile = dict(name='amd16',ideal_clocks=False,lcd_probe=False)
        sources = {'sim/boot_profile.cpp':'fixture-cpp','sim/boot_profile.h':'fixture-h'}
        frontier = dict(rom_sha256='fixture-rom',bridge=dict(sources=sources),boot_profile=profile,
                        blocked_address=0x0c120020,operation='read',byte_enable=15)
        metadata = dict(rom_sha256='fixture-rom',board_model_sources=sources.copy(),boot_profile=profile.copy())
        # ZAP replicates a halfword across both halves; only selected bytes count.
        rows = [('WRITE',0x0c150004,3,0x00800080,'observed_boot_latch'),
                ('UNMODELED_READ',0x0c120020,15,0,'')]
        events = [['WRITE',0x0c150004,3,0x80,'observed_boot_latch']]
        return frontier,metadata,rows,events

    def test_selected_bytes_match(self):
        frontier,metadata,rows,events = self.comparison_fixture()
        result = oracle.compare(self.reference(rows,metadata),events,frontier)
        self.assertTrue(result['io_events_match'])
        self.assertTrue(result['frontier_matches'])

    def test_changed_io_is_rejected(self):
        frontier,metadata,rows,events = self.comparison_fixture()
        events[0][3] ^= 1
        self.assertFalse(oracle.compare(self.reference(rows,metadata),events,frontier)['io_events_match'])

    def test_missing_io_is_rejected(self):
        frontier,metadata,rows,_ = self.comparison_fixture()
        self.assertFalse(oracle.compare(self.reference(rows,metadata),[],frontier)['io_events_match'])

    def test_changed_frontier_is_rejected(self):
        frontier,metadata,rows,events = self.comparison_fixture()
        frontier['blocked_address'] += 4
        self.assertFalse(oracle.compare(self.reference(rows,metadata),events,frontier)['frontier_matches'])

    def test_stale_model_is_rejected(self):
        frontier,metadata,rows,events = self.comparison_fixture()
        metadata['board_model_sources']['sim/boot_profile.cpp'] = 'stale'
        with self.assertRaisesRegex(RuntimeError,'board-model version'):
            oracle.compare(self.reference(rows,metadata),events,frontier)

    def test_other_firmware_is_rejected(self):
        frontier,metadata,rows,events = self.comparison_fixture()
        metadata['rom_sha256'] = 'other'
        with self.assertRaisesRegex(RuntimeError,'firmware hash'):
            oracle.compare(self.reference(rows,metadata),events,frontier)

    def test_other_digest_probe_is_rejected(self):
        frontier,metadata,rows,events = self.comparison_fixture()
        metadata['digest_probe'] = {'mode':'core'}
        with self.assertRaisesRegex(RuntimeError,'digest-metadata probe'):
            oracle.compare(self.reference(rows,metadata),events,frontier)

    def test_other_reconstructed_bytes_are_rejected(self):
        frontier,metadata,rows,events = self.comparison_fixture()
        metadata['rom_extension_sha256'] = 'different-extension'
        with self.assertRaisesRegex(RuntimeError,'reconstructed ROM bytes'):
            oracle.compare(self.reference(rows,metadata),events,frontier)

    def test_other_profile_is_rejected(self):
        frontier,metadata,rows,events = self.comparison_fixture()
        metadata['boot_profile']['lcd_probe'] = True
        with self.assertRaisesRegex(RuntimeError,'board setting'):
            oracle.compare(self.reference(rows,metadata),events,frontier)

    def test_pre_mmu_comparison_excludes_later_device_accesses(self):
        frontier,metadata,rows,events = self.comparison_fixture()
        frontier.update(status='scope_limit',cp15_control=1)
        reference = self.reference(rows,metadata)
        with reference.open('a') as stream:
            stream.write('10\tWRITE\t0x08000000\t0xf\t0x1234\tdata\tobserved_boot_latch\n')
        reference.with_name('cp15.tsv').write_text('cycle\toperation\tcrn\tvalue\n5\tMCR\t1\t0x1\n')
        result = oracle.compare(reference,events,frontier)
        self.assertTrue(result['io_events_match'])
        self.assertTrue(result['frontier_matches'])
        self.assertEqual(result['comparison_scope'],'pre-MMU prefix')
        reference.with_name('cp15.tsv').write_text('cycle\toperation\tcrn\tvalue\n5\tMCR\t1\t0x0\n')
        with self.assertRaisesRegex(RuntimeError,'MMU enable boundary'):
            oracle.compare(reference,events,frontier)

    def test_adc_options_and_invalid_values(self):
        from adc_inputs import parse_inputs, encode_inputs, case_suffix
        values = parse_inputs(['12=800','6=0x200'])
        self.assertEqual(values,{6:512,12:800})
        self.assertEqual(encode_inputs(values),'6=512,12=800')
        self.assertEqual(case_suffix(parse_inputs(['6=512'])),'-adc6-200')
        for options in (['6=-1'],['6=1024'],['14=1'],['6=1','6=2'],['6=1,7=2']):
            with self.assertRaises(ValueError):
                parse_inputs(options)

    def test_other_adc_inputs_are_rejected_even_before_mmu(self):
        frontier,metadata,rows,events = self.comparison_fixture()
        frontier['boot_profile']['uem_adc_inputs'] = [dict(channel=6,value=512,verified=False)]
        with self.assertRaisesRegex(RuntimeError,'ADC input assumptions'):
            oracle.compare(self.reference(rows,metadata),events,frontier)

    def test_timer_irq_assumptions_must_match(self):
        frontier,metadata,rows,events = self.comparison_fixture()
        metadata["boot_profile"]["timer_irq_delay"] = 2000
        with self.assertRaisesRegex(RuntimeError, "timer IRQ assumptions"):
            oracle.compare(self.reference(rows,metadata),events,frontier)

    def test_native_bridge_retains_explicit_adc_inputs(self):
        firmware = self.fixture((0xeafffffe,))
        args = SimpleNamespace(firmware=firmware,profile='amd16',ideal_clocks=True,
                               lcd_probe=True,boot_io_probe=True,adc_inputs={6:512},no_instruction_trace=True)
        with patch.object(oracle,'BUILD',self.build):
            lib,_ = oracle.bridge()
            engine = oracle.Oracle(args,lib,self.directory)
            result = engine.run(2)
        self.assertEqual(result['boot_profile']['uem_adc_inputs'],[dict(channel=6,value=512,verified=False)])
        self.assertEqual(result['boot_profile']['uem_adc_result_reads'],0)

    def test_native_mmu_code_and_data_address_conventions(self):
        for coarse,fast in ((False,False),(True,False),(False,True),(True,True)):
            with self.subTest(coarse=coarse,fast=fast):
                # Bootstrap enables M, then branches to a nonidentity virtual
                # ROM alias. The native load must use the mapped physical data.
                path = self.fixture((0xe3a00003 if fast else 0xe3a00001,0xee010f10,0xe59ff000,0xeafffffe,0x30002000))
                image = bytearray(path.read_bytes());image.extend(bytes(0x8000-len(image)))
                def word(at,value): struct.pack_into('<I',image,at,value)
                word(0x83c,len(image))
                for i,value in enumerate((0xe59f1008,0xe5910000,0xeafffffe,0,0x30003000)):
                    word(0x2000+4*i,value)
                word(0x3000,0x12345678)
                word(0x4000,0x00000c12)
                word(0x4c00,0x00007001 if coarse else 0x00000c12)
                if coarse:
                    word(0x7008,0x00002ff2);word(0x700c,0x00003ff2)
                path.write_bytes(image)
                args = SimpleNamespace(firmware=path,profile='amd16',ideal_clocks=False,
                                       lcd_probe=False,mmu_reference=True,no_instruction_trace=True,fast_rom_reference=fast,compact_bus=fast)
                with patch.object(oracle,'BUILD',self.build):
                    lib,_ = oracle.bridge();engine = oracle.Oracle(args,lib,self.directory)
                    engine.uc.cpr_write(15,0,2,0,0,0,False,0x4000)
                    engine.uc.cpr_write(15,0,3,0,0,0,False,3)
                    result = engine.run(7)
                self.assertEqual(result['status'],'instruction_limit',result)
                self.assertEqual(result['registers']['r0'],0x12345678)
                self.assertEqual(result['pc'],0x30002008)
                self.assertTrue(result['mmu_reference'])

    def test_fast_rom_keeps_unknown_mmio_reads_checked(self):
        path = self.fixture((0xe3a00003,0xee010f10,0xe59ff000,0xeafffffe,0x30002000))
        image = bytearray(path.read_bytes());image.extend(bytes(0x8000-len(image)))
        def word(at,value): struct.pack_into('<I',image,at,value)
        word(0x83c,len(image));word(0x4000,0xc12);word(0x4c00,0xc12)
        word(0x5604,0x0c100c12)
        for i,value in enumerate((0xe59f1008,0xe5910000,0xeafffffe,0,0x58120020)):
            word(0x2000+4*i,value)
        path.write_bytes(image)
        args = SimpleNamespace(firmware=path,profile='amd16',ideal_clocks=False,lcd_probe=False,
                               mmu_reference=True,fast_rom_reference=True,compact_bus=True,no_instruction_trace=True)
        with patch.object(oracle,'BUILD',self.build):
            lib,_ = oracle.bridge();engine = oracle.Oracle(args,lib,self.directory)
            engine.uc.cpr_write(15,0,2,0,0,0,False,0x4000)
            engine.uc.cpr_write(15,0,3,0,0,0,False,3)
            result = engine.run(20)
        self.assertEqual(result['status'],'unmapped_access',result)
        self.assertEqual(result['blocked_address'],0x0c120020)
        self.assertTrue(result['fast_rom_reference'])

    def test_quiescent_loop_is_not_reported_as_masked_failure(self):
        firmware = self.fixture((0xeafffffe,))
        args = SimpleNamespace(firmware=firmware,profile='amd16',ideal_clocks=False,lcd_probe=False,no_instruction_trace=True)
        with patch.object(oracle,'BUILD',self.build):
            lib,_ = oracle.bridge();engine = oracle.Oracle(args,lib,self.directory)
            engine.uc.reg_write(engine.A.UC_ARM_REG_CPSR,0x53)
            result = engine.run(100)
        self.assertEqual(result['status'],'quiescent_loop')
        self.assertEqual(result['blocked_address'],0)

    def test_quiescent_comparison_requires_matching_recent_retirements(self):
        frontier,metadata,rows,events = self.comparison_fixture()
        frontier.update(status='quiescent_loop',blocked_address=0x50003290,registers={'cpsr':0x53})
        metadata.update(status='timeout',cycles=1000)
        path = self.reference(rows[:1],metadata)
        trace = path.with_name('instructions.tsv')
        trace.write_text('cycle\tretired_instruction\n'+''.join(
            f'{968+i}\t50003290:< BAL -2> 80000053\n' for i in range(32)))
        result = oracle.compare(path,events,frontier)
        self.assertTrue(result['io_events_match'])
        self.assertTrue(result['frontier_matches'])
        trace.write_text(trace.read_text().replace('50003290:','50003294:',1))
        self.assertFalse(oracle.compare(path,events,frontier)['frontier_matches'])

    def test_mmu_boundary(self):
        # MOV r0,#1; MCR p15,0,r0,c1,c0,0; B .
        firmware = self.fixture((0xe3a00001,0xee010f10,0xeafffffe))
        args = SimpleNamespace(firmware=firmware,profile='amd16',ideal_clocks=False,
                               lcd_probe=False,no_instruction_trace=True)
        with patch.object(oracle,'BUILD',self.build):
            lib,_ = oracle.bridge()
            engine = oracle.Oracle(args,lib,self.directory)
            result = engine.run(8)
        self.assertEqual(result['status'],'scope_limit')
        self.assertEqual(result['instructions'],2)
        self.assertEqual(result['pc'],8)

    def test_conditional_mmu_write_not_executed(self):
        # EQ is false in the initial CPSR; the MCR must not trip the guard.
        firmware = self.fixture((0xe3a00001,0x0e010f10,0xeafffffe))
        args = SimpleNamespace(firmware=firmware,profile='amd16',ideal_clocks=False,
                               lcd_probe=False,no_instruction_trace=True)
        with patch.object(oracle,'BUILD',self.build):
            lib,_ = oracle.bridge()
            engine = oracle.Oracle(args,lib,self.directory)
            result = engine.run(8)
        self.assertEqual(result['status'],'instruction_limit')

    def test_cli_fails_for_bad_comparison(self):
        # LDR r1,[pc,#4]; LDR r0,[r1]; B .; literal unknown clock status.
        firmware = self.fixture((0xe59f1004,0xe5910000,0xeafffffe,0x0c120020))
        sources = {f'sim/{name}':oracle.sha(oracle.ROOT/'sim'/name)
                   for name in ('boot_profile.cpp','boot_profile.h')}
        metadata = dict(rom_sha256=oracle.sha(firmware),board_model_sources=sources,
                        boot_profile=dict(name='amd16',ideal_clocks=False,lcd_probe=False))
        rows = [('WRITE',0x08000000,15,1,'observed_boot_latch'),
                ('UNMODELED_READ',0x0c120020,15,0,'')]
        reference = self.reference(rows,metadata)
        argv = ['oracle.py','--firmware',str(firmware),'--profile','amd16','--compare',str(reference)]
        # Only this synthetic test substitutes the CLI's pinned input hash.
        with patch.object(oracle,'BUILD',self.build), patch.object(oracle,'EXPECTED',oracle.sha(firmware)), \
             patch('sys.argv',argv), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(oracle.main(),1)
            result = json.loads((self.build/'amd16/result.json').read_text())
            self.assertEqual(result['status'],'unmapped_access')
            self.assertTrue(result['comparisons'][0]['frontier_matches'])
            self.assertFalse(result['comparisons'][0]['io_events_match'])
            self.reference(rows[1:],metadata)
            self.assertEqual(oracle.main(),0)


if __name__ == '__main__':
    unittest.main(verbosity=2)
