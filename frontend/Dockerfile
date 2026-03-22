FROM ghcr.io/cirruslabs/flutter:stable AS frontend_base

WORKDIR /app

ENV HOME=/root
RUN git config --global --add safe.directory /sdks/flutter \
    && flutter config --enable-web

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

FROM frontend_base AS frontend_test

RUN flutter test

FROM frontend_base AS frontend_build

ARG API_BASE_URL=/api/v1
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

FROM nginx:1.27-alpine AS frontend_runtime

ENV FRONTEND_BACKEND_ORIGIN=http://host.docker.internal:9080

RUN rm /etc/nginx/conf.d/default.conf
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=frontend_build /app/build/web /usr/share/nginx/html

EXPOSE 80
