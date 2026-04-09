FROM python:3.12-slim AS base

ENV PYTHONUNBUFFERED True
ENV APP_HOME /app
WORKDIR $APP_HOME

FROM base AS production

ARG INBOX_REPOSITORY=RCOSDP/coar-notify-inbox
ARG INBOX_REF=nii_main

RUN python - "$INBOX_REPOSITORY" "$INBOX_REF" "$APP_HOME" <<'PY'
import io
import os
import shutil
import sys
import tarfile
import urllib.request

repo, ref, app_home = sys.argv[1:]
url = f"https://github.com/{repo}/archive/refs/heads/{ref}.tar.gz"

with urllib.request.urlopen(url) as response:
    archive = io.BytesIO(response.read())

with tarfile.open(fileobj=archive, mode="r:gz") as tar:
    root_dir = tar.getmembers()[0].name.split("/", 1)[0]
    tar.extractall("/tmp")

source_dir = os.path.join("/tmp", root_dir)

for entry in os.listdir(source_dir):
    shutil.move(os.path.join(source_dir, entry), os.path.join(app_home, entry))

shutil.rmtree(source_dir)
PY

RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt --prefer-binary

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
