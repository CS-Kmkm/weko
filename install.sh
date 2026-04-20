#!/bin/bash

set -euo pipefail

compose=(docker compose -f docker-compose2.yml)
bootstrap_marker=/var/tmp/.weko_bootstrap_complete
required_env_vars=(
  INVENIO_WEB_HOST_NAME
  INVENIO_USER_EMAIL
  INVENIO_USER_PASS
  POSTGRES_PASSWORD
  INVENIO_RABBITMQ_USER
  INVENIO_RABBITMQ_PASS
  WEKO_RECORDS_UI_SECRET_KEY
  SECRET_KEY
  WTF_CSRF_SECRET_KEY
  WEKO_TLS_CERT_PATH
  WEKO_TLS_KEY_PATH
)

reset_env=0
no_cache=0
rebuild_assets=0
force_bootstrap=0
pull_images=0

show_usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --reset            Remove containers and named volumes before rebuilding.
  --down-with-volumes
                     Alias of --reset.
  --no-cache         Build images without Docker layer cache.
  --pull-images      Pull prebuilt images instead of building locally.
  --rebuild-assets   Rebuild frontend assets even when bootstrap is skipped.
  --force-bootstrap  Re-run database/index bootstrap without removing volumes.
  -h, --help         Show this help.

Required:
  Create `.env` from `.env.example` and fill the required secrets/certificate paths.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --reset|--down-with-volumes)
      reset_env=1
      force_bootstrap=1
      rebuild_assets=1
      ;;
    --no-cache)
      no_cache=1
      ;;
    --pull-images)
      pull_images=1
      ;;
    --rebuild-assets)
      rebuild_assets=1
      ;;
    --force-bootstrap)
      force_bootstrap=1
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $arg" >&2
      show_usage >&2
      exit 1
      ;;
  esac
done

load_dotenv() {
  if [[ ! -f .env ]]; then
    echo "[ERROR] Missing .env. Copy .env.example to .env and fill the deployment values." >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1091
  source ./.env
  set +a
}

validate_env() {
  local missing=()
  local var

  for var in "${required_env_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done

  if (( ${#missing[@]} )); then
    echo "[ERROR] Missing required variables in .env: ${missing[*]}" >&2
    exit 1
  fi

  if [[ ! -r "${WEKO_TLS_CERT_PATH}" ]]; then
    echo "[ERROR] TLS certificate not readable: ${WEKO_TLS_CERT_PATH}" >&2
    exit 1
  fi

  if [[ ! -r "${WEKO_TLS_KEY_PATH}" ]]; then
    echo "[ERROR] TLS private key not readable: ${WEKO_TLS_KEY_PATH}" >&2
    exit 1
  fi
}

cleanup_python_artifacts() {
  find . -type d \( -name __pycache__ -o -name .tox -o -name .eggs -o -name .pytest_cache \) -prune -exec rm -rf {} +
  find . -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
}

run_web_task() {
  "${compose[@]}" run --rm --no-deps web bash /code/scripts/entrypoint_task.sh "$@"
}

build_images() {
  local build_services=(
    web
    elasticsearch
    nginx
  )
  local build_args=(
    build
    --force-rm
  )
  if (( no_cache )); then
    build_args+=(--no-cache)
  fi

  env DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 \
    docker compose -f docker-compose2.yml "${build_args[@]}" "${build_services[@]}"
}

pull_prebuilt_images() {
  local pull_services=(
    web
    worker
    elasticsearch
    nginx
  )

  "${compose[@]}" pull "${pull_services[@]}"
}

start_infra_services() {
  "${compose[@]}" up -d --no-build postgresql redis elasticsearch rabbitmq
}

start_app_services() {
  local app_services=(
    web
    worker
    scheduler
    nginx
  )

  "${compose[@]}" up -d --no-build "${app_services[@]}"
}

bootstrap_marker_exists() {
  run_web_task bash -lc "test -f '${bootstrap_marker}'" >/dev/null 2>&1
}

run_sql_file() {
  local sql_file=$1
  local container_id
  local target_file

  container_id="$("${compose[@]}" ps -q postgresql)"
  target_file="/tmp/$(basename "$sql_file")"

  docker cp "$sql_file" "${container_id}:${target_file}"
  "${compose[@]}" exec -T postgresql psql -U invenio -d invenio -f "$target_file"
}

rebuild_asset_bundle() {
  run_web_task invenio assets build
  run_web_task invenio collect -v
}

bootstrap_instance() {
  "${compose[@]}" run --rm --no-deps \
    -e RESET_DATABASE=1 \
    -e REBUILD_INDEX=1 \
    web bash /code/scripts/entrypoint_task.sh ./scripts/populate-instance.sh

  run_sql_file scripts/demo/item_type.sql
  run_sql_file scripts/demo/indextree.sql
  run_web_task invenio workflow init action_status,Action
  run_sql_file scripts/demo/defaultworkflow.sql
  run_sql_file scripts/demo/doi_identifier.sql
  run_sql_file postgresql/ddl/W-OA-user_activity_log.sql
  rebuild_asset_bundle
  run_web_task bash -lc "touch '${bootstrap_marker}'"
}
main() {
  local bootstrap_needed=1

  load_dotenv
  validate_env
  cleanup_python_artifacts

  if (( pull_images && no_cache )); then
    echo "[INFO] --no-cache is ignored when --pull-images is specified."
  fi

  if (( reset_env )); then
    "${compose[@]}" down -v --remove-orphans
  fi

  if (( pull_images )); then
    pull_prebuilt_images
  else
    build_images
  fi

  start_infra_services

  if (( ! force_bootstrap )) && bootstrap_marker_exists; then
    bootstrap_needed=0
  fi

  if (( bootstrap_needed )); then
    bootstrap_instance
  elif (( rebuild_assets )); then
    rebuild_asset_bundle
  fi

  start_app_services
}

main
