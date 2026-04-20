#!/bin/bash

set -euo pipefail

/home/invenio/.virtualenvs/"${INVENIO_WEB_VENV:-invenio}"/bin/python \
    /code/scripts/render_instance_cfg.py \
    /code/scripts/instance.cfg \
    /home/invenio/.virtualenvs/invenio/var/instance/conf/invenio.cfg
exec "$@"
