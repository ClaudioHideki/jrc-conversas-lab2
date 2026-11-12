#!/usr/bin/env bash
set -euo pipefail
test "$GITHUB_ACTIONS" = true
test "$RUNNER_ENVIRONMENT" = github-hosted
base='docker.io/library/ruby:3.4.12-alpine3.24@sha256:a28982cf8ed78eb0d222e51bc6788335d33ef191bfc6fc39da138577e611741d'
mkdir -p "$RUNNER_TEMP/scout-packages" "$RUNNER_TEMP/scout-results"
for version in 5.3.3 5.7.0; do
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 120 "https://rubygems.org/downloads/scout_apm-$version.gem" -o "$RUNNER_TEMP/scout-packages/scout_apm-$version.gem"
done
(cd "$RUNNER_TEMP/scout-packages" && printf '%s\n' \
  'e70ffe8a04f7e9a2d95382f3fdeee6227f6f69620fc8f913c2e98f271dc76116  scout_apm-5.3.3.gem' \
  '5d13f38018d437fcf18aab954b5a1618cc4114c80175d565069bb287e487c7a6  scout_apm-5.7.0.gem' | sha256sum --check)
# Run an existing immutable official base; no Dockerfile, docker build, commit or registry push.
docker run --rm --platform linux/amd64 \
  --mount "type=bind,src=$RUNNER_TEMP/scout-packages,dst=/packages,readonly" \
  --mount "type=bind,src=$GITHUB_WORKSPACE/.github/runtime_fix,dst=/work,readonly" \
  --mount "type=bind,src=$RUNNER_TEMP/scout-results,dst=/out" \
  "$base" sh -eu -c '
    apk add --no-cache build-base
    ruby --version
    gcc --version
    printf "" | gcc -dM -E - | grep __STDC_VERSION__
    apk info -v musl gcc > /out/compiler.txt
    if GEM_HOME=/tmp/scout-old GEM_PATH=/tmp/scout-old gem install --local --ignore-dependencies --no-document /packages/scout_apm-5.3.3.gem > /out/scout-old.log 2>&1; then
      echo "Old Scout unexpectedly compiled; diagnosis not reproduced" >&2; exit 1
    fi
    grep -q "incompatible-pointer-types" /out/scout-old.log
    grep -q "allocations.c" /out/scout-old.log
    GEM_HOME=/tmp/scout-new GEM_PATH=/tmp/scout-new gem install --local --ignore-dependencies --no-document /packages/scout_apm-5.7.0.gem > /out/scout-new.log 2>&1
    ruby /work/allocations_check.rb
  '
docker run --rm --platform linux/amd64 --network none --entrypoint ruby \
  -e EXPECT_PID_ONE=1 \
  --mount "type=bind,src=$GITHUB_WORKSPACE/.github/runtime_build,dst=/probe,readonly" \
  --mount "type=bind,src=$RUNNER_TEMP/scout-results,dst=/out" \
  "$base" /probe/test_receipt.rb /out/pid-one.json
