"""CI-only review artifact: safe formatter suggestions, never source mutation."""
import hashlib
import json
import os
import pathlib
import subprocess

if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('RUNNER_ENVIRONMENT') != 'github-hosted':
    raise SystemExit('Owned disposable CI required')

suggestions = []
report = pathlib.Path(os.environ.get('JRC_CC_LINT_REPORT', '/tmp/call-center-rubocop.json'))
if str(report) not in {'/tmp/call-center-rubocop.json', '/tmp/call-center-ending-public-lint.json'}:
    raise SystemExit('Exact owned lint report required')
if report.is_file():
    data = json.loads(report.read_text())
    rows = data['files'] if isinstance(data, dict) else data
    for row in rows:
        offenses = row['offenses'] if isinstance(data, dict) else row['new_offenses']
        cops = sorted({offense['cop_name'] for offense in offenses if offense.get('correctable')})
        if not cops:
            continue
        path = row['path']
        source = pathlib.Path(path).read_text()
        check = subprocess.run(['bundle', 'exec', 'rubocop', '--stdin', path, '--autocorrect', '--stderr',
                                '--format', 'json', '--only', ','.join(cops)], input=source, capture_output=True, text=True)
        if check.returncode not in (0, 1):
            raise RuntimeError(f'Safe RuboCop suggestion failed: {path}')
        corrected = check.stdout
        if corrected and corrected != source:
            syntax = subprocess.run(['ruby', '-c'], input=corrected, capture_output=True, text=True)
            if syntax.returncode:
                raise RuntimeError(f'Formatter did not return valid Ruby source: {path}')
            suggestions.append(dict(path=path, original_sha256=hashlib.sha256(source.encode()).hexdigest(), source=corrected))
        if pathlib.Path(path).read_text() != source:
            raise RuntimeError(f'Unexpected source mutation: {path}')

changed = subprocess.check_output(['git', 'diff', '--name-only', '--diff-filter=ACMR',
                                   'a24adc6dd8bb660f955b76cce0172ae1638deee2', 'HEAD', '--', 'app/javascript'], text=True).splitlines()
frontend = [name for name in changed if name.endswith(('.vue', '.js'))]
if frontend:
    result = subprocess.run(['pnpm', 'exec', 'eslint', *frontend, '--fix-dry-run', '--format', 'json'], capture_output=True, text=True)
    if result.returncode not in (0, 1):
        raise RuntimeError('ESLint suggestion failed')
    for row in json.loads(result.stdout):
        if 'output' in row:
            path = str(pathlib.Path(row['filePath']).relative_to(pathlib.Path.cwd()))
            source = pathlib.Path(path).read_text()
            suggestions.append(dict(path=path, original_sha256=hashlib.sha256(source.encode()).hexdigest(), source=row['output']))

pathlib.Path('/tmp/call-center-lint-suggestions.json').write_text(json.dumps(suggestions, indent=2) + '\n')
print(f'{len(suggestions)} formatter suggestions retained for review; candidate source unchanged')
