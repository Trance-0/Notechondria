# pull official base image
FROM python:3.9.18-bullseye AS builder

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
