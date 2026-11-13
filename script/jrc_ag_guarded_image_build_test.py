import unittest
from pathlib import Path
from unittest.mock import patch
from jrc_ag_guarded_image_build import identity


class ImageIdentityTest(unittest.TestCase):
    def test_only_exact_owned_manual_candidate_and_builder_are_allowed(self):
        sha = 'a' * 40
        env = {'GITHUB_ACTIONS': 'true', 'RUNNER_ENVIRONMENT': 'github-hosted',
               'GITHUB_REF': 'refs/heads/codex/lab2-ag-consolidada-20261110',
               'GITHUB_EVENT_NAME': 'workflow_dispatch', 'GITHUB_RUN_ATTEMPT': '1', 'GITHUB_RUN_ID': '123',
               'GITHUB_SHA': sha, 'SOURCE_SHA': sha, 'JRC_AG_AUTHORIZED_BUILD_SHA': sha,
               'GITHUB_REPOSITORY': 'ClaudioHideki/jrc-conversas-lab2', 'IMAGE': 'claudiohideki/jrc-conversas-lab2',
               'COMPONENT': 'app', 'JRC_AG_BUILDER': 'jrc-ag-image-123-1'}
        with patch('jrc_ag_guarded_frontend_build.sys.platform', 'linux'):
            self.assertEqual(identity(env), (sha, 'jrc-ag-image-123-1', 'buildx_buildkit_jrc-ag-image-123-10'))
            for key, value in [('SOURCE_SHA', 'b' * 40), ('COMPONENT', 'nico-runtime'), ('IMAGE', 'other/app'),
                               ('GITHUB_REPOSITORY', 'other/app'), ('JRC_AG_BUILDER', 'shared'),
                               ('GITHUB_RUN_ID', ''), ('GITHUB_RUN_ATTEMPT', '2'), ('GITHUB_EVENT_NAME', 'push')]:
                with self.assertRaises(RuntimeError):
                    identity({**env, key: value})
        with patch('jrc_ag_guarded_frontend_build.sys.platform', 'win32'):
            with self.assertRaises(RuntimeError):
                identity(env)


class ImageFrontendHeapTest(unittest.TestCase):
    def test_assets_use_the_scoped_vite_process_without_changing_runtime(self):
        docker = (Path(__file__).resolve().parent.parent / 'docker/Dockerfile').read_text()
        builder, runtime = docker.split('# final build stage\n', 1)
        assets = builder.split('# generate production assets if production environment\n', 1)[1]
        self.assertIn('ARG JRC_VITE_BUILD_HEAP_MIB=6144', builder)
        self.assertIn('VITE_RUBY_VITE_BIN_PATH=/app/script/jrc_vite_build.mjs', assets)
        self.assertIn('bundle exec rake assets:precompile', assets)
        self.assertNotIn('JRC_VITE_BUILD_HEAP_MIB', runtime)
        self.assertNotIn('VITE_RUBY_VITE_BIN_PATH', runtime)
        self.assertNotIn('6144', runtime)


if __name__ == '__main__':
    unittest.main()
