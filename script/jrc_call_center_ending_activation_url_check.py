"""Require positive Node URL-regression TAP in the immutable disposable runner."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

assert os.environ.get('GITHUB_ACTIONS') == 'true'
assert os.environ.get('RUNNER_ENVIRONMENT') == 'github-hosted'
sha = os.environ['GITHUB_SHA']
assert re.fullmatch('[a-f0-9]{40}', sha)
assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() == sha
report = Path('/tmp/call-center-ending-activation-url-tests.txt').read_text()
for key, expected in [('tests', 8), ('pass', 8), ('fail', 0), ('cancelled', 0), ('skipped', 0), ('todo', 0)]:
    values = re.findall(rf'^# {key} (\d+)$', report, flags=re.M)
    assert values == [str(expected)], (key, values)
base = 'tests/playwright/tests/e2e/ui/call-center-ending-activation-request'
files = [base + '.mjs', base + '.test.mjs', 'script/jrc_call_center_ending_activation_url_check.py']
proof = {'product_sha': sha, 'examples': 8, 'failures': 0, 'pending': 0,
         'synthetic_URL_logic_only_not_Chrome_acceptance': True,
         'source_sha256': {name: hashlib.sha256(Path(name).read_bytes()).hexdigest() for name in files}}
Path('/tmp/call-center-ending-activation-url-verification.json').write_text(json.dumps(proof, indent=2) + '\n')
print(json.dumps(proof))
