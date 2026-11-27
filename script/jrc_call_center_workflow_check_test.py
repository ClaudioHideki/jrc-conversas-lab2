"""Regress the original evidence-manifest indentation failure before expensive CI."""
import unittest
from jrc_call_center_workflow_check import validate_source, validate_owned_ticket_step

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


class OwnedRecordingTicketWorkflowTest(unittest.TestCase):
    @staticmethod
    def workflow(database='corporate_gratuity_disposable'):
        return ('      - name: Owned committed Ticket test\n'
                '        id: recording_ticket_concurrency\n'
                '        env:\n'
                f'          POSTGRES_DATABASE: {database}\n'
                '        run: |\n'
                '          bundle exec rspec spec/requests/api/v1/accounts/jrc_contact_center/recording_ticket_intake_concurrency_spec.rb\n')

    def test_accepts_the_already_prepared_owned_database_without_running_anything(self):
        validate_owned_ticket_step(self.workflow())

    def test_reproduces_the_inherited_default_database_failure_before_native_execution(self):
        text = self.workflow().replace('        env:\n          POSTGRES_DATABASE: corporate_gratuity_disposable\n', '')
        with self.assertRaisesRegex(ValueError, 'own disposable'):
            validate_owned_ticket_step(text)

    def test_rejects_a_different_or_real_database(self):
        with self.assertRaisesRegex(ValueError, 'own disposable'):
            validate_owned_ticket_step(self.workflow('not_the_owned_database'))

    def test_does_not_accept_a_duplicate_gate_as_proof(self):
        with self.assertRaisesRegex(ValueError, 'Exactly one'):
            validate_owned_ticket_step(self.workflow() + self.workflow())


if __name__ == '__main__':
    unittest.main()
