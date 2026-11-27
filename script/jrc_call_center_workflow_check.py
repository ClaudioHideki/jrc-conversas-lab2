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


def validate_owned_ticket_step(text):
    """The committed spec refuses any DB except its already prepared own database."""
    blocks = [block for block in text.split('      - name: ')
              if '\n        id: recording_ticket_concurrency\n' in block]
    if len(blocks) != 1:
        raise ValueError('Exactly one native recording Ticket contention gate is required')
    config, command = blocks[0].split('        run: |\n', 1)
    if '\n        env:\n          POSTGRES_DATABASE: corporate_gratuity_disposable\n' not in config:
        raise ValueError('Native recording Ticket contention requires its own disposable PostgreSQL database')
    spec = 'spec/requests/api/v1/accounts/jrc_contact_center/recording_ticket_intake_concurrency_spec.rb'
    if 'bundle exec rspec ' + spec not in command:
        raise ValueError('The actual native recording Ticket contention spec must execute')


if __name__ == '__main__':
    path = Path(sys.argv[1])
    blocks = validate_source(path.read_text(encoding='utf-8'), str(path))
    validate_owned_ticket_step(path.read_text(encoding='utf-8'))
    print(f'Compiled {len(blocks)} embedded Python blocks; no commands executed')
