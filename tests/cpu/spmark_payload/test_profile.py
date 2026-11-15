"""Accounting controls for the simulation-only cycle observer parser."""
import unittest
from profile import parse_profile


def fixture():
    lines=[]
    for i in range(7):
        for bucket,n in enumerate([2,1,0,0,0,0,0,7]):
            lines.append(f'PROFILE_BUCKET index={i} bucket={bucket} cycles={n}')
        for state in range(15):
            lines.append(f'PROFILE_STATE index={i} state={state} cycles={2 if state==0 else 0}')
        lines.append(f'PROFILE_RAW index={i} cycles=10 retire=3 external_wait=0 translation_wait=0 response_ack=1 read_wait=2 write_wait=0 redirects=0 fetch_wait=0')
    for bucket,n in [(0,10),(1,5),(4,15)]:
        lines.append(f'PROFILE_PC bucket={bucket} pc=10000000 cycles={n}')
    observation={'windows':[dict(cycles=10,retire_proxy=3) for _ in range(7)]}
    return '\n'.join(lines),observation


class ProfileAccounting(unittest.TestCase):
    def test_valid(self):
        text,obs=fixture()
        self.assertEqual(len(parse_profile(text,obs)['windows']),7)

    def reject(self,old,new):
        text,obs=fixture()
        with self.assertRaises(ValueError):parse_profile(text.replace(old,new,1),obs)

    def test_bad_bucket_sum(self):
        self.reject('bucket=0 cycles=2','bucket=0 cycles=3')

    def test_duplicate_bucket(self):
        self.reject('PROFILE_BUCKET index=0 bucket=0 cycles=2',
                    'PROFILE_BUCKET index=0 bucket=0 cycles=2\nPROFILE_BUCKET index=0 bucket=0 cycles=2')

    def test_missing_raw_window(self):
        self.reject('PROFILE_RAW index=6','MISSING_RAW index=6')

    def test_missing_state(self):
        self.reject('PROFILE_STATE index=0 state=14 cycles=0','')

    def test_direction_sum(self):
        self.reject('read_wait=2','read_wait=3')

    def test_retirement_sum(self):
        self.reject('retire=3','retire=4')

    def test_bad_histogram(self):
        self.reject('pc=10000000 cycles=10','pc=10000000 cycles=11')

    def test_duplicate_pc(self):
        self.reject('PROFILE_PC bucket=0 pc=10000000 cycles=10',
                    'PROFILE_PC bucket=0 pc=10000000 cycles=10\nPROFILE_PC bucket=0 pc=10000000 cycles=10')


if __name__=='__main__':unittest.main()
