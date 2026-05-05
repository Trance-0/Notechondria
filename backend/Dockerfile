# pull official base image
# Python 3.11.4 matches `.python-version` and `runtime.txt` so the
# Northflank Docker deploy and the Render free-tier deploy both
# resolve the same wheel set. Bumped from 3.9.18 in 0.1.115:
# casdoor>=1.41 (added in 0.1.96) requires requests~=2.33.0, and
# requests 2.33+ requires Python>=3.10 — pip's resolver on 3.9
# rejected the requirement with "No matching distribution found".
FROM python:3.11.4-bullseye AS builder

# configurations
ENV HOME=/home
ENV APP_HOME=/home/notechondria
ENV DJANGO_PRODUCTION_MEDIA_ROOT=/home/mediafiles
ENV DJANGO_PRODUCTION_STATIC_ROOT=/home/staticfiles
RUN mkdir ${APP_HOME}

RUN apt-get update \
    && apt-get install -y --no-install-recommends netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# install dependencies
WORKDIR $HOME 
RUN pip install --upgrade pip
COPY backend/requirements.txt .
RUN pip3 install -r requirements.txt --no-cache-dir

# copy files
WORKDIR ${APP_HOME}
COPY backend/ .
COPY sample/ /home/sample/
# Ship VERSION into the image so /api/v1/handshake/ can return the
# deployed build. _read_backend_version() in notechondria.api_views
# walks several candidate paths; /home/VERSION is the canonical
# Docker location. The same file's mtime doubles as the
# build_time fallback when no BUILD_TIME file is present.
COPY VERSION /home/VERSION

# Bake commit + build time into the image so /api/v1/handshake/'s
# `build` block stays accurate without runtime env vars. Both ARGs
# are optional — when omitted, the handshake falls back to the file
# mtime (build_time) or "" (commit). CI / Northflank build pipelines
# should set them via `docker build --build-arg`:
#
#   docker build --build-arg GIT_COMMIT=$(git rev-parse HEAD) \
#                --build-arg BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
#                ...
#
# Northflank exposes `NORTHFLANK_GIT_COMMIT` to build steps; map it
# into GIT_COMMIT in the service's build configuration.
ARG GIT_COMMIT=""
ARG BUILD_TIME=""
RUN sh -c 'echo "${GIT_COMMIT}" > /home/BUILD_COMMIT && \
           if [ -n "${BUILD_TIME}" ]; then \
             echo "${BUILD_TIME}" > /home/BUILD_TIME; \
           else \
             date -u +%Y-%m-%dT%H:%M:%SZ > /home/BUILD_TIME; \
           fi'
# bootstrap_platform seeds a starter note from this file's content.
# Project-local rules now live in docs/index.md (the repo-root
# AGENTS.md pointer file was removed; shared cross-project rules come
# from the AGENTS.md/ submodule). Copy docs/index.md to /home/AGENTS.md
# so resolve_codex_path in bootstrap_platform finds it at the same
# container path as before.
COPY docs/index.md /home/AGENTS.md

# add entrypoint to root
ADD backend/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh 

# create the appropriate directories for static and media file (nginx)
# nginx only process medias and should not be exposed.
RUN mkdir $HOME/staticfiles
RUN mkdir $HOME/mediafiles

# make log directory
RUN mkdir -p ${APP_HOME}/logs

EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
