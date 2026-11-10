import unittest
from jrc_ag_catalog_compare import sql_tokens, function_tokens, differences


class NativeCatalogComparisonTest(unittest.TestCase):
    def test_formatting_and_sql_comments_do_not_change_tokens(self):
        self.assertEqual(sql_tokens("BEGIN IF a=1 THEN RETURN 'two words'; END IF; END;"),
                         sql_tokens("BEGIN\n/* note /* nested */ */ IF a = 1 -- note\nTHEN RETURN 'two words'; END IF; END;"))

    def test_quoted_literal_bytes_remain_exact(self):
        for left, right in [("SELECT 'a b'", "SELECT 'a  b'"),
                            ("SELECT 'approved'", "SELECT 'rejected'"),
                            ('SELECT "a b"', 'SELECT "ab"'),
                            ('SELECT $$a b$$', 'SELECT $$a  b$$')]:
            self.assertNotEqual(sql_tokens(left), sql_tokens(right))

    def test_operators_parameters_and_numbers_cannot_disappear(self):
        for left, right in [('a AND b', 'a OR b'), ('$1', '$ 1'), ('x>=1', 'x>1'),
                            ('a - - b', 'a -- b'), ('count > 0', 'count > 1')]:
            self.assertNotEqual(sql_tokens(left), sql_tokens(right))

    def test_unknown_or_unclosed_input_fails_closed(self):
        for source in ["SELECT 'unclosed", '/* unclosed', 'SELECT $tag$unclosed']:
            with self.assertRaises(ValueError):
                sql_tokens(source)
        with self.assertRaises(ValueError):
            function_tokens('not a native dollar-quoted function')
        with self.assertRaises(ValueError):
            function_tokens('CREATE FUNCTION f() RETURNS text LANGUAGE plpythonu AS $$return 1$$')

    def test_function_body_is_code_but_nested_dollar_literal_is_immutable(self):
        header = 'CREATE OR REPLACE FUNCTION f() RETURNS trigger LANGUAGE plpgsql AS $function$'
        first = header + "BEGIN RETURN 'a b'; END;$function$\n"
        second = header + "\nBEGIN\n RETURN 'a b';\nEND;\n$function$\n"
        self.assertEqual(function_tokens(first), function_tokens(second))
        self.assertNotEqual(function_tokens(first), function_tokens(second.replace("'a b'", "'a  b'")))

    def test_no_other_catalog_field_is_normalized_or_omitted(self):
        base = {'functions': [], 'constraints': [{'convalidated': True, 'definition': 'x > 0'}]}
        changed = {'functions': [], 'constraints': [{'convalidated': False, 'definition': 'x > 0'}]}
        self.assertEqual(differences(base, changed), ['constraints'])
        self.assertEqual(differences(base, {**base, 'missing_guard': []}), ['missing_guard'])


if __name__ == '__main__':
    unittest.main()
