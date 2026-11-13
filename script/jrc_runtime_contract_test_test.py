"""Focused lock-contract regressions; no gems or database needed."""
import unittest
from pathlib import Path
import tempfile
from jrc_runtime_contract_test import verify_reviewed_lock, verify_reviewed_retry_sources, REVIEWED_RETRY_SOURCES

OLD = "    scout_apm (5.3.3)\n      parser\n    rails (7.1.5.2)\n\n  scout_apm\n   ruby 3.4.4p34\n"
NEW = OLD.replace("5.3.3", "5.7.0").replace("\n  scout_apm\n", "\n  scout_apm (= 5.7.0)\n").replace("3.4.4p34", "3.4.12p148")

class ReviewedLockTest(unittest.TestCase):
    def test_exact_reviewed_update(self):
        verify_reviewed_lock(NEW, OLD)

    def test_unrelated_dependency_change_is_rejected(self):
        with self.assertRaises(AssertionError):
            verify_reviewed_lock(NEW.replace("7.1.5.2", "7.1.5.3"), OLD)

    def test_agent_removal_is_rejected(self):
        with self.assertRaises(AssertionError):
            verify_reviewed_lock(NEW.replace("    scout_apm (5.7.0)\n", ""), OLD)

    def test_old_broken_extension_is_rejected(self):
        with self.assertRaises(AssertionError):
            verify_reviewed_lock(NEW.replace("5.7.0", "5.3.3"), OLD)

    def test_unpinned_agent_is_rejected(self):
        with self.assertRaises(AssertionError):
            verify_reviewed_lock(NEW.replace(" (= 5.7.0)", ""), OLD)

    def test_duplicate_agent_is_rejected(self):
        with self.assertRaises(AssertionError):
            verify_reviewed_lock(NEW + "    scout_apm (5.7.0)\n", OLD)


class ReviewedRetrySourceTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        source = Path(__file__).resolve().parent.parent
        for name in REVIEWED_RETRY_SOURCES:
            destination = self.root / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes((source / name).read_bytes())

    def test_exact_reviewed_retry_files_are_accepted(self):
        verify_reviewed_retry_sources(self.root)

    def test_each_modified_retry_file_is_rejected(self):
        for name in REVIEWED_RETRY_SOURCES:
            with self.subTest(path=name):
                path = self.root / name
                original = path.read_bytes()
                path.write_bytes(original + b'\nUNREVIEWED_CHANGE\n')
                with self.assertRaisesRegex(AssertionError, 'Unreviewed retry source'):
                    verify_reviewed_retry_sources(self.root)
                path.write_bytes(original)

    def test_missing_retry_source_is_rejected(self):
        (self.root / 'app/services/whatsapp/retry_policy.rb').unlink()
        with self.assertRaises(FileNotFoundError):
            verify_reviewed_retry_sources(self.root)

if __name__ == "__main__":
    unittest.main()
