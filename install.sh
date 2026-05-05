#!/bin/bash

set -euo pipefail

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
image_bundle_dir=""
compose_project_name=""

default_compose_project_name() {
  local repo_name path_hash

  repo_name=$(basename "$(pwd)" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')
  path_hash=$(printf '%s' "$(pwd)" | sha256sum | cut -c1-8)
  printf '%s\n' "${repo_name}-${path_hash}"
}

detect_compose_command() {
  if [[ -z "$compose_project_name" ]]; then
    compose_project_name="${WEKO_DOCKER_PROJECT:-$(default_compose_project_name)}"
  fi

  if docker compose version >/dev/null 2>&1; then
    compose=(docker compose -p "${compose_project_name}" -f docker-compose2.yml)
  elif command -v docker-compose >/dev/null 2>&1; then
    compose=(docker-compose -p "${compose_project_name}" -f docker-compose2.yml)
  else
    echo "[ERROR] Neither 'docker compose' nor 'docker-compose' is available." >&2
    exit 1
  fi
}

show_usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --reset            Remove containers and named volumes before rebuilding.
  --down-with-volumes
                     Alias of --reset.
  --no-cache         Build images without Docker layer cache.
  --pull-images      Pull prebuilt images instead of building locally.
  --image-bundle DIR Load prebuilt image tarballs from DIR instead of building.
                     Cannot be combined with --pull-images.
  --rebuild-assets   Rebuild frontend assets even when bootstrap is skipped.
  --force-bootstrap  Re-run database/index bootstrap without removing volumes.
  -h, --help         Show this help.

Required:
  Create `.env` from `.env.example` and fill the required secrets/certificate paths.
  Optional: set WEKO_DOCKER_PROJECT in `.env` to pin the Docker Compose project name.
EOF
}

while (($#)); do
  case "$1" in
    --reset|--down-with-volumes)
      reset_env=1
      force_bootstrap=1
      rebuild_assets=1
      shift
      ;;
    --no-cache)
      no_cache=1
      shift
      ;;
    --pull-images)
      pull_images=1
      shift
      ;;
    --image-bundle)
      if (($# < 2)); then
        echo "[ERROR] --image-bundle requires a directory path." >&2
        exit 1
      fi
      image_bundle_dir=$2
      shift 2
      ;;
    --rebuild-assets)
      rebuild_assets=1
      shift
      ;;
    --force-bootstrap)
      force_bootstrap=1
      shift
      ;;
    -h|--help)
      show_usage
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown option: $1" >&2
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

set_default_ports() {
  WEKO_HTTP_PORT=${WEKO_HTTP_PORT:-18080}
  WEKO_HTTPS_PORT=${WEKO_HTTPS_PORT:-443}
  export WEKO_HTTP_PORT WEKO_HTTPS_PORT
}

cleanup_python_artifacts() {
  find . -type d \( -name __pycache__ -o -name .tox -o -name .eggs -o -name .pytest_cache \) -prune -exec rm -rf {} +
  find . -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete
}

run_web_task() {
  "${compose[@]}" run --rm --no-deps web bash /code/scripts/entrypoint_task.sh "$@"
}

validate_public_ports_available() {
  local nginx_container_id=""
  local nginx_running="false"
  local http_mapping=""
  local https_mapping=""

  nginx_container_id="$("${compose[@]}" ps -q nginx 2>/dev/null || true)"
  if [[ -n "$nginx_container_id" ]] && [[ "$(docker inspect -f '{{.State.Running}}' "$nginx_container_id" 2>/dev/null || true)" == "true" ]]; then
    nginx_running="true"
    http_mapping="$(docker port "$nginx_container_id" 80/tcp 2>/dev/null | head -n1 || true)"
    https_mapping="$(docker port "$nginx_container_id" 443/tcp 2>/dev/null | head -n1 || true)"
  fi

  if ss -ltnH "( sport = :${WEKO_HTTP_PORT} )" | grep -q .; then
    if [[ "$nginx_running" != "true" ]] || [[ ! "$http_mapping" =~ :${WEKO_HTTP_PORT}$ ]]; then
      echo "[ERROR] Host port ${WEKO_HTTP_PORT} is already in use. Leaving the existing service untouched and not starting WEKO app containers." >&2
      exit 1
    fi
  fi

  if ss -ltnH "( sport = :${WEKO_HTTPS_PORT} )" | grep -q .; then
    if [[ "$nginx_running" != "true" ]] || [[ ! "$https_mapping" =~ :${WEKO_HTTPS_PORT}$ ]]; then
      echo "[ERROR] Host port ${WEKO_HTTPS_PORT} is already in use. Leaving the existing service untouched and not starting WEKO app containers." >&2
      exit 1
    fi
  fi
}

