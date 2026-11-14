import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('backoffice_plan', Path(__file__).with_name('jrc_backoffice_ci_plan.py'))
plan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(plan)


class BackofficeCiPlanTest(unittest.TestCase):
    def test_every_existing_spec_stays_in_exactly_one_partition(self):
        paths = plan.inventory()
        groups = plan.partition(paths)
        joined = [path for group in groups.values() for path in group]
        self.assertEqual(sorted(joined), paths)
        self.assertEqual(len(joined), len(set(joined)))
        self.assertEqual([len(groups[key]) for key in ('current', 'submission')], [4, 4])

    def test_reviewed_routes_match_the_existing_native_plan(self):
        plan.verify_native_routes()

    def test_missing_reviewed_fixture_fails_closed(self):
        paths = plan.inventory()
        paths.remove(plan.ROUTES['current'][0])
        with self.assertRaises(ValueError):
            plan.partition(paths)

    def test_duplicate_input_and_duplicate_route_are_rejected(self):
        paths = plan.inventory()
        with self.assertRaises(ValueError):
            plan.partition(paths + paths[:1])
        routes = {key: list(value) for key, value in plan.ROUTES.items()}
        routes['submission'].append(routes['current'][0])
        with self.assertRaises(ValueError):
            plan.partition(paths, routes)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)

    def report(self, name, ids, **summary):
        data = {'examples': [{'id': identity, 'status': 'passed'} for identity in ids],
                'summary': {'example_count': len(ids), 'failure_count': 0, 'pending_count': 0,
                            'errors_outside_of_examples_count': 0, **summary}}
        path = self.root / name
        path.write_text(json.dumps(data), encoding='utf8')
        return path

    def test_three_real_result_shapes_merge_without_losing_ids(self):
        paths = [self.report(str(index), [f'{index}[1:1]']) for index in range(3)]
        result = plan.merge_core(paths)
        self.assertEqual(result['summary']['example_count'], 3)
        self.assertEqual([row['id'] for row in result['examples']], ['0[1:1]', '1[1:1]', '2[1:1]'])

    def test_duplicate_execution_fails_closed(self):
        with self.assertRaises(ValueError):
            plan.merge_core([self.report('one', ['same']), self.report('two', ['same']), self.report('three', ['third'])])

    def test_missing_an_entire_partition_is_rejected(self):
        with self.assertRaises(ValueError):
            plan.merge_core([self.report('one', ['one']), self.report('two', ['two'])])

    def test_failure_pending_outside_error_or_wrong_count_are_rejected(self):
        for key in ('failure_count', 'pending_count', 'errors_outside_of_examples_count', 'example_count'):
            with self.subTest(key=key), self.assertRaises(ValueError):
                plan.merge_core([self.report(key, ['example'], **{key: 2}),
                                 self.report('two', ['second']), self.report('three', ['third'])])

    def test_nonpassing_or_empty_results_are_rejected(self):
        path = self.report('failed-status', ['one'])
        data = json.loads(path.read_text())
        data['examples'][0]['status'] = 'pending'
        path.write_text(json.dumps(data))
        with self.assertRaises(ValueError):
            plan.merge_core([path, self.report('two', ['second']), self.report('three', ['third'])])
        with self.assertRaises(ValueError):
            plan.merge_core([self.report('empty', []), self.report('two', ['second']), self.report('three', ['third'])])


if __name__ == '__main__':
    unittest.main()
