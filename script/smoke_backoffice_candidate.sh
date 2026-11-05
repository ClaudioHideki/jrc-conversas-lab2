#!/usr/bin/env bash
set -euo pipefail

: "${SOURCE_SHA:?Full source SHA required}"
: "${IMAGE:?Configured image repository required}"
: "${RUNNER_TEMP:?CI temporary directory required}"
[[ "$SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]]
test "$(git rev-parse HEAD)" = "$SOURCE_SHA"
candidate="ghcr.io/$IMAGE:sha-$SOURCE_SHA"
prefix="jrc-bo-candidate-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}"
network="$prefix-network"
setup_network="$prefix-setup-network"
storage="$prefix-storage"
postgres="$prefix-pg"
redis="$prefix-redis"
rails="$prefix-rails"
sidekiq="$prefix-sidekiq"
label="jrc.backoffice.candidate=$SOURCE_SHA"

cleanup() {
  for container in "$rails" "$sidekiq" "$postgres" "$redis"; do
    if docker inspect "$container" >/dev/null 2>&1; then
      test "$(docker inspect --format '{{ index .Config.Labels "jrc.backoffice.candidate" }}' "$container")" = "$SOURCE_SHA" || continue
      docker logs --tail 60 "$container" > "$RUNNER_TEMP/$container.log" 2>&1 || true
      docker rm -f -v "$container" >/dev/null
    fi
  done
  docker volume rm "$storage" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  docker network rm "$setup_network" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker network create --internal --label "$label" "$network"
# Only PostgreSQL joins this bridge so the hosted test bundle can prepare its schema.
# Rails, Sidekiq, Redis and the documentary runner retain the internal-only network.
docker network create --label "$label" "$setup_network"
docker volume create --label "$label" "$storage"
docker run -d --name "$postgres" --label "$label" --network "$setup_network" -p 127.0.0.1::5432 \
  -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=disposable-candidate-only \
  -e POSTGRES_DB=backoffice_candidate_smoke_test \
  pgvector/pgvector:pg16@sha256:7b822b0aac60967beb1ea5e576b8602c94c300a157d187f385ae3e0da199b90a
docker network connect --alias "$postgres" "$network" "$postgres"
docker run -d --name "$redis" --label "$label" --network "$network" \
  redis:7.4.0-alpine@sha256:c35af3bbcef51a62c8bae5a9a563c6f1b60d7ebaea4cb5a3ccbcc157580ae098
postgres_ready=false
for attempt in {1..30}; do
  if docker exec "$postgres" pg_isready -h 127.0.0.1 -U postgres >/dev/null; then postgres_ready=true; break; fi
  sleep 1
done
test "$postgres_ready" = true
port=$(docker inspect --format '{{(index (index .NetworkSettings.Ports "5432/tcp") 0).HostPort}}' "$postgres")
[[ "$port" =~ ^[0-9]+$ ]]
# Prepare only the named disposable database using the hosted test dependencies.
RAILS_ENV=test POSTGRES_HOST=127.0.0.1 POSTGRES_PORT="$port" POSTGRES_USERNAME=postgres \
  POSTGRES_PASSWORD=disposable-candidate-only POSTGRES_DATABASE=backoffice_candidate_smoke_test \
  SECRET_KEY_BASE=isolated-candidate-smoke-not-production SCHEMA=db/schema.rb bundle exec rails db:schema:load
RAILS_ENV=test POSTGRES_HOST=127.0.0.1 POSTGRES_PORT="$port" POSTGRES_USERNAME=postgres \
  POSTGRES_PASSWORD=disposable-candidate-only POSTGRES_DATABASE=backoffice_candidate_smoke_test \
  SECRET_KEY_BASE=isolated-candidate-smoke-not-production bundle exec rails runner script/prepare_lab2_candidate_database.rb

# The native worker also runs auxiliary capsules and cron; a one-connection pool starves documentary jobs.
runtime_env=(--network "$network" --label "$label" --mount "type=volume,source=$storage,target=/app/storage"
  -e RAILS_ENV=production -e POSTGRES_HOST="$postgres" -e POSTGRES_PORT=5432
  -e POSTGRES_USERNAME=postgres -e POSTGRES_PASSWORD=disposable-candidate-only
  -e POSTGRES_DATABASE=backoffice_candidate_smoke_test -e REDIS_URL="redis://$redis:6379/15"
  -e SECRET_KEY_BASE=isolated-candidate-smoke-not-production -e CANDIDATE_SHA="$SOURCE_SHA"
  -e LOG_LEVEL=error -e RAILS_LOG_TO_STDOUT=true -e ACTIVE_STORAGE_SERVICE=local
  -e SIDEKIQ_CONCURRENCY=1 -e DB_POOL_SIZE=10
  -e APP_TIME_ZONE=America/Sao_Paulo -e TZ=UTC
  -e URA_HML_TIMEZONE_REDIS_URL="redis://$redis:6379/15")
docker run -d --name "$rails" "${runtime_env[@]}" --entrypoint bundle \
  "$candidate" exec rails server -b 0.0.0.0 -p 3000
docker run -d --name "$sidekiq" "${runtime_env[@]}" --entrypoint bundle \
  "$candidate" exec sidekiq -C config/sidekiq.yml -r ./script/ura_hml_timezone.rb -q low -q ura_hml_timezone_probe
test "$(docker inspect --format '{{.Image}}' "$rails")" = "$(docker inspect --format '{{.Image}}' "$sidekiq")"
ready=false
for attempt in {1..45}; do
  test "$(docker inspect --format '{{.State.Running}}' "$rails")" = true
  test "$(docker inspect --format '{{.State.Running}}' "$sidekiq")" = true
  if docker exec "$rails" bundle exec ruby -rnet/http -e '
    http = Net::HTTP.new("127.0.0.1", 3000, nil)
    http.open_timeout = 1
    http.read_timeout = 2
    exit(http.get("/health").code == "200" ? 0 : 1)
  ' >/dev/null 2>&1; then ready=true; break; fi
  sleep 1
done
test "$ready" = true
docker exec "$rails" bundle exec rails runner script/ura_hml_timezone_check.rb
docker run --rm "${runtime_env[@]}" \
  --mount "type=bind,source=$PWD/script/smoke_backoffice_candidate.rb,target=/candidate-smoke.rb,readonly" \
  --mount "type=bind,source=$PWD/test/fixtures/jrc_backoffice/cnpj_synthetic.png,target=/candidate-fixture.png,readonly" \
  --entrypoint bundle "$candidate" exec rails runner /candidate-smoke.rb
printf 'Exact candidate Rails and Sidekiq image ID: %s\n' "$(docker inspect --format '{{.Image}}' "$rails")"
