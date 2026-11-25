import unittest
from jrc_call_center_lint import classify


def finding(cop, message, line=1):
    return dict(cop_name=cop, message=message, location=dict(start_line=line))


class IncrementalLintTest(unittest.TestCase):
    def test_accepts_unchanged_and_improved_same_method(self):
        old = finding('Metrics/AbcSize', 'size [<5, 31, 8> 32.4/26]')
        better = finding('Metrics/AbcSize', 'size [<5, 30, 7> 31.21/26]')
        self.assertEqual(classify([old], [old], 'def normalize(x)', 'def normalize(x)'), ([], []))
        added, improved = classify([old], [better], 'def normalize(x)', 'def normalize(x)')
        self.assertEqual(added, [])
        self.assertEqual(len(improved), 1)

    def test_rejects_any_increased_component_even_if_overall_size_falls(self):
        old = finding('Metrics/AbcSize', 'size [<5, 31, 8> 32.4/26]')
        worse = finding('Metrics/AbcSize', 'size [<5, 20, 9> 22.5/26]')
        self.assertEqual(classify([old], [worse], 'def x', 'def x')[0], [worse])

    def test_does_not_inherit_an_unrelated_method_allowance(self):
        row = finding('Metrics/MethodLength', 'length [22/19]')
        self.assertEqual(classify([row], [row], 'def old_method', 'def new_method')[0], [row])

    def test_rejects_longer_classes_and_changed_limits(self):
        old = finding('Metrics/ClassLength', 'length [309/175]')
        for row in [finding('Metrics/ClassLength', 'length [317/175]'), finding('Metrics/ClassLength', 'length [309/180]')]:
            self.assertEqual(classify([old], [row], 'class Client', 'class Client')[0], [row])

    def test_rejects_new_methods_even_when_an_old_method_improves(self):
        old = finding('Metrics/MethodLength', 'length [25/19]')
        improved = finding('Metrics/MethodLength', 'length [21/19]')
        new = finding('Metrics/MethodLength', 'length [25/19]', 2)
        self.assertEqual(classify([old], [improved, new], 'def old', 'def old\ndef new')[0], [new])

    def test_preserves_style_counts_and_rejects_additional_findings(self):
        row = finding('Layout/LineLength', 'Line too long [160/150]')
        self.assertEqual(classify([row], [row, row], 'x', 'x')[0], [row])

    def test_unknown_metric_context_does_not_get_a_numerical_allowance(self):
        old = finding('Metrics/AbcSize', 'size [<5, 31, 8> 32.4/26]')
        new = finding('Metrics/AbcSize', 'size [<5, 20, 7> 22.5/26]')
        self.assertEqual(classify([old], [new], 'unknown context', 'unknown context')[0], [new])


class IncrementalLintProgressTest(unittest.TestCase):
    """Simulated process replies verify the gate itself, never native Ruby."""

    def run_procedure(self, baseline=None, candidate=None, returncode=0):
        import contextlib
        import io
        import json
        from types import SimpleNamespace
        from unittest.mock import Mock, patch
        import jrc_call_center_lint as lint

        baseline, candidate = baseline or [], candidate or []
        baseline_source, candidate_source = 'class Historical', 'class Candidate'
        written = {}

        def fake_path(name):
            value = Mock()
            value.read_text.return_value = candidate_source
            value.write_text.side_effect = lambda text: written.update({str(name): text})
            return value

        def fake_run(command, **options):
            if command[0] == 'git':
                self.assertEqual(command[:2], ['git', 'show'])
                return SimpleNamespace(returncode=0, stdout=baseline_source)
            self.assertEqual(command[:4], ['bundle', 'exec', 'rubocop', '--stdin'])
            self.assertEqual(command[-2:], ['--format', 'json'])
            offenses = baseline if options['input'] == baseline_source else candidate
            return SimpleNamespace(returncode=returncode, stdout=json.dumps({'files': [{'offenses': offenses}]}))

        output = io.StringIO()
        with patch.object(lint.subprocess, 'check_output', return_value='one.rb\ntwo.rb\n'), \
                patch.object(lint.subprocess, 'run', side_effect=fake_run), \
                patch.object(lint.pathlib, 'Path', side_effect=fake_path), contextlib.redirect_stdout(output):
            result = lint.main()
        report = json.loads(written['/tmp/call-center-rubocop.json'])
        progress = [json.loads(line) for line in output.getvalue().splitlines() if line.startswith('{')]
        return result, report, progress

    def test_reports_each_position_without_changing_success_or_report_identity(self):
        result, report, progress = self.run_procedure()
        self.assertEqual(result, 0)
        self.assertEqual([row['path'] for row in report], ['one.rb', 'two.rb'])
        self.assertTrue(all(row['new_offenses'] == [] for row in report))
        self.assertEqual(progress, [
            {'event': 'ruby_lint_progress', 'current': 1, 'total': 2, 'path': 'one.rb'},
            {'event': 'ruby_lint_progress', 'current': 2, 'total': 2, 'path': 'two.rb'},
        ])

    def test_progress_does_not_accept_a_new_offense(self):
        row = finding('Layout/TrailingWhitespace', 'Trailing whitespace detected.')
        result, report, progress = self.run_procedure(candidate=[row])
        self.assertEqual(result, 1)
        self.assertTrue(all(value['new_offenses'] == [row] for value in report))
        self.assertEqual(len(progress), 2)

    def test_progress_preserves_duplicate_style_detection(self):
        row = finding('Layout/TrailingWhitespace', 'Trailing whitespace detected.')
        result, report, _ = self.run_procedure(baseline=[row], candidate=[row, row])
        self.assertEqual(result, 1)
        self.assertTrue(all(value['new_offenses'] == [row] for value in report))

    def test_runtime_failure_remains_an_error_instead_of_a_lint_success(self):
        with self.assertRaisesRegex(RuntimeError, 'RuboCop did not complete: one.rb baseline'):
            self.run_procedure(returncode=2)


if __name__ == '__main__':
    unittest.main()
