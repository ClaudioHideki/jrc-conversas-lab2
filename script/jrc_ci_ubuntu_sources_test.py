"""Small source-fixture checks. No APT, network, services or environment changes."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
import uuid
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("jrc_ci_ubuntu_sources", ROOT / ".github/scripts/jrc_ci_ubuntu_sources.py")
sources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sources)
MIRROR = "https://archive.ubuntu.com/ubuntu"
REGIONAL = "http://us-east-2.ec2.archive.ubuntu.com/ubuntu/"
STANZA = """Types: deb
URIs: mirror+file:/etc/apt/apt-mirrors.txt
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: mirror+file:/etc/apt/apt-mirrors.txt
Suites: noble-security
Components: main restricted universe multiverse
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
"""


class UbuntuSourcesTest(unittest.TestCase):
    def setUp(self):
        # Preserve local fixtures; disposable Actions runners retire their own storage.
        parent = Path(os.environ.get("JRC_CI_FIXTURE_ROOT", tempfile.gettempdir()))
        self.root = (parent / ("jrc-ubuntu-source-" + uuid.uuid4().hex)).resolve()
        self.root.mkdir()
        (self.root / "sources.list.d").mkdir()
        (self.root / "sources.list.d/ubuntu.sources").write_text(STANZA, encoding="utf-8")
        (self.root / "apt-mirrors.txt").write_text(REGIONAL + "\n", encoding="utf-8")

    def test_regional_ec2_mirror_file_reproduces_the_actual_runner_and_becomes_https(self):
        result = sources.prepare(self.root, MIRROR)
        self.assertEqual((self.root / "apt-mirrors.txt").read_text().strip(), MIRROR + "/")
        self.assertEqual((self.root / "sources.list.d/ubuntu.sources").read_text(), STANZA)
        self.assertEqual(result["suites"], sorted(sources.SUITES))
        self.assertEqual(result["ubuntu_source_records"], 2)
        self.assertEqual(result["files_changed"], 1)

    def test_separate_native_security_mirror_file_is_resolved_and_verified(self):
        path = self.root / "sources.list.d/ubuntu.sources"
        first, security = STANZA.split("\n\n")
        security = security.replace("apt-mirrors.txt", "apt-mirrors-security.txt")
        path.write_text(first + "\n\n" + security, encoding="utf-8")
        (self.root / "apt-mirrors-security.txt").write_text("http://security.ubuntu.com/ubuntu/\n", encoding="utf-8")
        result = sources.prepare(self.root, MIRROR)
        self.assertEqual(result["suites"], sorted(sources.SUITES))
        self.assertEqual((self.root / "apt-mirrors-security.txt").read_text().strip(), MIRROR + "/")

    def test_alternate_positive_security_flag_spelling_is_also_refused(self):
        path = self.root / "sources.list.d/unsafe.list"
        path.write_text(f"deb [trusted=on] {REGIONAL} noble main", encoding="utf-8")
        with self.assertRaises(sources.SourceError):
            sources.prepare(self.root, MIRROR)
        path.write_text("# disabled fixture\n", encoding="utf-8")
        (self.root / "sources.list.d/ubuntu.sources").write_text(STANZA.replace("Types: deb", "Types: deb\nTrusted: on", 1), encoding="utf-8")
        with self.assertRaises(sources.SourceError):
            sources.prepare(self.root, MIRROR)

    def test_selected_kernel_mirror_is_the_actual_source_for_all_four_suites(self):
        mirror = "https://mirrors.edge.kernel.org/ubuntu"
        result = sources.prepare(self.root, mirror)
        self.assertEqual(result["selected_mirror"], mirror)
        self.assertEqual((self.root / "apt-mirrors.txt").read_text().strip(), mirror + "/")

    def test_all_existing_reviewed_origins_are_normalized_without_changing_keys_or_comments(self):
        for host in ["archive.ubuntu.com", "azure.archive.ubuntu.com", "security.ubuntu.com", "mirrors.edge.kernel.org",
                     "eu-west-3.ec2.archive.ubuntu.com", "us-east-2.ec2.archive.ubuntu.com"]:
            original = f"URIs: http://{host}/ubuntu/ # keep http://example.invalid/comment\n"
            expected = "URIs: https://archive.ubuntu.com/ubuntu/ # keep http://example.invalid/comment\n"
            self.assertEqual(sources.rewrite_text(original, MIRROR), expected)

    def test_legacy_list_retains_architecture_keyring_and_all_suites(self):
        path = self.root / "sources.list"
        original = "\n".join(f"deb [arch=amd64 signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] {REGIONAL} {suite} main" for suite in sorted(sources.SUITES))
        path.write_text(original, encoding="utf-8")
        sources.prepare(self.root, MIRROR)
        self.assertEqual(path.read_text(), original.replace(REGIONAL, MIRROR + "/"))

    def test_deb822_direct_uris_and_continued_suites_are_preserved(self):
        path = self.root / "sources.list.d/ubuntu.sources"
        direct = STANZA.replace("mirror+file:/etc/apt/apt-mirrors.txt", REGIONAL).replace("Suites: noble noble-updates noble-backports", "Suites: noble\n noble-updates noble-backports")
        path.write_text(direct, encoding="utf-8")
        sources.prepare(self.root, MIRROR)
        self.assertEqual(path.read_text(), direct.replace(REGIONAL, MIRROR + "/"))

    def test_nonubuntu_repository_is_not_rewritten_or_logged_as_ubuntu(self):
        path = self.root / "sources.list.d/microsoft.list"
        original = "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/24.04/prod noble main\n"
        path.write_text(original, encoding="utf-8")
        result = sources.prepare(self.root, MIRROR)
        self.assertEqual(path.read_text(), original)
        self.assertEqual(result["ubuntu_source_records"], 2)

    def test_missing_suite_is_rejected_before_any_source_write(self):
        path = self.root / "sources.list.d/ubuntu.sources"
        path.write_text(STANZA.replace("Suites: noble-security", "Suites: noble"), encoding="utf-8")
        with self.assertRaises(sources.SourceError):
            sources.prepare(self.root, MIRROR)
        self.assertEqual((self.root / "apt-mirrors.txt").read_text().strip(), REGIONAL)

    def test_unreviewed_suite_is_not_silently_enabled(self):
        path = self.root / "sources.list.d/ubuntu.sources"
        path.write_text(STANZA.replace("noble-security", "noble-proposed"), encoding="utf-8")
        with self.assertRaises(sources.SourceError):
            sources.prepare(self.root, MIRROR)

    def test_disabled_stanza_cannot_fake_security_suite_coverage(self):
        path = self.root / "sources.list.d/ubuntu.sources"
        path.write_text(STANZA.replace("Suites: noble-security", "Enabled: no\nSuites: noble-security"), encoding="utf-8")
        with self.assertRaises(sources.SourceError):
            sources.prepare(self.root, MIRROR)

    def test_unreviewed_or_plaintext_target_mirrors_are_rejected(self):
        for mirror in ["http://archive.ubuntu.com/ubuntu", "https://example.invalid/ubuntu", MIRROR + "?secret=private"]:
            with self.assertRaises(sources.SourceError):
                sources.prepare(self.root, mirror)
        self.assertEqual((self.root / "apt-mirrors.txt").read_text().strip(), REGIONAL)

    def test_unrecognized_official_regional_host_is_blocked_instead_of_left_as_http(self):
        with self.assertRaises(sources.SourceError):
            sources.rewrite_text("deb http://unknown.archive.ubuntu.com/ubuntu noble main", MIRROR)

    def test_credential_query_or_unexpected_path_in_ubuntu_origin_is_not_silently_rewritten(self):
        for uri in ["https://user:private@archive.ubuntu.com/ubuntu", MIRROR + "?key=private", MIRROR + "#private", MIRROR + "/other"]:
            with self.assertRaises(sources.SourceError):
                sources.rewrite_text("URIs: " + uri, MIRROR)

    def test_lookalike_host_with_ubuntu_keyring_is_rejected_before_mutation(self):
        path = self.root / "sources.list.d/lookalike.list"
        path.write_text("deb [signed-by=/usr/share/keyrings/ubuntu-archive-keyring.gpg] https://archive.ubuntu.com.evil.invalid/ubuntu noble main", encoding="utf-8")
        with self.assertRaises(sources.SourceError):
            sources.prepare(self.root, MIRROR)
        self.assertEqual((self.root / "apt-mirrors.txt").read_text().strip(), REGIONAL)

    def test_insecure_legacy_options_are_never_accepted(self):
        path = self.root / "sources.list.d/unsafe.list"
        for option in ["trusted=yes", "allow-insecure=true", "allow-weak=1", "allow-downgrade-to-insecure=yes"]:
            path.write_text(f"deb [{option}] {REGIONAL} noble main", encoding="utf-8")
            with self.assertRaises(sources.SourceError):
                sources.prepare(self.root, MIRROR)

    def test_insecure_deb822_options_are_never_accepted(self):
        path = self.root / "sources.list.d/ubuntu.sources"
        for option in ["Trusted", "Allow-Insecure", "Allow-Weak", "Allow-Downgrade-To-Insecure"]:
            path.write_text(STANZA.replace("Types: deb", f"Types: deb\n{option}: yes", 1), encoding="utf-8")
            with self.assertRaises(sources.SourceError):
                sources.prepare(self.root, MIRROR)

    def test_unknown_mirror_file_cannot_be_read_as_an_effective_ubuntu_source(self):
        path = self.root / "sources.list.d/ubuntu.sources"
        for uri in ["mirror+file:/private/source.txt", "mirror+file:/etc/apt/unknown.txt", "mirror+file:/etc/apt/../private.txt"]:
            path.write_text(STANZA.replace("mirror+file:/etc/apt/apt-mirrors.txt", uri), encoding="utf-8")
            with self.assertRaises(sources.SourceError):
                sources.prepare(self.root, MIRROR)

    def test_effective_audit_rejects_the_old_http_mirror_list_even_with_a_https_probe(self):
        texts = {self.root / "sources.list.d/ubuntu.sources": STANZA,
                 self.root / "apt-mirrors.txt": REGIONAL + "\n"}
        with self.assertRaises(sources.SourceError):
            sources.validate_sources(texts, self.root, MIRROR)

    def test_empty_effective_mirror_list_cannot_satisfy_the_suite_checks(self):
        (self.root / "apt-mirrors.txt").write_text("# no actual endpoint\n", encoding="utf-8")
        with self.assertRaises(sources.SourceError):
            sources.prepare(self.root, MIRROR)

    def test_only_comment_delimiters_are_ignored_and_uri_fragments_are_rejected(self):
        self.assertEqual(sources.rewrite_text("# keep http://archive.ubuntu.com/ubuntu\n", MIRROR),
                         "# keep http://archive.ubuntu.com/ubuntu\n")
        with self.assertRaises(sources.SourceError):
            sources.rewrite_text("URIs: " + MIRROR + "#private", MIRROR)

    def test_reexecution_is_idempotent_and_does_not_change_the_selected_configuration(self):
        sources.prepare(self.root, MIRROR)
        result = sources.prepare(self.root, MIRROR)
        self.assertEqual(result["files_changed"], 0)
        self.assertEqual(result["suites"], sorted(sources.SUITES))

    def test_shell_keeps_all_existing_probe_limits_and_makes_signature_requirements_explicit(self):
        text = (ROOT / ".github/scripts/jrc_ci_apt_setup.sh").read_text(encoding="utf-8")
        for required in ["--connect-timeout 5 --max-time 10", "--proto '=https' --proto-redir '=https'",
                         'suites=(noble noble-updates noble-backports noble-security)',
                         'Acquire::Retries "2";', 'Acquire::http::Timeout "20";', 'Acquire::https::Timeout "20";',
                         'Acquire::AllowInsecureRepositories "false";', 'APT::Get::AllowUnauthenticated "false";',
                         'Acquire::AllowDowngradeToInsecureRepositories "false";', 'APT::Update::Error-Mode "any";',
                         'sudo apt-get install -y --no-install-recommends "$@"']:
            self.assertIn(required, text)
        self.assertLess(text.index("jrc_ci_ubuntu_sources.py"), text.index("sudo apt-get update"))
        self.assertLess(text.index("jrc_ci_ubuntu_sources_test.py"), text.index("for candidate in"))

    def test_cli_refuses_a_nonowned_or_windows_environment_before_preparing_sources(self):
        with patch.dict(os.environ, {}, clear=True), patch.object(sources, "prepare") as prepare:
            with self.assertRaises(sources.SourceError):
                sources.main()
            prepare.assert_not_called()


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(UbuntuSourcesTest)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() and result.testsRun == 24 and not result.skipped else 1)
