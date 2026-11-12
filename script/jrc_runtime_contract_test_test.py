"""Focused lock-contract regressions; no gems or database needed."""
import unittest
from jrc_runtime_contract_test import verify_reviewed_lock

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

if __name__ == "__main__":
    unittest.main()