normalize_arch() {
  local arch=$1

  case "$arch" in
    x86_64|amd64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    *)
      echo "$arch"
      ;;
  esac
}

load_image_bundle_metadata() {
  local metadata_file="${image_bundle_dir}/images.env"
  local required_vars=(
    WEKO_APP_IMAGE
    WEKO_ELASTICSEARCH_IMAGE
    WEKO_NGINX_IMAGE
    WEKO_IMAGE_BUNDLE_ARCH
    WEKO_IMAGE_BUNDLE_COMMIT
  )
  local missing=()
  local var

  if [[ ! -r "$metadata_file" ]]; then
    echo "[ERROR] Missing bundle metadata file: ${metadata_file}" >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1090
  source "$metadata_file"
  set +a

  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done

  if (( ${#missing[@]} )); then
    echo "[ERROR] Missing required variables in ${metadata_file}: ${missing[*]}" >&2
    exit 1
  fi
}

validate_image_bundle() {
  local required_files=(
    "${image_bundle_dir}/app.tar"
    "${image_bundle_dir}/elasticsearch.tar"
    "${image_bundle_dir}/nginx.tar"
    "${image_bundle_dir}/images.env"
  )
  local file
  local current_arch
  local current_commit

  if [[ -z "$image_bundle_dir" ]]; then
    echo "[ERROR] Internal error: image bundle directory is empty." >&2
    exit 1
  fi

  if [[ ! -d "$image_bundle_dir" ]]; then
    echo "[ERROR] Image bundle directory not found: ${image_bundle_dir}" >&2
    exit 1
  fi

  for file in "${required_files[@]}"; do
    if [[ ! -r "$file" ]]; then
      echo "[ERROR] Missing required bundle file: ${file}" >&2
      exit 1
    fi
  done

  load_image_bundle_metadata

  current_arch="$(normalize_arch "$(uname -m)")"
  if [[ "$current_arch" != "$WEKO_IMAGE_BUNDLE_ARCH" ]]; then
    echo "[ERROR] Image bundle architecture mismatch: bundle=${WEKO_IMAGE_BUNDLE_ARCH}, host=${current_arch}" >&2
    exit 1
  fi

  current_commit="$(git rev-parse HEAD)"
  if [[ "$current_commit" != "$WEKO_IMAGE_BUNDLE_COMMIT" ]]; then
    echo "[ERROR] Image bundle commit mismatch: bundle=${WEKO_IMAGE_BUNDLE_COMMIT}, checkout=${current_commit}" >&2
    exit 1
  fi
}

load_image_bundle() {
  local tarball
  local tarballs=(
    "${image_bundle_dir}/app.tar"
    "${image_bundle_dir}/elasticsearch.tar"
    "${image_bundle_dir}/nginx.tar"
  )

  for tarball in "${tarballs[@]}"; do
    docker load -i "$tarball"
  done
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
    "${compose[@]}" "${build_args[@]}" "${build_services[@]}"
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
  if [[ -z "$image_bundle_dir" ]] || (( rebuild_assets )); then
    rebuild_asset_bundle
  fi
  run_web_task bash -lc "touch '${bootstrap_marker}'"
}
main() {
  local bootstrap_needed=1

  load_dotenv
  set_default_ports
  compose_project_name="${WEKO_DOCKER_PROJECT:-$(default_compose_project_name)}"
  detect_compose_command
  validate_env
  cleanup_python_artifacts

  if [[ -n "$image_bundle_dir" ]] && (( pull_images )); then
    echo "[ERROR] --image-bundle cannot be combined with --pull-images." >&2
    exit 1
  fi

  if (( pull_images && no_cache )); then
    echo "[INFO] --no-cache is ignored when --pull-images is specified."
  fi

  if [[ -n "$image_bundle_dir" ]] && (( no_cache )); then
    echo "[INFO] --no-cache is ignored when --image-bundle is specified."
  fi

  if (( reset_env )); then
    "${compose[@]}" down -v --remove-orphans
  fi

  if [[ -n "$image_bundle_dir" ]]; then
    validate_image_bundle
    load_image_bundle
  elif (( pull_images )); then
    pull_prebuilt_images
  else
    build_images
  fi

  validate_public_ports_available

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
