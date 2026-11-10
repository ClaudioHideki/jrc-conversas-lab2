"""Strict catalog comparison after PostgreSQL-native check/index reparsing.

Function bodies ignore only SQL whitespace/comments outside quoted literals.
Operators, identifiers, literal bytes, parameters and all other catalog fields
remain exact. This is a test gate, not a runtime SQL or authorization parser.
"""
import argparse
import copy
import json
from pathlib import Path
import re


def sql_tokens(source):
    result = []
    index = 0
    while index < len(source):
        if source[index].isspace():
            index += 1
            continue
        if source.startswith('--', index):
            end = source.find('\n', index)
            index = len(source) if end < 0 else end + 1
            continue
        if source.startswith('/*', index):
            depth = 1
            index += 2
            while depth and index < len(source):
                if source.startswith('/*', index):
                    depth += 1
                    index += 2
                elif source.startswith('*/', index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            if depth:
                raise ValueError('Unclosed SQL comment')
            continue
        if source[index] in ("'", '"'):
            start, quote = index, source[index]
            index += 1
            while index < len(source):
                if source[index] == '\\':
                    index += 2
                elif source[index] == quote:
                    index += 1
                    if index < len(source) and source[index] == quote:
                        index += 1
                    else:
                        break
                else:
                    index += 1
            else:
                raise ValueError('Unclosed quoted SQL literal')
            result.append(source[start:index])
            continue
        dollar = re.match(r'\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$', source[index:])
        if dollar:
            tag = dollar.group()
            end = source.find(tag, index + len(tag))
            if end < 0:
                raise ValueError('Unclosed dollar-quoted literal')
            end += len(tag)
            result.append(source[index:end])
            index = end
            continue
        token = re.match(r'\$\d+|[A-Za-z_\u0080-\uffff][A-Za-z_0-9$\u0080-\uffff]*|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?|[+*/<>=~!@#%^&|?:-]+', source[index:])
        value = token.group() if token else source[index]
        result.append(value)
        index += len(value)
    return result


def function_tokens(definition):
    match = re.fullmatch(r'(.*?)\bAS\s+(\$[A-Za-z_0-9]*\$)(.*?)\2\s*', definition, re.S)
    if not match or not re.search(r'\bLANGUAGE (plpgsql|sql)\b', match[1]):
        raise ValueError('Unsupported native function definition; manual review required')
    return [sql_tokens(match[1]), sql_tokens(match[3])]


def comparable(catalog):
    result = copy.deepcopy(catalog)
    for function in result['functions']:
        function['definition'] = function_tokens(function['definition'])
    return result


def differences(baseline, actual):
    left, right = comparable(baseline), comparable(actual)
    return [key for key in sorted(left.keys() | right.keys()) if left.get(key) != right.get(key)]


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('baseline', type=Path)
    parser.add_argument('comparisons', type=Path, nargs='+')
    args = parser.parse_args()
    baseline = json.loads(args.baseline.read_text())
    failed = False
    for path in args.comparisons:
        changed = differences(baseline, json.loads(path.read_text()))
        print(json.dumps({'catalog': str(path), 'different_groups': changed,
                          'checks_and_indexes': 'reparsed by PostgreSQL in rollback-only comparison copies',
                          'functions': 'exact tokens; quoted literal bytes preserved'}))
        failed |= bool(changed)
    raise SystemExit(1 if failed else 0)
