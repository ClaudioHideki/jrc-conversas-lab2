"""Regress the original evidence-manifest indentation failure before expensive CI."""
import unittest
from jrc_call_center_workflow_check import validate_source

PREFIX = "          python3 -B - <<'PY'\n"
SUFFIX = "          PY\n"


class WorkflowPythonCheckTest(unittest.TestCase):
    def test_accepts_a_valid_block_without_executing_its_import_or_mutation(self):
        text = PREFIX + "          raise RuntimeError('must only compile')\n" + SUFFIX
        self.assertEqual(len(validate_source(text, 'synthetic.yml')), 1)

    def test_compiles_every_block_in_the_file(self):
        block = PREFIX + "          value = 1\n" + SUFFIX
        self.assertEqual(len(validate_source(block + block, 'synthetic.yml')), 2)

    def test_reproduces_original_manifest_unexpected_indent(self):
        text = PREFIX + "          stats = {}\n            assert stats['expected'] == 200\n" + SUFFIX
        with self.assertRaises(IndentationError):
            validate_source(text, 'synthetic.yml')

    def test_rejects_invalid_python_even_when_shell_indentation_is_valid(self):
        with self.assertRaises(SyntaxError):
            validate_source(PREFIX + "          assert [\n" + SUFFIX, 'synthetic.yml')

    def test_rejects_an_unterminated_block(self):
        with self.assertRaisesRegex(ValueError, 'delimiter'):
            validate_source(PREFIX + "          value = 1\n", 'synthetic.yml')

    def test_rejects_unsupported_heredoc_syntax_instead_of_silently_skipping_it(self):
        with self.assertRaisesRegex(ValueError, 'unreviewed'):
            validate_source("          python3 -B - <<PY\n", 'synthetic.yml')

    def test_rejects_an_empty_file_instead_of_claiming_a_zero_block_approval(self):
        with self.assertRaisesRegex(ValueError, 'no reviewed'):
            validate_source('', 'synthetic.yml')


if __name__ == '__main__':
    unittest.main()
