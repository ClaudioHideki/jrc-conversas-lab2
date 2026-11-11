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
docker run -d --name "$pg" --network "$network" --tmpfs /var/lib/postgresql/data \
  -e POSTGRES_DB=precimech_candidate_test -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=synthetic_test_only pgvector/pgvector:pg16 >/dev/null
docker run -d --name "$redis" --network "$network" redis:7.4-alpine redis-server --save '' --appendonly no >/dev/null
ready=0
for i in $(seq 1 60); do
  if docker exec "$pg" pg_isready -h 127.0.0.1 -p 5432 -U postgres -d precimech_candidate_test >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
if [ "$ready" != 1 ]; then docker logs --tail 80 "$pg"; exit 1; fi
# Internal networks do not need published ports: the native Linux Docker host can use the bridge IPs.
pg_ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$pg")
redis_ip=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$redis")
export SMOKE_DB_HOST="$pg_ip"
export RAILS_ENV=test POSTGRES_HOST="$pg_ip" POSTGRES_PORT=5432 POSTGRES_DATABASE=precimech_candidate_test
export POSTGRES_USERNAME=postgres POSTGRES_PASSWORD=synthetic_test_only REDIS_URL="redis://$redis_ip:6379/0"
# DATABASE_URL takes precedence over POSTGRES_*; always override any caller/.env value.
export DATABASE_URL="postgresql://postgres:synthetic_test_only@$pg_ip:5432/precimech_candidate_test"
export SECRET_KEY_BASE=synthetic_candidate_smoke_only
export ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
export ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
export ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
bundle exec rails db:create db:schema:load
SCHEMA="${RUNNER_TEMP:-/tmp}/precimech-image-test-schema.rb" bundle exec rails db:migrate
env_args=(-e RAILS_ENV=production -e NODE_ENV=production -e SECRET_KEY_BASE -e ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY \
  -e ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY -e ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT \
  -e DATABASE_URL="postgresql://postgres:synthetic_test_only@$pg:5432/precimech_candidate_test" -e POSTGRES_HOST="$pg" -e POSTGRES_PORT=5432 -e POSTGRES_DATABASE -e POSTGRES_USERNAME -e POSTGRES_PASSWORD \
  -e REDIS_URL="redis://$redis:6379/0" -e ACTIVE_STORAGE_SERVICE=local -e FORCE_SSL=false -e FRONTEND_URL=http://localhost:13000 \
  -e RAILS_LOG_TO_STDOUT=true -e LOG_LEVEL=error)
lock_before=$(docker run --rm --network none --entrypoint sha256sum "$image" /app/Gemfile.lock)
docker run --rm --network none --entrypoint bundle "$image" check
# Actual image entrypoint and default bundle install. Internal network prevents dependency downloads; checksum detects lockfile drift.
docker run -d --name "$app" --network "$network" "${env_args[@]}" \
  --entrypoint docker/entrypoints/rails.sh "$image" \
  bundle exec rails s -p 3000 -b 0.0.0.0 >/dev/null
docker run -d --name "$worker" --network "$network" "${env_args[@]}" \
  --mount "type=bind,source=$PWD/script/precimech_hotfix/smoke_worker_boot.rb,target=/smoke_worker_boot.rb,readonly" \
  --entrypoint bundle "$image" exec sidekiq -r /smoke_worker_boot.rb -q high -c 1 >/dev/null
export SMOKE_APP_HOST="$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$app")"
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
retry_message = Message.find(ids.fetch('retry_id'))
recovered = Message.find(ids.fetch('recovered_id'))
%w[delivered sent failed].each do |status|
  callback[:entry][0][:changes][0][:value][:statuses][0] = { id: retry_message.source_id, status: status }.with_indifferent_access
  Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: callback).perform
end
%w[delivered failed].each do |status|
  callback[:entry][0][:changes][0][:value][:statuses][0] = { id: recovered.source_id, status: status }.with_indifferent_access
  Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: callback).perform
end
raise 'Retry receipt regressed after early read' unless retry_message.reload.read?
raise 'Recovered retry receipt regressed after delivery' unless recovered.reload.delivered?
raise 'Original transient failure changed' unless Message.find(ids.fetch('eligible_original_id')).failed? && Message.find(ids.fetch('lost_original_id')).failed?
puts JSON.generate(artifact_retry_callback: 'read', recovered_callback: 'delivered', original_attempts: 'failed')
RUBY
# Boot the exact previous installed revision as a read-only reader of the additive schema.
# No old worker is started: it cannot process the new retry job classes.
rollback_image=ghcr.io/claudiohideki/jrc-conversas-lab2@sha256:40d8073e0861b156f344c1f4fb882e8472c9560149ef5a353d27a5a4b23fb2d1
docker pull --platform linux/amd64 "$rollback_image"
docker run --rm -i --network "$network" "${env_args[@]}" -e SMOKE_IDS="$(cat "$SMOKE_IDS_PATH")" \
  --entrypoint bundle "$rollback_image" exec rails runner - <<'ROLLBACK_RUBY'
require 'json'
raise 'Unexpected rollback revision' unless File.read('/app/.git_sha').strip == '4ce8241d35ce862e9d53e9a5dce4df9a1858432c'
ids = JSON.parse(ENV.fetch('SMOKE_IDS'))
ActiveRecord::Base.transaction do
  ActiveRecord::Base.connection.execute('SET TRANSACTION READ ONLY')
  %w[original_id eligible_original_id lost_original_id].each { |key| raise 'Original changed on rollback read' unless Message.find(ids.fetch(key)).failed? }
  raise 'Rollback lost normal message' unless Message.find(ids.fetch('normal_id')).delivered?
  raise 'Rollback lost retry receipt' unless Message.find(ids.fetch('retry_id')).read?
  raise 'Rollback lost recovery receipt' unless Message.find(ids.fetch('recovered_id')).delivered?
  raise 'New job unexpectedly present in old image' if defined?(WhatsappRetryJob)
end
puts JSON.generate(rollback_reader_boot: 'passed', additive_schema_read: 'passed', old_worker_new_jobs_supported: false)
ROLLBACK_RUBY


test "$(docker exec "$app" cat /app/.git_sha)" = "$SOURCE_SHA"
test "$(docker exec "$worker" cat /app/.git_sha)" = "$SOURCE_SHA"
test "$(docker exec "$app" sha256sum /app/Gemfile.lock)" = "$lock_before"
