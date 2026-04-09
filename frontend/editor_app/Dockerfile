FROM ghcr.io/cirruslabs/flutter:stable AS frontend_base

ARG FRONTEND_UID=1000
ARG FRONTEND_GID=1000

WORKDIR /app

RUN mkdir -p /home/frontend /app     && chown -R ${FRONTEND_UID}:${FRONTEND_GID} /home/frontend /app /sdks/flutter

USER ${FRONTEND_UID}:${FRONTEND_GID}

ENV HOME=/home/frontend
RUN git config --global --add safe.directory /sdks/flutter     && flutter config --enable-web

COPY --chown=${FRONTEND_UID}:${FRONTEND_GID} pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY --chown=${FRONTEND_UID}:${FRONTEND_GID} . .

FROM frontend_base AS frontend_test
RUN flutter test test/smoke_test.dart

FROM frontend_base AS frontend_build
ARG FRONTEND_API_BASE_URL=http://localhost:9060/api/v1
ARG APP_BASE_HREF=/
RUN flutter build web --release --web-renderer html --no-tree-shake-icons --base-href ${APP_BASE_HREF} --dart-define=API_BASE_URL=${FRONTEND_API_BASE_URL}

FROM nginx:1.27-alpine AS frontend_runtime
ENV FRONTEND_BACKEND_ORIGIN=http://nginx
RUN rm /etc/nginx/conf.d/default.conf
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=frontend_build /app/build/web /usr/share/nginx/html
EXPOSE 80
