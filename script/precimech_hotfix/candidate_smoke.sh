#!/usr/bin/env bash
set -euo pipefail
image=${1:?Exact candidate image required}
: "${SOURCE_SHA:?Expected full source SHA required}"
case "$image" in ghcr.io/claudiohideki/jrc-conversas-lab2:sha-*|ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:*) ;; *) exit 2 ;; esac
network=precimech-candidate-smoke
pg=precimech-candidate-smoke-pg
redis=precimech-candidate-smoke-redis
app=precimech-candidate-smoke-app
worker=precimech-candidate-smoke-worker
cleanup() {
  docker rm -f "$app" "$worker" "$pg" "$redis" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
}
# These names must be absent; never replace another task's resources.
for name in "$app" "$worker" "$pg" "$redis"; do
  if docker container inspect "$name" >/dev/null 2>&1; then echo "Smoke resource already exists: $name" >&2; exit 2; fi
done
if docker network inspect "$network" >/dev/null 2>&1; then echo 'Smoke network already exists' >&2; exit 2; fi
docker network create --internal "$network" >/dev/null
trap cleanup EXIT
docker run -d --name "$pg" --network "$network" --tmpfs /var/lib/postgresql/data -p 127.0.0.1:15432:5432 \
  -e POSTGRES_DB=precimech_candidate_test -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=synthetic_test_only pgvector/pgvector:pg16 >/dev/null
docker run -d --name "$redis" --network "$network" -p 127.0.0.1:16379:6379 redis:7.4-alpine redis-server --save '' --appendonly no >/dev/null
for i in $(seq 1 30); do docker exec "$pg" pg_isready -U postgres -d precimech_candidate_test >/dev/null 2>&1 && break; sleep 1; done
export RAILS_ENV=test POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=15432 POSTGRES_DATABASE=precimech_candidate_test
export POSTGRES_USERNAME=postgres POSTGRES_PASSWORD=synthetic_test_only REDIS_URL=redis://127.0.0.1:16379/0
export SECRET_KEY_BASE=synthetic_candidate_smoke_only
export ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
export ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
bundle exec rails db:create db:schema:load
SCHEMA="${RUNNER_TEMP:-/tmp}/precimech-image-test-schema.rb" bundle exec rails db:migrate
env_args=(-e RAILS_ENV=production -e NODE_ENV=production -e SECRET_KEY_BASE -e ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY \
  -e ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY -e ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT \
  -e POSTGRES_HOST="$pg" -e POSTGRES_PORT=5432 -e POSTGRES_DATABASE -e POSTGRES_USERNAME -e POSTGRES_PASSWORD \
  -e REDIS_URL="redis://$redis:6379/0" -e ACTIVE_STORAGE_SERVICE=local -e FORCE_SSL=false -e FRONTEND_URL=http://localhost:13000 \
  -e RAILS_LOG_TO_STDOUT=true -e LOG_LEVEL=error)
lock_before=$(docker run --rm --network none --entrypoint sha256sum "$image" /app/Gemfile.lock)
docker run --rm --network none --entrypoint bundle "$image" check
# Actual image entrypoint and default bundle install. Internal network prevents dependency downloads; checksum detects lockfile drift.
docker run -d --name "$app" --network "$network" -p 127.0.0.1:13000:3000 "${env_args[@]}" \
  --entrypoint docker/entrypoints/rails.sh "$image" \
  bundle exec rails s -p 3000 -b 0.0.0.0 >/dev/null
docker run -d --name "$worker" --network "$network" "${env_args[@]}" \
  --mount "type=bind,source=$PWD/script/precimech_hotfix/smoke_worker_boot.rb,target=/smoke_worker_boot.rb,readonly" \
  --entrypoint bundle "$image" exec sidekiq -r /smoke_worker_boot.rb -q high -c 1 >/dev/null
export SMOKE_IDS_PATH="${RUNNER_TEMP:-/tmp}/precimech-smoke-ids.json"
if ! bundle exec rails runner script/precimech_hotfix/candidate_smoke.rb; then
  docker logs --tail 80 "$app"
  docker logs --tail 80 "$worker"
  exit 1
fi
docker exec -i -e SMOKE_IDS="$(cat "$SMOKE_IDS_PATH")" "$app" bundle exec rails runner - <<'RUBY'
require 'json'
ids = JSON.parse(ENV.fetch('SMOKE_IDS'))
normal = Message.find(ids.fetch('normal_id'))
original = Message.find(ids.fetch('original_id'))
inbox = Inbox.find(ids.fetch('inbox_id'))
callback = { entry: [{ changes: [{ value: { statuses: [{ id: normal.source_id, status: 'delivered' }] } }] }] }.with_indifferent_access
Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: callback).perform
raise 'Artifact callback did not update matching message' unless normal.reload.delivered? && original.reload.failed?
raise 'Artifact callback changed original correlation' unless original.source_id == 'wamid.synthetic-original'
puts JSON.generate(artifact_callback: 'delivered', original: 'failed')
RUBY
test "$(docker exec "$app" cat /app/.git_sha)" = "$SOURCE_SHA"
test "$(docker exec "$worker" cat /app/.git_sha)" = "$SOURCE_SHA"
test "$(docker exec "$app" sha256sum /app/Gemfile.lock)" = "$lock_before"
