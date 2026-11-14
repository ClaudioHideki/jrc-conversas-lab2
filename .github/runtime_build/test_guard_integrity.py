"""The new acceptance extends the audited runtime guard; no smoke/control removal."""
import ast
import hashlib
from pathlib import Path
import unittest
import guard

HERE=Path(__file__).parent
class GuardIntegrity(unittest.TestCase):
    def setUp(self):
        self.original=(HERE/'approved-guard.fixture.txt').read_text()
        self.current=(HERE/'guard.py').read_text()
        self.assertEqual(hashlib.sha256(self.original.encode()).hexdigest(),'4ef817b48c81de8659bb7e92bdfe909ca67977056abf147673db91761fe1938d')

    def test_original_resource_and_identity_functions_preserved(self):
        def functions(s): return {n.name:ast.dump(n) for n in ast.parse(s).body if isinstance(n,ast.FunctionDef)}
        before,after=functions(self.original),functions(self.current)
        for name in before:
            if name not in ['limits','schema_command']: self.assertEqual(before[name],after[name],name)
        self.assertEqual(set(after)-set(before),{'check_preserved_refs'})

    def test_original_owned_resources_and_readiness_preserved(self):
        def methods(s):
            c=next(n for n in ast.parse(s).body if isinstance(n,ast.ClassDef) and n.name=='Attempt')
            return {n.name:ast.dump(n) for n in c.body if isinstance(n,ast.FunctionDef)}
        before,after=methods(self.original),methods(self.current)
        for name in before:
            if name not in ['__init__','execute','finish','command']: self.assertEqual(before[name],after[name],name)
        self.assertEqual(set(after)-set(before),{'browser'})

    def test_all_original_smokes_remain_mandatory(self):
        for marker in ['probe("native")','probe("scout", "extra.rb")','probe("enqueue")','probe("verify_worker")',
                       'probe("worker_pid_one", "extra.rb")','frontend_receipt(build_log)',
                       'schema_command()','Rails/Sidekiq image mismatch','Actual Rails login/assets missing','Served asset differs']:
            self.assertEqual(self.original.count(marker),self.current.count(marker),marker)
        self.assertLess(self.current.index('self.browser(origin, info)'),self.current.index('self.result["smoke_passed"] = True'))

    def test_continuous_resources_and_owned_kill_are_preserved(self):
        for text in ['self.sample()','os.getpgid(process.pid) == process.pid','os.killpg(process.pid, signal.SIGTERM)',
                     'self.limits.no_other_vite_build()','self.no_foreign_vite()','time.sleep(0.5)']:
            self.assertGreaterEqual(self.current.count(text),self.original.count(text),text)
        self.assertIn('REF_TOKEN = os.environ.pop("GH_TOKEN", "")',self.current)
        self.assertIn('time.monotonic() - last_ref_check >= 30',self.current)
        self.assertIn('p.suffix != ".private"',self.current)

    def test_schema_uses_owned_fresh_migrations_without_exports(self):
        self.assertEqual(guard.schema_command(),['bundle','exec','ruby','/smoke/migrate_without_export.rb'])
        schema=(HERE/'migrate_without_export.rb').read_text()
        for marker in ['Existing application schema refused','dump_schema_after_migration = false',
                       'Tracked schema changed','20261111170000 20261112120000','jrc_history_visibility_revoke']:
            self.assertIn(marker,schema)

if __name__=='__main__': unittest.main(verbosity=2)
