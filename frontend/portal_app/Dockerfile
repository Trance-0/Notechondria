# Build context must be the parent frontend/ directory so the
# ../notechondria_shared path dependency resolves inside the image:
#   docker build -f portal_app/Dockerfile frontend/
FROM ghcr.io/cirruslabs/flutter:stable AS frontend_base

ARG FRONTEND_UID=1000
ARG FRONTEND_GID=1000

WORKDIR /app

RUN mkdir -p /home/frontend /app /notechondria_shared     && chown -R ${FRONTEND_UID}:${FRONTEND_GID} /home/frontend /app /notechondria_shared /sdks/flutter

USER ${FRONTEND_UID}:${FRONTEND_GID}

ENV HOME=/home/frontend
RUN git config --global --add safe.directory /sdks/flutter     && flutter config --enable-web

COPY --chown=${FRONTEND_UID}:${FRONTEND_GID} notechondria_shared/ /notechondria_shared/
COPY --chown=${FRONTEND_UID}:${FRONTEND_GID} portal_app/pubspec.yaml portal_app/pubspec.lock ./
RUN flutter pub get

COPY --chown=${FRONTEND_UID}:${FRONTEND_GID} portal_app/ .

FROM frontend_base AS frontend_test
RUN flutter test test/smoke_test.dart


FROM frontend_base AS frontend_build
ARG FRONTEND_API_BASE_URL=http://localhost:9060/api/v1
ARG APP_BASE_HREF=/
# Pass --build-arg APP_VERSION="$(cat VERSION)". Without it the Dart default
# (0.1.21 in lib/core/helpers.dart) ships and the version banner misfires;
# an empty value is never passed as a define.
ARG APP_VERSION=
RUN set -e; version_define=''; \
    if [ -n "${APP_VERSION}" ]; then version_define="--dart-define=APP_VERSION=${APP_VERSION}"; \
    else echo "Version banner and What's New will report the Dart default version: portal_app Docker build / APP_VERSION define — APP_VERSION build arg is empty or missing (pass --build-arg APP_VERSION from the repo-root VERSION file)." >&2; fi; \
    flutter build web --release --no-web-resources-cdn --no-tree-shake-icons --base-href ${APP_BASE_HREF} --dart-define=API_BASE_URL=${FRONTEND_API_BASE_URL} ${version_define}

FROM nginx:1.27-alpine AS frontend_runtime
ENV FRONTEND_BACKEND_ORIGIN=http://nginx
RUN rm /etc/nginx/conf.d/default.conf
COPY portal_app/nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=frontend_build /app/build/web /usr/share/nginx/html
EXPOSE 80
