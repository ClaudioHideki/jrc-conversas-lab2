#!/usr/bin/env bash
# Only owned disposable Actions runners; never a workstation or client host.
set -euo pipefail
test "${GITHUB_ACTIONS:-}" = true
test "${RUNNER_ENVIRONMENT:-}" = github-hosted
test "${GITHUB_REPOSITORY:-}" = ClaudioHideki/jrc-conversas-lab2
test "${RUNNER_OS:-}" = Linux
grep -q '^ID=ubuntu$' /etc/os-release

# Reuse the official HTTPS archive procedure already used by build-ghcr.yml.
# Keep Ubuntu signatures/TLS verification and every requested package unchanged.
for source in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources /etc/apt/apt-mirrors*.txt; do
  if [ -f "$source" ]; then
    sudo sed -i -E \
      -e 's|https?://azure[.]archive[.]ubuntu[.]com/ubuntu/?|https://archive.ubuntu.com/ubuntu/|g' \
      -e 's#http://(archive|security)[.]ubuntu[.]com/ubuntu/?#https://\1.ubuntu.com/ubuntu/#g' \
      "$source"
  fi
done
# Playwright --with-deps uses APT again later on the same disposable VM.
printf '%s\n' 'Acquire::Retries "2";' 'Acquire::http::Timeout "20";' \
  'Acquire::https::Timeout "20";' 'APT::Update::Error-Mode "any";' |
  sudo tee /etc/apt/apt.conf.d/99-jrc-disposable-ci-network >/dev/null
sudo apt-get update
sudo apt-get install -y --no-install-recommends "$@"
