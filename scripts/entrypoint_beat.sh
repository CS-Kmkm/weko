#!/bin/bash

set -xeuo pipefail
/home/invenio/.virtualenvs/"${INVENIO_WEB_VENV:-invenio}"/bin/python \
    /code/scripts/render_instance_cfg.py \
    /code/scripts/instance.cfg \
    /home/invenio/.virtualenvs/invenio/var/instance/conf/invenio.cfg
/usr/bin/supervisord -c /code/scripts/supervisord_beat.conf
