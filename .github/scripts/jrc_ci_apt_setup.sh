#!/usr/bin/env bash
# Only owned disposable Actions runners; never a workstation or client host.
set -euo pipefail
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
test "${GITHUB_REPOSITORY:-}" = ClaudioHideki/jrc-conversas-lab2
test "${RUNNER_OS:-}" = Linux
grep -q '^ID=ubuntu$' /etc/os-release
grep -q '^VERSION_CODENAME=noble$' /etc/os-release

python3 -B script/jrc_ci_ubuntu_sources_test.py

# Connectivity is a preliminary probe. APT must still validate signed metadata.
suites=(noble noble-updates noble-backports noble-security)
mirror=''
for candidate in https://archive.ubuntu.com/ubuntu https://azure.archive.ubuntu.com/ubuntu https://mirrors.edge.kernel.org/ubuntu; do
  reachable=true
  for suite in "${suites[@]}"; do
    url="$candidate/dists/$suite/InRelease"
    status=''
    if status=$(curl --ipv4 --proto '=https' --proto-redir '=https' --location \
      --fail --silent --show-error --connect-timeout 5 --max-time 10 \
      --output /dev/null --write-out '%{http_code}' -- "$url") && [ "$status" = 200 ]; then
      printf 'CI Ubuntu connectivity OK: %s HTTP=%s\n' "$url" "$status"
    else
      printf 'CI Ubuntu connectivity failed: %s HTTP=%s\n' "$url" "${status:-000}" >&2
      reachable=false
      break
    fi
  done
  if [ "$reachable" = true ]; then
    mirror="$candidate"
    break
  fi
done
if [ -z "$mirror" ]; then
  echo 'No approved HTTPS Ubuntu mirror serves all four suites; preparation stopped.' >&2
  exit 1
fi
printf 'CI Ubuntu mirror selected: %s (APT signature verification follows)\n' "$mirror"

# Resolve the actual Ubuntu sources, including regional EC2 mirror+file lists.
# Only URLs change; the helper verifies all four suites before the first write.
sudo --preserve-env=GITHUB_ACTIONS,RUNNER_ENVIRONMENT,GITHUB_REPOSITORY,RUNNER_OS \
  python3 -B .github/scripts/jrc_ci_ubuntu_sources.py "$mirror"
# Persist the same bounded settings for Playwright --with-deps on this disposable VM.
printf '%s\n' 'Acquire::ForceIPv4 "true";' 'Acquire::Retries "2";' \
  'Acquire::http::Timeout "20";' 'Acquire::https::Timeout "20";' 'APT::Update::Error-Mode "any";' \
  'Acquire::AllowInsecureRepositories "false";' 'Acquire::AllowDowngradeToInsecureRepositories "false";' \
  'APT::Get::AllowUnauthenticated "false";' |
  sudo tee /etc/apt/apt.conf.d/99-jrc-disposable-ci-network >/dev/null
sudo apt-get update
printf 'CI Ubuntu APT metadata update passed with signature checks enabled: %s\n' "$mirror"
sudo apt-get install -y --no-install-recommends "$@"
