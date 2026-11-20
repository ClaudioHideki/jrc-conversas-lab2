#!/usr/bin/env bash
# Only disposable GitHub test resources; never install/start the system daemon.
set -euo pipefail
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
test "${GITHUB_REPOSITORY:-}" = ClaudioHideki/jrc-conversas-lab2
test "${GITHUB_REF_NAME:-}" = codex/call-center-control-desk-20261116
test "${RAILS_ENV:-}" = test
test "${POSTGRES_HOST:-}" = 127.0.0.1
test "${POSTGRES_DATABASE:-}" = jrc_sd_bc_portal_concurrency_20261025_test
test "${REDIS_URL:-}" = redis://127.0.0.1:6379/15
test "$(dpkg --print-architecture)" = amd64
[[ ${GITHUB_RUN_ID:-} =~ ^[0-9]+$ ]]
[[ ${GITHUB_RUN_ATTEMPT:-} =~ ^[0-9]+$ ]]
test -d "${RUNNER_TEMP:?}"
test -f "${GITHUB_ENV:?}"
command -v ffprobe
command -v ffmpeg
dpkg-query -W libclamav12

umask 077
native_root="$RUNNER_TEMP/jrc-cc-audio-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
socket_root="/run/jrc-cc-audio-$GITHUB_RUN_ID-$GITHUB_RUN_ATTEMPT"
test ! -e "$native_root"
test ! -e "$socket_root"
mkdir "$native_root"
mkdir "$native_root/package" "$native_root/database" "$native_root/binary"
sudo install -d -m 700 -o "$(id -un)" -g "$(id -gn)" "$socket_root"

# Existing HTTPS APT helper must have refreshed all four signed suites first.
# apt-get download checks package hashes from that authenticated index. No daemon/freshclam package is installed.
candidate="$(LC_ALL=C apt-cache policy clamav-daemon | awk '/Candidate:/ {print $2}')"
[[ $candidate =~ ^[0-9][A-Za-z0-9.+:~_-]+$ ]]
(
  cd "$native_root/package"
  apt-get download "clamav-daemon=$candidate"
)
mapfile -t packages < <(find "$native_root/package" -maxdepth 1 -type f -name '*.deb')
test "${#packages[@]}" = 1
deb="${packages[0]}"
test "$(dpkg-deb -f "$deb" Package)" = clamav-daemon
test "$(dpkg-deb -f "$deb" Version)" = "$candidate"
test "$(dpkg-deb -f "$deb" Architecture)" = amd64
dpkg-deb -x "$deb" "$native_root/binary"
daemon="$native_root/binary/usr/sbin/clamd"
test -x "$daemon"
ldd "$daemon" > "$native_root/binary-dependencies.txt"
if grep -q 'not found' "$native_root/binary-dependencies.txt"; then
  cat "$native_root/binary-dependencies.txt"
  exit 1
fi

# Harmless 60-byte WAV marker. A real engine with a synthetic signature DB proves transport/handling,
# not malware coverage, production signatures or external homologation. Never use EICAR/customer data.
python3 -B - "$native_root/database/synthetic.hdb" <<'PY'
from hashlib import md5
from pathlib import Path
import struct
import sys
wave = b'RIFF' + struct.pack('<I', 52) + b'WAVEfmt ' + struct.pack('<IHHIIHH', 16, 1, 1, 8000, 16000, 2, 16)
wave += b'data' + struct.pack('<I', 16) + b'\0' * 15 + b'\1'
assert len(wave) == 60
Path(sys.argv[1]).write_text(f'{md5(wave).hexdigest()}:{len(wave)}:JRC.Synthetic.AudioByteMarker\n')
PY

cat > "$native_root/clamd.conf" <<EOF
Foreground yes
DatabaseDirectory $native_root/database
LocalSocket $socket_root/clamd.sock
LocalSocketMode 600
FixStaleSocket no
PidFile $socket_root/clamd.pid
MaxThreads 2
MaxQueue 8
StreamMaxLength 40M
MaxScanSize 40M
MaxFileSize 40M
ReadTimeout 30
CommandReadTimeout 10
SelfCheck 0
EOF

setsid "$daemon" --config-file="$native_root/clamd.conf" > "$native_root/startup.log" 2>&1 &
daemon_pid=$!
printf '%s\n' "$daemon_pid" > "$native_root/owned-daemon-pid.txt"
python3 -B - "$socket_root/clamd.sock" "$native_root" "$deb" "$candidate" <<'PY'
from hashlib import sha256
from pathlib import Path
import json
import socket
import sys
import time
path, root = sys.argv[1], Path(sys.argv[2])
deadline = time.monotonic() + 30
while True:
    try:
        with socket.socket(socket.AF_UNIX) as client:
            client.settimeout(2)
            client.connect(path)
            client.sendall(b'zPING\0')
            assert client.recv(64) == b'PONG\0'
        break
    except (OSError, AssertionError):
        if time.monotonic() >= deadline:
            raise RuntimeError('Owned synthetic ClamAV did not become ready') from None
        time.sleep(0.5)
with socket.socket(socket.AF_UNIX) as client:
    client.settimeout(3)
    client.connect(path)
    client.sendall(b'zVERSION\0')
    version = client.recv(2048).rstrip(b'\0').decode('ascii')
assert version.startswith('ClamAV ')
report = {'actual_engine': version, 'signature_database': 'SYNTHETIC_TEST_ONLY', 'malware_coverage_proven': False,
          'external_homologation': False, 'database_sha256': sha256((root / 'database/synthetic.hdb').read_bytes()).hexdigest(),
          'package_sha256': sha256(Path(sys.argv[3]).read_bytes()).hexdigest(), 'package_version': sys.argv[4],
          'binary_sha256': sha256((root / 'binary/usr/sbin/clamd').read_bytes()).hexdigest()}
Path('/tmp/call-center-audio-native-tools.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps(report))
PY

printf 'JRC_CC_AUDIO_CLAMAV_SOCKET=%s\n' "$socket_root/clamd.sock" >> "$GITHUB_ENV"
printf 'JRC_CC_AUDIO_SYNTHETIC_TOOLS_ROOT=%s\n' "$native_root" >> "$GITHUB_ENV"
ffprobe -version | sed -n '1p'
ffmpeg -version | sed -n '1p'
