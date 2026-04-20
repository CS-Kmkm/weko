#!/bin/bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "${script_dir}/.." && pwd)

detect_compose_command() {
  if docker compose version >/dev/null 2>&1; then
    compose=(docker compose -f docker-compose2.yml)
  elif command -v docker-compose >/dev/null 2>&1; then
    compose=(docker-compose -f docker-compose2.yml)
  else
    echo "[ERROR] Neither 'docker compose' nor 'docker-compose' is available." >&2
    exit 1
  fi
}

normalize_arch() {
  case "$1" in
    x86_64|amd64)
      echo "amd64"
      ;;
    aarch64|arm64)
      echo "arm64"
      ;;
    *)
      echo "$1"
      ;;
  esac
}

load_dotenv() {
  if [[ ! -f "${repo_root}/.env" ]]; then
    echo "[ERROR] Missing ${repo_root}/.env. Copy .env.example to .env before packaging images." >&2
    exit 1
  fi

  set -a
  # shellcheck disable=SC1091
  source "${repo_root}/.env"
  set +a
}

main() {
  local arch
  local commit_sha
  local short_sha
  local output_dir
  local app_tag
  local elasticsearch_tag
  local nginx_tag

  cd "${repo_root}"

  detect_compose_command
  load_dotenv

  arch="$(normalize_arch "$(uname -m)")"
  if [[ "${arch}" != "amd64" ]]; then
    echo "[ERROR] This packaging workflow currently supports amd64 only. Detected: ${arch}" >&2
    exit 1
  fi

  commit_sha="$(git rev-parse HEAD)"
  short_sha="$(git rev-parse --short=12 HEAD)"
  output_dir="${repo_root}/dist/prebuilt-images/${short_sha}"

  app_tag="weko3-app:bundle-${short_sha}"
  elasticsearch_tag="weko3-elasticsearch:bundle-${short_sha}"
  nginx_tag="weko3-nginx:bundle-${short_sha}"

  mkdir -p "${output_dir}"

  env DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 \
    "${compose[@]}" build --force-rm web elasticsearch nginx

  docker tag weko3-app:local "${app_tag}"
  docker tag weko3-elasticsearch:local "${elasticsearch_tag}"
  docker tag weko3-nginx:local "${nginx_tag}"

  docker save -o "${output_dir}/app.tar" "${app_tag}"
  docker save -o "${output_dir}/elasticsearch.tar" "${elasticsearch_tag}"
  docker save -o "${output_dir}/nginx.tar" "${nginx_tag}"

  cat > "${output_dir}/images.env" <<EOF
WEKO_APP_IMAGE=${app_tag}
WEKO_ELASTICSEARCH_IMAGE=${elasticsearch_tag}
WEKO_NGINX_IMAGE=${nginx_tag}
WEKO_IMAGE_BUNDLE_ARCH=${arch}
WEKO_IMAGE_BUNDLE_COMMIT=${commit_sha}
EOF

  (
    cd "${output_dir}"
    sha256sum app.tar elasticsearch.tar nginx.tar images.env > SHA256SUMS
  )

  echo "[INFO] Image bundle created at ${output_dir}"
}

main "$@"
