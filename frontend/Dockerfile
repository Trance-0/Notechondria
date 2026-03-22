FROM ghcr.io/cirruslabs/flutter:stable AS frontend_base

ARG FRONTEND_UID=1000
ARG FRONTEND_GID=1000
RUN mkdir -p /app /home/frontend \
    && chown -R ${FRONTEND_UID}:${FRONTEND_GID} /app /home/frontend

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN chown -R ${FRONTEND_UID}:${FRONTEND_GID} /app
USER ${FRONTEND_UID}:${FRONTEND_GID}
ENV HOME=/home/frontend
RUN git config --global --add safe.directory /sdks/flutter \
    && flutter config --enable-web \
    && flutter pub get

USER root
COPY . .
RUN chown -R ${FRONTEND_UID}:${FRONTEND_GID} /app
USER ${FRONTEND_UID}:${FRONTEND_GID}

FROM frontend_base AS frontend_test

RUN flutter test

FROM frontend_base AS frontend_build

ARG API_BASE_URL=http://localhost:9080/api/v1
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

FROM nginx:1.27-alpine AS frontend_runtime

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=frontend_build /app/build/web /usr/share/nginx/html

EXPOSE 80
