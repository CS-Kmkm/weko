#!/usr/bin/env bash
#
# This file is part of WEKO3.
# Copyright (C) 2017 National Institute of Informatics.
#
# WEKO3 is free software; you can redistribute it
# and/or modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# WEKO3 is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with WEKO3; if not, write to the
# Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA 02111-1307, USA.

# check environment variables:
if [ "${INVENIO_WEB_HOST}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_WEB_HOST before runnning this script."
    echo "[ERROR] Example: export INVENIO_WEB_HOST=192.168.50.10"
    exit 1
fi
if [ "${INVENIO_WEB_INSTANCE}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_WEB_INSTANCE before runnning this script."
    echo "[ERROR] Example: export INVENIO_WEB_INSTANCE=invenio"
    exit 1
fi
if [ "${INVENIO_WEB_VENV}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_WEB_VENV before runnning this script."
    echo "[ERROR] Example: export INVENIO_WEB_VENV=invenio"
    exit 1
fi
if [ "${INVENIO_WEB_HOST_NAME}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_WEB_HOST_NAME before runnning this script."
    echo "[ERROR] Example: export INVENIO_WEB_HOST_NAME=invenio"
    exit 1
fi
if [ "${INVENIO_USER_EMAIL}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_USER_EMAIL before runnning this script."
    echo "[ERROR] Example: export INVENIO_USER_EMAIL=wekosoftware@nii.ac.jp"
    exit 1
fi
if [ "${INVENIO_USER_PASS}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_USER_PASS before runnning this script."
    echo "[ERROR] Example: export INVENIO_USER_PASS=uspass123"
    exit 1
fi
if [ "${INVENIO_POSTGRESQL_HOST}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_POSTGRESQL_HOST before runnning this script."
    echo "[ERROR] Example: export INVENIO_POSTGRESQL_HOST=192.168.50.11"
    exit 1
fi
if [ "${INVENIO_POSTGRESQL_DBNAME}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_POSTGRESQL_DBNAME before runnning this script."
    echo "[ERROR] Example: INVENIO_POSTGRESQL_DBNAME=invenio"
    exit 1
fi
if [ "${INVENIO_POSTGRESQL_DBUSER}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_POSTGRESQL_DBUSER before runnning this script."
    echo "[ERROR] Example: INVENIO_POSTGRESQL_DBUSER=invenio"
    exit 1
fi
if [ "${INVENIO_POSTGRESQL_DBPASS}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_POSTGRESQL_DBPASS before runnning this script."
    echo "[ERROR] Example: INVENIO_POSTGRESQL_DBPASS=dbpass123"
    exit 1
fi
if [ "${INVENIO_REDIS_HOST}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_REDIS_HOST before runnning this script."
    echo "[ERROR] Example: export INVENIO_REDIS_HOST=192.168.50.12"
    exit 1
fi
if [ "${INVENIO_ELASTICSEARCH_HOST}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_ELASTICSEARCH_HOST before runnning this script."
    echo "[ERROR] Example: export INVENIO_ELASTICSEARCH_HOST=192.168.50.13"
    exit 1
fi
if [ "${INVENIO_RABBITMQ_HOST}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_RABBITMQ_HOST before runnning this script."
    echo "[ERROR] Example: export INVENIO_RABBITMQ_HOST=192.168.50.14"
    exit 1
fi
if [ "${INVENIO_RABBITMQ_USER}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_RABBITMQ_USER before runnning this script."
    echo "[ERROR] Example: export INVENIO_RABBITMQ_USER=guest"
    exit 1
fi
if [ "${INVENIO_RABBITMQ_PASS}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_RABBITMQ_PASS before runnning this script."
    echo "[ERROR] Example: export INVENIO_RABBITMQ_PASS=guest"
    exit 1
fi
if [ "${INVENIO_RABBITMQ_VHOST}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_RABBITMQ_VHOST before runnning this script."
    echo "[ERROR] Example: export INVENIO_RABBITMQ_VHOST=/"
    exit 1
fi
if [ "${INVENIO_WORKER_HOST}" = "" ]; then
    echo "[ERROR] Please set environment variable INVENIO_WORKER_HOST before runnning this script."
    echo "[ERROR] Example: export INVENIO_WORKER_HOST=192.168.50.15"
    exit 1
fi
if [ "${SEARCH_INDEX_PREFIX}" = "" ]; then
    echo "[ERROR] Please set environment variable SEARCH_INDEX_PREFIX before runnning this script."
    echo "[ERROR] Example: export SEARCH_INDEX_PREFIX=tenant1"
    exit 1
fi

RESET_DATABASE=${RESET_DATABASE:-0}
REBUILD_INDEX=${REBUILD_INDEX:-0}

wait_for_tcp_service () {
    local host=$1
    local port=$2
    local label=$3
    local retries=${4:-60}
    local delay=${5:-2}
    local attempt

    for attempt in $(seq 1 "${retries}"); do
        if (echo >"/dev/tcp/${host}/${port}") >/dev/null 2>&1; then
            return 0
        fi
        sleep "${delay}"
    done

    echo "[ERROR] Timed out waiting for ${label} (${host}:${port})."
    exit 1
}

wait_for_http_service () {
    local url=$1
    local label=$2
    local retries=${3:-60}
    local delay=${4:-2}
    local attempt

    for attempt in $(seq 1 "${retries}"); do
        if curl --silent --fail "${url}" >/dev/null 2>&1; then
            return 0
        fi
        sleep "${delay}"
    done

    echo "[ERROR] Timed out waiting for ${label} (${url})."
    exit 1
}

# load virtualenvrapper:
# shellcheck source=/dev/null
if ! "${VIRTUALENVWRAPPER_PYTHON:-python}" -c "import virtualenvwrapper.hook_loader" >/dev/null 2>&1; then
    export VIRTUALENVWRAPPER_PYTHON="$(command -v python)"
fi
source "$(which virtualenvwrapper.sh)"

# switch virtual environment:
workon "${INVENIO_WEB_VENV}"

run_invenio () {
    "${HOME}/.virtualenvs/${INVENIO_WEB_VENV}/bin/${INVENIO_WEB_INSTANCE}" "$@"
}

# quit on errors and unbound symbols:
set -o errexit
# set -o nounset

wait_for_tcp_service "${INVENIO_POSTGRESQL_HOST}" 5432 "PostgreSQL"
wait_for_tcp_service "${INVENIO_REDIS_HOST}" 6379 "Redis"
wait_for_tcp_service "${INVENIO_RABBITMQ_HOST}" 5672 "RabbitMQ"
wait_for_tcp_service "${INVENIO_ELASTICSEARCH_HOST}" 9200 "Elasticsearch"
wait_for_http_service "http://${INVENIO_ELASTICSEARCH_HOST}:9200" "Elasticsearch HTTP endpoint"

# sphinxdoc-create-database-begin
if [ "${RESET_DATABASE}" = "1" ]; then
    run_invenio db drop --yes-i-know
fi
run_invenio db init
run_invenio db create -v
run_invenio stats partition create $(date +%Y)
run_invenio stats partition create $(date -d 'year' +%Y)
run_invenio logging partition create $(date +%Y)
run_invenio logging partition create $(date -d 'year' +%Y)
# sphinxdoc-create-database-end

# sphinxdoc-index-initialisation-begin
if [ "${REBUILD_INDEX}" = "1" ]; then
    run_invenio index destroy --force --yes-i-know || true
    run_invenio index delete '*' --force --yes-i-know || true
fi
run_invenio index init
wait_for_http_service \
    "http://${INVENIO_ELASTICSEARCH_HOST}:9200/_cluster/health?wait_for_status=yellow&timeout=30s" \
    "Elasticsearch cluster health"
run_invenio index queue init
# sphinxdoc-index-initialisation-end

# elasticsearch-ilm-setting-begin
curl -XPUT 'http://'${INVENIO_ELASTICSEARCH_HOST}':9200/_ilm/policy/weko_stats_policy' -H 'Content-Type: application/json' -d '
{
  "policy":{
    "phases":{
      "hot":{
        "actions":{
          "rollover":{
            "max_size":"50gb"
          }
        }
      }
    }
  }
}'
event_list=('celery-task' 'item-create' 'top-view' 'record-view' 'file-download' 'file-preview' 'search')
for event_name in ${event_list[@]}
do
  curl -XPUT 'http://'${INVENIO_ELASTICSEARCH_HOST}':9200/'${SEARCH_INDEX_PREFIX}'-events-stats-'${event_name}'-000001?timeout=2m' -H 'Content-Type: application/json' -d '
  {
    "aliases": {
      "'${SEARCH_INDEX_PREFIX}'-events-stats-'${event_name}'": {
        "is_write_index": true
      }
    }
  }'
  curl -XPUT 'http://'${INVENIO_ELASTICSEARCH_HOST}':9200/'${SEARCH_INDEX_PREFIX}'-stats-'${event_name}'-000001?timeout=2m' -H 'Content-Type: application/json' -d '
  {
    "aliases": {
      "'${SEARCH_INDEX_PREFIX}'-stats-'${event_name}'": {
        "is_write_index": true
      }
    }
  }'
done
# elasticsearch-ilm-setting-end

# sphinxdoc-populate-with-demo-records-begin
#${INVENIO_WEB_INSTANCE} demo init
# sphinxdoc-populate-with-demo-records-end

# sphinxdoc-create-files-location-begin
run_invenio files location \
       "${INVENIO_FILES_LOCATION_NAME}" \
       "${INVENIO_FILES_LOCATION_URI}" \
       --default
# sphinxdoc-create-files-location-end

# sphinxdoc-create-user-account-begin
run_invenio users create \
       "${INVENIO_USER_EMAIL}" \
       --password "${INVENIO_USER_PASS}" \
       --active
# sphinxdoc-create-user-account-end

# sphinxdoc-create-roles-begin
run_invenio roles create "${INVENIO_ROLE_SYSTEM}"
run_invenio roles create "${INVENIO_ROLE_REPOSITORY}"
run_invenio roles create "${INVENIO_ROLE_CONTRIBUTOR}"
run_invenio roles create "${INVENIO_ROLE_COMMUNITY}"
# sphinxdoc-create-roles-end

# sphinxdoc-set-user-role-begin
run_invenio roles add \
       "${INVENIO_USER_EMAIL}" \
       "${INVENIO_ROLE_SYSTEM}"
# sphinxdoc-set-user-role-end

# sphinxdoc-set-role-access-begin
run_invenio access \
       allow "superuser-access" \
       role "${INVENIO_ROLE_SYSTEM}"

run_invenio access \
       allow "admin-access" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}"

run_invenio access \
       allow "schema-access" \
       role "${INVENIO_ROLE_REPOSITORY}"

run_invenio access \
       allow "index-tree-access" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}"

run_invenio access \
       allow "indextree-journal-access" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}"

run_invenio access \
       allow "item-type-access" \
       role "${INVENIO_ROLE_REPOSITORY}"

run_invenio access \
       allow "item-access" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}" \
       role "${INVENIO_ROLE_CONTRIBUTOR}"

run_invenio access \
       allow "files-rest-bucket-update" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}" \
       role "${INVENIO_ROLE_CONTRIBUTOR}"

run_invenio access \
       allow "files-rest-object-delete" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}" \
       role "${INVENIO_ROLE_CONTRIBUTOR}"

run_invenio access \
       allow "files-rest-object-delete-version" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}" \
       role "${INVENIO_ROLE_CONTRIBUTOR}"

run_invenio access \
       allow "files-rest-object-read" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}" \
       role "${INVENIO_ROLE_CONTRIBUTOR}"

run_invenio access \
       allow "files-rest-object-read-version" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}" \
       role "${INVENIO_ROLE_CONTRIBUTOR}"

run_invenio access \
       allow "search-access" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}" \
       role "${INVENIO_ROLE_CONTRIBUTOR}"

run_invenio access \
       allow "detail-page-access" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}" \
       role "${INVENIO_ROLE_CONTRIBUTOR}"

run_invenio access \
       allow "download-original-pdf-access" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}" \
       role "${INVENIO_ROLE_CONTRIBUTOR}"

run_invenio access \
       allow "author-access" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}" \
       role "${INVENIO_ROLE_CONTRIBUTOR}"

run_invenio access \
       allow "items-autofill" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}" \
       role "${INVENIO_ROLE_CONTRIBUTOR}"

run_invenio access \
       allow "stats-api-access" \
       role "${INVENIO_ROLE_REPOSITORY}" \
       role "${INVENIO_ROLE_COMMUNITY}"

run_invenio access \
       allow "read-style-action" \
       role "${INVENIO_ROLE_REPOSITORY}"

run_invenio access \
       allow "update-style-action" \
       role "${INVENIO_ROLE_REPOSITORY}"

# sphinxdoc-set-role-access-end

#### sphinxdoc-create-language-data-begin
run_invenio language create \
        --active --registered "en" "English" 001

run_invenio language create \
        --active "zh-cn" "中文 (簡体)" 000

run_invenio language create \
        --active "zh-tw" "中文 (繁体)" 000

run_invenio language create \
        --active "id" "Indonesia" 000

run_invenio language create \
        --active "vi" "Tiếng Việt" 000

run_invenio language create \
         --active "ms" "Bahasa Melayu" 000

run_invenio language create \
         --active "fil" "Filipino (Pilipinas)" 000

run_invenio language create \
         --active "th" "ไทย" 000

run_invenio language create \
         --active "hi" "हिन्दी" 000

run_invenio language create \
         --active --registered "ja" "日本語" 002
#### sphinxdoc-create-language-data-end

##### sphinxdoc-create-test-data-begin
run_invenio users create \
       "repoadmin@example.org" \
       --password "${INVENIO_USER_PASS}" \
       --active

run_invenio roles add \
       "repoadmin@example.org" \
       "${INVENIO_ROLE_REPOSITORY}"

run_invenio users create \
       "contributor@example.org" \
       --password "${INVENIO_USER_PASS}" \
       --active

run_invenio roles add \
        "contributor@example.org" \
       "${INVENIO_ROLE_CONTRIBUTOR}"

run_invenio users create \
       "user@example.org" \
       --password "${INVENIO_USER_PASS}" \
       --active

run_invenio users create \
      "comadmin@example.org" \
      --password "${INVENIO_USER_PASS}" \
      --active

run_invenio roles add \
        "comadmin@example.org" \
       "${INVENIO_ROLE_COMMUNITY}"

##### sphinxdoc-create-test-data-end

# sphinxdoc-set-web-api-account-combobox-begin
run_invenio cert insert crf CrossRef
run_invenio cert insert oaa "OAアシスト"
# sphinxdoc-set-web-api-account-combobox-end

#### sphinxdoc-create-widget_type-data-begin
run_invenio widget_type create \
        "Free description" "Free description"

run_invenio widget_type create \
        "Access counter" "Access counter"

run_invenio widget_type create \
        "Notice" "Notice"

run_invenio widget_type create \
        "New arrivals" "New arrivals"

run_invenio widget_type create \
        "Main contents" "Main contents"

run_invenio widget_type create \
        "Menu" "Menu"
run_invenio widget_type create \
        "Header" "Header"
run_invenio widget_type create \
        "Footer" "Footer"
### sphinxdoc-create-widget_type-data-end

# sphinxdoc-set-report-unit-and-target-begin
run_invenio report create_unit \
       "1" "Day"
run_invenio report create_unit \
       "2" "Week"
run_invenio report create_unit \
       "3" "Year"
run_invenio report create_unit \
       "4" "Item"
run_invenio report create_unit \
       "5" "Host"
run_invenio report create_target \
       "1" "Item registration report" "1,2,3,5"
run_invenio report create_target \
       "2" "Item detail view report" "1,2,3,4,5"
run_invenio report create_target \
       "3" "Contents download report" "1,2,3,4,5"
# sphinxdoc-set-report-unit-and-target-end

run_invenio billing create \
       --active 1

# create-admin-settings-begin
run_invenio admin_settings create_settings \
       1 "items_display_settings" \
       "{'items_search_author': 'name', 'items_display_email': True}"
run_invenio admin_settings create_settings \
       2 "storage_check_settings" \
       "{'threshold_rate': 80, 'cycle': 'weekly', 'day': 0}"
run_invenio admin_settings create_settings \
       3 "site_license_mail_settings" \
       "{'Root Index': {'auto_send_flag': False}}"
run_invenio admin_settings create_settings \
       4 "default_properties_settings" \
       "{'show_flag': True}"
run_invenio admin_settings create_settings \
       5 "elastic_reindex_settings" \
       "{'has_errored': False}"
run_invenio admin_settings create_settings \
       6 "blocked_user_settings" \
       "{'blocked_ePPNs': []}"
run_invenio admin_settings create_settings \
       7 "shib_login_enable" \
       "{'shib_flg': False}"
run_invenio admin_settings create_settings \
       8 "default_role_settings" \
       "{'gakunin_role': '', 'orthros_outside_role': '', 'extra_role': ''}"
run_invenio admin_settings create_settings \
       9 "attribute_mapping" \
       "{'shib_eppn': '', 'shib_role_authority_name': '', 'shib_mail': '', 'shib_user_name': ''}"
# create-admin-settings-end

# create-default-authors-prefix-settings-begin
run_invenio authors_prefix default_settings \
       "WEKO" "WEKO" ""
run_invenio authors_prefix default_settings \
       "ORCID" "ORCID" "https://orcid.org/##"
run_invenio authors_prefix default_settings \
       "CiNii" "CiNii" "https://ci.nii.ac.jp/author/##"
run_invenio authors_prefix default_settings \
       "KAKEN2" "KAKEN2" "https://nrid.nii.ac.jp/nrid/##"
run_invenio authors_prefix default_settings \
       "ROR" "ROR" "https://ror.org/##"
run_invenio authors_prefix default_settings \
       "e-Rad_Researcher" "e-Rad_Researcher" ""
run_invenio authors_prefix default_settings \
       "NRID" "NRID【非推奨】" "https://nrid.nii.ac.jp/nrid/##"
run_invenio authors_prefix default_settings \
       "ISNI" "ISNI" "http://www.isni.org/isni/##"
run_invenio authors_prefix default_settings \
       "VIAF" "VIAF" "https://viaf.org/viaf/##"
run_invenio authors_prefix default_settings \
       "AID" "AID" ""
run_invenio authors_prefix default_settings \
       "kakenhi" "kakenhi【非推奨】" ""
run_invenio authors_prefix default_settings \
       "Ringgold" "Ringgold" ""
run_invenio authors_prefix default_settings \
       "GRID" "GRID【非推奨】" "" 
run_invenio authors_prefix default_settings \
       "researchmap" "researchmap" "https://researchmap.jp/##"
# create-default-authors-prefix-settings-end

# create-default-authors-affiliation-settings-begin
run_invenio authors_affiliation default_settings \
       "ISNI" "ISNI" "http://www.isni.org/isni/##"
run_invenio authors_affiliation default_settings \
       "GRID" "GRID" "https://www.grid.ac/institutes/##"
run_invenio authors_affiliation default_settings \
       "Ringgold" "Ringgold" ""
run_invenio authors_affiliation default_settings \
       "kakenhi" "kakenhi" ""
run_invenio authors_affiliation default_settings \
       "ROR" "ROR" "https://ror.org/##"
# create-default-authors-affiliation-settings-end

# create-widget-bucket-begin
run_invenio widget init
# create-widget-bucket-end

# create-facet-search-setting-begin
run_invenio facet_search_setting create \
       "Data Language"	"デ一タの言語"	"language"	"[]"	True   SelectBox     1      True    OR
run_invenio facet_search_setting create \
       "Access"	"アクセス制限"	"accessRights"	"[]"	True   SelectBox     2      True    OR
run_invenio facet_search_setting create \
       "Location"	"地域"	"geoLocation.geoLocationPlace"	"[]"	True   SelectBox     3      True    OR
run_invenio facet_search_setting create \
       "Temporal"	"時間的範囲"	"temporal"	"[]"	True   SelectBox     4      True    OR
run_invenio facet_search_setting create \
       "Topic"	"トピック"	"subject.value"	"[]"	True   SelectBox     5      True    OR
run_invenio facet_search_setting create \
       "Distributor"	"配布者"	"contributor.contributorName"	"[{'agg_value': 'Distributor', 'agg_mapping': 'contributor.@attributes.contributorType'}]"	True   SelectBox     6      True    OR
run_invenio facet_search_setting create \
       "Data Type"	"デ一タタイプ"	"description.value"	"[{'agg_value': 'Other', 'agg_mapping': 'description.descriptionType'}]"	True   SelectBox     7      True    OR
# create-facet-search-setting-end
