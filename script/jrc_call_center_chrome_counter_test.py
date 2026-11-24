"""Execute the actual workflow's count/error assertions without running Rails, Chrome or shell commands."""
import ast
from pathlib import Path
import unittest
from jrc_call_center_workflow_check import validate_source

WORKFLOW = Path(__file__).resolve().parents[1] / '.github/workflows/call-center-administration.yml'


def compile_stats_guard(text, filename):
    lines = text.splitlines()
    guards = []
    for block in validate_source(text, filename):
        header = lines[block['line'] - 1]
        prefix = len(header) - len(header.lstrip())
        body = '\n'.join(line[prefix:] for line in lines[block['line']:block['end'] - 1])
        tree = ast.parse(body, filename=filename)
        ast.increment_lineno(tree, block['line'])
        for node in tree.body:
            if not isinstance(node, ast.Assert):
                continue
            names = {part.id for part in ast.walk(node.test) if isinstance(part, ast.Name)}
            if names and names.issubset({'stats', 'report'}):
                guards.append(node)
    if len(guards) != 3:
        raise ValueError('Three executed top-level Chrome count/error guards are required')
    return compile(ast.Module(body=guards, type_ignores=[]), filename, 'exec')


class ChromeCounterTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = WORKFLOW.read_text(encoding='utf-8')
        cls.code = compile_stats_guard(cls.text, str(WORKFLOW))

    def check_report(self, *, expected=272, unexpected=0, skipped=0, flaky=0, errors=None):
        stats = {'expected': expected, 'unexpected': unexpected, 'skipped': skipped, 'flaky': flaky}
        exec(self.code, {'__builtins__': {}}, {'stats': stats, 'report': {'errors': errors or []}})

    def test_accepts_272_cases_including_four_native_history_runs(self):
        self.check_report()

    def test_rejects_the_previous_264_cases_without_explicit_activation(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=264)

    def test_rejects_the_previous_268_cases_without_native_history(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=268)

    def test_rejects_the_obsolete_256_cases(self):
        with self.assertRaises(AssertionError):
            self.check_report(expected=256)

    def test_rejects_missing_extra_or_zero_cases(self):
        for count in [0, 259, 260, 263, 265, 267, 269, 271, 273]:
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

    def test_a_commented_count_guard_is_not_a_valid_gate(self):
        rows = self.text.splitlines()
        matches = [index for index, line in enumerate(rows) if line.strip().startswith("assert stats['expected']")]
        self.assertEqual(len(matches), 1)
        rows[matches[0]] = rows[matches[0]].replace('assert ', '# removed: ', 1)
        with self.assertRaises(ValueError):
            compile_stats_guard('\n'.join(rows), str(WORKFLOW))


if __name__ == '__main__':
    unittest.main()
