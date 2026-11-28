"""Execute the actual workflow's count/error assertions without running Rails, Chrome or shell commands."""
import ast
from pathlib import Path
import unittest
from jrc_call_center_workflow_check import validate_source

WORKFLOW = Path(__file__).resolve().parents[1] / '.github/workflows/call-center-administration.yml'


def compile_stats_guard(text, filename):
    lines = text.splitlines()
    guards = []
    chrome_blocks = 0
    for block in validate_source(text, filename):
        header = lines[block['line'] - 1]
        prefix = len(header) - len(header.lstrip())
        body = '\n'.join(line[prefix:] for line in lines[block['line']:block['end'] - 1])
        tree = ast.parse(body, filename=filename)
        ast.increment_lineno(tree, block['line'])
        # A generic `report` name also belongs to Vitest/RSpec. Only the
        # executed block that actually derives Playwright stats is relevant.
        owns_stats = any(
            isinstance(node, ast.Assign) and len(node.targets) == 1 and
            isinstance(node.targets[0], ast.Name) and node.targets[0].id == 'stats' and
            isinstance(node.value, ast.Subscript) and isinstance(node.value.value, ast.Name) and
            node.value.value.id == 'report' and isinstance(node.value.slice, ast.Constant) and
            node.value.slice.value == 'stats'
            for node in tree.body
        )
        if not owns_stats:
            continue
        chrome_blocks += 1
        for node in tree.body:
            if not isinstance(node, ast.Assert):
                continue
            names = {part.id for part in ast.walk(node.test) if isinstance(part, ast.Name)}
            if names and names.issubset({'stats', 'report'}):
                guards.append(node)
    if chrome_blocks != 1 or len(guards) != 3:
        raise ValueError('Three executed top-level Chrome count/error guards are required')
    return compile(ast.Module(body=guards, type_ignores=[]), filename, 'exec')


class ChromeCounterTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = WORKFLOW.read_text(encoding='utf-8')
        cls.code = compile_stats_guard(cls.text, str(WORKFLOW))

    def check_report(self, *, expected=304, unexpected=0, skipped=0, flaky=0, errors=None):
        stats = {'expected': expected, 'unexpected': unexpected, 'skipped': skipped, 'flaky': flaky}
        exec(self.code, {'__builtins__': {}}, {'stats': stats, 'report': {'errors': errors or []}})

    def test_accepts_304_cases_including_four_native_policy_draft_flows(self):
        self.check_report()

    def test_rejects_300_cases_without_four_native_policy_draft_flows(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=300)

    def test_rejects_296_cases_without_four_native_relationship_flows(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=296)

    def test_rejects_292_cases_without_four_native_sentiment_period_flows(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=292)

    def test_rejects_288_cases_without_four_native_initial_customer_link_flows(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=288)

    def test_rejects_284_cases_without_four_native_human_quality_review_flows(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=284)

    def test_rejects_280_cases_without_the_four_scoped_native_recording_flows(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=280)

    def test_rejects_276_cases_without_the_four_public_native_destination_flows(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=276)

    def test_rejects_the_previous_264_cases_without_explicit_activation(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=264)

    def test_rejects_the_previous_272_cases_without_selected_pending(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=272)

    def test_rejects_the_previous_268_cases_without_native_history(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=268)

    def test_rejects_the_obsolete_256_cases(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=256)

    def test_rejects_missing_extra_or_zero_cases(self):
        for count in [0, 259, 260, 263, 265, 267, 269, 271, 273, 279, 281, 291, 293, 303, 305]:
            with self.subTest(count=count), self.assertRaises(AssertionError):
                self.check_report(expected=count)

    def test_rejects_unexpected_failures(self):
        with self.assertRaises(AssertionError):
            self.check_report(unexpected=1)

    def test_rejects_skipped_cases(self):
        with self.assertRaises(AssertionError):
            self.check_report(skipped=1)

    def test_rejects_flaky_cases(self):
        with self.assertRaises(AssertionError):
            self.check_report(flaky=1)

    def test_rejects_errors_outside_cases(self):
        with self.assertRaises(AssertionError):
            self.check_report(errors=[{'message': 'SYNTHETIC external error'}])

    def test_unrelated_executed_Vitest_assertions_do_not_become_Chrome_guards(self):
        unrelated = "\n      - name: Synthetic separate Vitest report\n        run: |\n          python3 -B - <<'PY'\n          assert report['numTotalTests'] == 81\n          assert report['numFailedTests'] == 0\n          PY\n"
        code = compile_stats_guard(self.text + unrelated, str(WORKFLOW))
        exec(code, {'__builtins__': {}}, {'stats': {'expected': 304, 'unexpected': 0, 'skipped': 0, 'flaky': 0}, 'report': {'errors': []}})

    def test_two_executed_Playwright_stats_blocks_are_not_an_unambiguous_gate(self):
        duplicate = "\n      - name: Synthetic duplicate Playwright source\n        run: |\n          python3 -B - <<'PY'\n          stats = report['stats']\n          assert stats['expected'] == 280\n          PY\n"
        with self.assertRaises(ValueError):
            compile_stats_guard(self.text + duplicate, str(WORKFLOW))

    def test_missing_executed_Playwright_stats_assignment_is_rejected(self):
        text = self.text.replace("stats = report['stats']", '# no executed Playwright source', 1)
        with self.assertRaises(ValueError):
            compile_stats_guard(text, str(WORKFLOW))

    def test_a_disabled_nested_count_guard_is_not_a_valid_executed_gate(self):
        rows = self.text.splitlines()
        index, = [i for i, row in enumerate(rows) if row.strip().startswith("assert stats['expected']")]
        indent = rows[index][:-len(rows[index].lstrip())]
        rows[index] = indent + 'if False:\n' + indent + '    ' + rows[index].strip()
        with self.assertRaises(ValueError):
            compile_stats_guard('\n'.join(rows), str(WORKFLOW))

    def test_a_commented_count_guard_is_not_a_valid_gate(self):
        rows = self.text.splitlines()
        matches = [index for index, line in enumerate(rows) if line.strip().startswith("assert stats['expected']")]
        self.assertEqual(len(matches), 1)
        rows[matches[0]] = rows[matches[0]].replace('assert ', '# removed: ', 1)
        with self.assertRaises(ValueError):
            compile_stats_guard('\n'.join(rows), str(WORKFLOW))


if __name__ == '__main__':
    unittest.main()
