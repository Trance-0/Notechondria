FROM ghcr.io/cirruslabs/flutter:stable AS frontend_base

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter config --enable-web && flutter pub get

COPY . .

FROM frontend_base AS frontend_test

RUN flutter test

FROM frontend_base AS frontend_build

ARG API_BASE_URL=http://localhost:9080/api/v1
RUN flutter build web --release --dart-define=API_BASE_URL=${API_BASE_URL}

FROM nginx:1.27-alpine AS frontend_runtime

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=frontend_build /app/build/web /usr/share/nginx/html

EXPOSE 80
