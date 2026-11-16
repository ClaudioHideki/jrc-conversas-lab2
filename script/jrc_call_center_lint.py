"""Compare existing Ruby findings, reject every new offense; no code mutation."""
import collections
import json
import pathlib
import subprocess

BASE = 'a24adc6dd8bb660f955b76cce0172ae1638deee2'
paths = subprocess.check_output(['git', 'diff', '--name-only', '--diff-filter=ACMR', BASE, 'HEAD', '--', '*.rb'], text=True).splitlines()
results = []
for path in paths:
    before = subprocess.run(['git', 'show', f'{BASE}:{path}'], capture_output=True, text=True)
    reports = {}
    for label, source in [('baseline', before.stdout if before.returncode == 0 else None), ('candidate', pathlib.Path(path).read_text())]:
        if source is None:
            reports[label] = []
            continue
        check = subprocess.run(['bundle', 'exec', 'rubocop', '--stdin', path, '--format', 'json'], input=source, capture_output=True, text=True)
        if check.returncode not in (0, 1):
            raise RuntimeError(f'RuboCop did not complete: {path} {label}')
        reports[label] = json.loads(check.stdout)['files'][0]['offenses']
    baseline = collections.Counter((row['cop_name'], row['message']) for row in reports['baseline'])
    added = []
    for row in reports['candidate']:
        key = (row['cop_name'], row['message'])
        if baseline[key] > 0:
            baseline[key] -= 1
        else:
            added.append(row)
    results.append(dict(path=path, new_offenses=added, **reports))
pathlib.Path('/tmp/call-center-rubocop.json').write_text(json.dumps(results, indent=2) + '\n')
for result in results:
    for row in result['new_offenses']:
        print(result['path'], row['location']['start_line'], row['cop_name'], row['message'])
raise SystemExit(1 if any(row['new_offenses'] for row in results) else 0)
