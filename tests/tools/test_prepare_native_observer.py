"""Safety gates for volatile observer writes; no firmware or hardware needed."""
import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
spec = importlib.util.spec_from_file_location('observer', ROOT / 'tools/prepare_native_observer.py')
observer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(observer)


class FreshHoldTests(unittest.TestCase):
    def fresh(self):
        words = [0] * 256
        words[30] = 1  # CPU physically held.
        words[242] = (1 << 4) | (1 << 25)  # Restored and bundle verified.
        return words

    def test_reset_bookkeeping_fetch_is_allowed(self):
        for fetches in (0, 1):
            words = self.fresh()
            words[13] = fetches
            self.assertTrue(observer.held_fresh(words))

    def test_warm_or_running_cpu_is_rejected(self):
        for index, value in ((6, 1), (8, 4), (9, 4), (12, 1), (13, 2),
                             (18, 1), (19, 1), (29, 256), (30, 0)):
            with self.subTest(index=index):
                words = self.fresh()
                words[index] = value
                self.assertFalse(observer.held_fresh(words))

    def test_restore_save_and_error_states_are_rejected(self):
        for bit in (0, 1, 2, 6, 7, 10, 26):
            with self.subTest(bit=bit):
                words = self.fresh()
                words[242] |= 1 << bit
                self.assertFalse(observer.held_fresh(words))
        for required in (4, 25):
            words = self.fresh()
            words[242] &= ~(1 << required)
            self.assertFalse(observer.held_fresh(words))


if __name__ == '__main__':
    unittest.main()
