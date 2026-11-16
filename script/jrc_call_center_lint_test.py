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


if __name__ == '__main__':
    unittest.main()
