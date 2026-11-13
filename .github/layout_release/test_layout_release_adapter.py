import copy
import unittest
import layout_release_adapter as adapter

class LayoutBindingTest(unittest.TestCase):
    def setUp(self):
        self.files = [{'path': f'app/{n}', 'sha256': 'a' * 64} for n in range(13)]
        self.manifest = {'product_sha': adapter.PRODUCT, 'base': adapter.BASE, 'files': self.files}
        self.contract = {'passed': True, 'approved_runtime_source': adapter.BASE,
                         'product_sha': adapter.PRODUCT, 'infrastructure_sha': adapter.VALIDATION,
                         'reviewed_layout_files': self.files, 'migrations_unchanged': True, 'pnpm_lock_unchanged': True}
        self.paths = [item['path'] for item in self.files]
        self.hashes = {item['path']: item['sha256'] for item in self.files}

    def test_exact_binding(self):
        self.assertTrue(adapter.layout_binding(self.manifest, self.contract, self.paths, self.hashes)['passed'])

    def test_wrong_native_or_product_identity_is_denied(self):
        for key in ['product_sha', 'infrastructure_sha', 'approved_runtime_source']:
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                adapter.layout_binding(self.manifest, {**self.contract, key: 'b' * 40}, self.paths, self.hashes)

    def test_missing_or_duplicate_review_is_denied(self):
        for files in [self.files[:-1], self.files[:-1] + [self.files[0]]]:
            with self.subTest(files=files), self.assertRaises(RuntimeError):
                adapter.layout_binding({**self.manifest, 'files': files}, self.contract, self.paths, self.hashes)

    def test_new_functional_path_is_denied(self):
        with self.assertRaises(RuntimeError):
            adapter.layout_binding(self.manifest, self.contract, self.paths + ['db/migrate/unapproved.rb'], self.hashes)

    def test_changed_reviewed_file_is_denied(self):
        with self.assertRaises(RuntimeError):
            adapter.layout_binding(self.manifest, self.contract, self.paths, {**self.hashes, 'app/0': 'b' * 64})

    def test_false_preservation_claims_are_denied(self):
        for key in ['passed', 'migrations_unchanged', 'pnpm_lock_unchanged']:
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                adapter.layout_binding(self.manifest, {**self.contract, key: False}, self.paths, self.hashes)

    def test_unreviewed_source_manifest_is_denied(self):
        changed = copy.deepcopy(self.contract)
        changed['reviewed_layout_files'][0]['sha256'] = 'b' * 64
        with self.assertRaises(RuntimeError):
            adapter.layout_binding(self.manifest, changed, self.paths, self.hashes)

if __name__ == '__main__':
    unittest.main()
