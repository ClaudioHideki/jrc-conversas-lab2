"""Compile literal Python CI blocks without executing them or loading application data."""
import ast
from pathlib import Path
import re
import sys

HEADER = re.compile(r"^( +)python3 -B - <<'([A-Z_]+)'$")


def validate_source(text, filename):
    lines = text.splitlines()
    checked = []
    for index, line in enumerate(lines):
        if 'python3' not in line or '<<' not in line:
            continue
        match = HEADER.fullmatch(line)
        if not match:
            raise ValueError(f'{filename}:{index + 1}: unreviewed Python heredoc syntax')
        prefix, tag = match.groups()
        body = []
        for closing in range(index + 1, len(lines)):
            current = lines[closing]
            if current == prefix + tag:
                break
            if current and not current.startswith(prefix):
                raise ValueError(f'{filename}:{closing + 1}: invalid YAML block indentation')
            body.append(current[len(prefix):] if current else '')
        else:
            raise ValueError(f'{filename}:{index + 1}: missing Python heredoc delimiter')
        source = '\n' * (index + 1) + '\n'.join(body) + '\n'
        ast.parse(source, filename=filename)
        checked.append({'line': index + 1, 'end': closing + 1})
    if not checked:
        raise ValueError(f'{filename}: no reviewed Python blocks found')
    return checked


if __name__ == '__main__':
    path = Path(sys.argv[1])
    blocks = validate_source(path.read_text(encoding='utf-8'), str(path))
    print(f'Compiled {len(blocks)} embedded Python blocks; no commands executed')
