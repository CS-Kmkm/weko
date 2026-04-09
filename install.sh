#!/bin/bash

set -xe

if docker compose version >/dev/null 2>&1; then
  DOCKER_COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE=(docker-compose)
else
  echo "docker compose plugin or docker-compose is required." >&2
  exit 1
fi

compose() {
  "${DOCKER_COMPOSE[@]}" -f docker-compose2.yml "$@"
}

find . | grep -E "(__pycache__|\.tox|\.eggs|\.pyc|\.pyo$)" | xargs rm -rf
compose down -v
DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1 compose build --no-cache --force-rm

# Initialize resources
compose run --rm web ./scripts/populate-instance.sh
docker cp scripts/demo/item_type.sql $(compose ps -q postgresql):/tmp/item_type.sql
compose exec postgresql psql -U invenio -d invenio -f /tmp/item_type.sql
docker cp scripts/demo/indextree.sql $(compose ps -q postgresql):/tmp/indextree.sql
compose exec postgresql psql -U invenio -d invenio -f /tmp/indextree.sql
compose run --rm web invenio workflow init action_status,Action
docker cp scripts/demo/defaultworkflow.sql $(compose ps -q postgresql):/tmp/defaultworkflow.sql
compose exec postgresql psql -U invenio -d invenio -f /tmp/defaultworkflow.sql
docker cp scripts/demo/doi_identifier.sql $(compose ps -q postgresql):/tmp/doi_identifier.sql
compose exec postgresql psql -U invenio -d invenio -f /tmp/doi_identifier.sql
docker cp postgresql/ddl/W-OA-user_activity_log.sql $(compose ps -q postgresql):/tmp/W-OA-user_activity_log.sql
compose exec postgresql psql -U invenio -d invenio -f /tmp/W-OA-user_activity_log.sql
# docker cp scripts/demo/resticted_access.sql $(compose ps -q postgresql):/tmp/resticted_access.sql
# compose exec postgresql psql -U invenio -d invenio -f /tmp/resticted_access.sql

compose run --rm web invenio assets build
compose run --rm web invenio collect -v

# Start services
compose up -d
