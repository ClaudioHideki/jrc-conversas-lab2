"""Reject new/worse Ruby findings against the fixed base, without mutating source."""
import collections
import json
import pathlib
import re
import subprocess

BASE = 'a24adc6dd8bb660f955b76cce0172ae1638deee2'

def metric(offense, source):
    """Compare the same named method/class, never unrelated metric messages."""
    if not offense['cop_name'].startswith('Metrics/'):
        return None
    line = source.splitlines()[offense['location']['start_line'] - 1].strip()
    context = re.match(r'(?:def\s+([\w.!?=]+)|class\s+([\w:]+))', line)
    values = re.search(r'\[([^\]]+)/(\d+)\]', offense['message'])
    if not context or not values:
        return None
    counts = tuple(float(value) for value in re.findall(r'\d+(?:\.\d+)?', values[1]))
    return (offense['cop_name'], context[1] or context[2]), counts, int(values[2])


def classify(baseline, candidate, old_source, new_source):
    previous = collections.Counter((row['cop_name'], row['message']) for row in baseline if not metric(row, old_source))
    metrics = collections.defaultdict(list)
    for row in baseline:
        value = metric(row, old_source)
        if value:
            metrics[value[0]].append(value)
    added, improved = [], []
    for row in candidate:
        value = metric(row, new_source)
        if value:
            matches = metrics[value[0]]
            match = next((old for old in matches if old[2] == value[2] and len(old[1]) == len(value[1])
                          and all(current <= prior for current, prior in zip(value[1], old[1]))), None)
            if match is None:
                added.append(row)
            else:
                matches.remove(match)
                if match[1] != value[1]:
                    improved.append(dict(context=value[0], before=match[1], after=value[1]))
        else:
            key = (row['cop_name'], row['message'])
            if previous[key] > 0:
                previous[key] -= 1
            else:
                added.append(row)
    return added, improved


def main():
    paths = subprocess.check_output(['git', 'diff', '--name-only', '--diff-filter=ACMR', BASE, 'HEAD', '--', '*.rb'], text=True).splitlines()
    results = []
    for index, path in enumerate(paths, start=1):
        print(json.dumps({'event': 'ruby_lint_progress', 'current': index, 'total': len(paths), 'path': path}), flush=True)
        before = subprocess.run(['git', 'show', f'{BASE}:{path}'], capture_output=True, text=True)
        sources = dict(baseline=before.stdout if before.returncode == 0 else None, candidate=pathlib.Path(path).read_text())
        reports = {}
        for label, source in sources.items():
            if source is None:
                reports[label] = []
                continue
            check = subprocess.run(['bundle', 'exec', 'rubocop', '--stdin', path, '--format', 'json'], input=source, capture_output=True, text=True)
            if check.returncode not in (0, 1):
                raise RuntimeError(f'RuboCop did not complete: {path} {label}')
            report = json.loads(check.stdout)
            if len(report['files']) != 1:
                raise RuntimeError(f'Expected exactly one inspected file: {path}')
            reports[label] = report['files'][0]['offenses']
        added, improved = classify(reports['baseline'], reports['candidate'], sources['baseline'] or '', sources['candidate'])
        results.append(dict(path=path, new_offenses=added, improved_metrics=improved, **reports))
    pathlib.Path('/tmp/call-center-rubocop.json').write_text(json.dumps(results, indent=2) + '\n')
    for result in results:
        for row in result['new_offenses']:
            print(result['path'], row['location']['start_line'], row['cop_name'], row['message'])
    return 1 if any(row['new_offenses'] for row in results) else 0


if __name__ == '__main__':
    raise SystemExit(main())
