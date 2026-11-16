"""Fail closed on missing, failed, skipped or incomplete candidate test evidence."""
import json
from pathlib import Path
import sys


def verify(kind, evidence, minimum):
    if kind == 'rspec':
        summary = evidence['summary']
        count = summary['example_count']
        invalid = any(summary.get(key, 0) != 0 for key in
                      ['failure_count', 'pending_count', 'errors_outside_of_examples_count'])
    elif kind == 'vitest':
        count = evidence['numTotalTests']
        invalid = (evidence['success'] is not True or evidence['numPassedTests'] != count or
                   any(evidence.get(key, 0) != 0 for key in
                       ['numFailedTests', 'numPendingTests', 'numTodoTests', 'numRuntimeErrorTestSuites']))
    else:
        raise ValueError('unknown evidence kind')
    if invalid or count < minimum or count < 1:
        raise ValueError('candidate evidence failed, skipped, empty or incomplete')
    return count


if __name__ == '__main__':
    kind, filename, minimum = sys.argv[1:]
    evidence = json.loads(Path(filename).read_text())
    count = verify(kind, evidence, int(minimum))
    print(json.dumps({'kind': kind, 'file': filename, 'count': count, 'passed': True, 'pending': 0}))
