FROM ghcr.io/cirruslabs/flutter:stable AS frontend_base

ARG FRONTEND_UID=1000
ARG FRONTEND_GID=1000
RUN groupadd --gid ${FRONTEND_GID} frontend \
    && useradd --uid ${FRONTEND_UID} --gid ${FRONTEND_GID} --create-home --shell /bin/bash frontend

WORKDIR /app

COPY --chown=frontend:frontend pubspec.yaml pubspec.lock ./
USER frontend
ENV HOME=/home/frontend
RUN flutter config --enable-web && flutter pub get

COPY --chown=frontend:frontend . .

FROM frontend_base AS frontend_test

RUN flutter test

FROM frontend_base AS frontend_build

ARG API_BASE_URL=http://localhost:9080/api/v1
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

FROM nginx:1.27-alpine AS frontend_runtime

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=frontend_build /app/build/web /usr/share/nginx/html

EXPOSE 80
