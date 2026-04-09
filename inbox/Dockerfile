FROM python:3.12-slim-bookworm AS base

ENV PYTHONUNBUFFERED True
ENV APP_HOME /app
WORKDIR $APP_HOME

FROM base AS production

ARG INBOX_REF=nii_main

# Pin the Debian family and bypass the docker-clean hook that broke apt on
# newer slim variants.
RUN rm -f /etc/apt/apt.conf.d/docker-clean && \
    apt-get update -o Acquire::Retries=3 && \
    apt-get install -y --no-install-recommends git ca-certificates && \
    rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${INBOX_REF} https://github.com/RCOSDP/coar-notify-inbox.git $APP_HOME

RUN pip install --upgrade pip
RUN pip install --no-cache-dir -r requirements.txt --prefer-binary

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
