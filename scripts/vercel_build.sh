#!/usr/bin/env bash
# Builds the existing Flutter web app for Vercel. Does not touch Android or iOS.
set -euo pipefail

FLUTTER_VERSION="3.44.0"
FLUTTER_HOME="${HOME}/flutter"

if ! command -v flutter >/dev/null 2>&1; then
  git clone https://github.com/flutter/flutter.git \
    --depth 1 \
    --branch "${FLUTTER_VERSION}" \
    "${FLUTTER_HOME}"
  git config --global --add safe.directory "${FLUTTER_HOME}"
  export PATH="${FLUTTER_HOME}/bin:${PATH}"
fi

flutter config --enable-web --no-analytics
flutter precache --web
flutter pub get

defines=()
if [ -n "${API_BASE_URL:-}" ]; then
  defines+=(--dart-define="API_BASE_URL=${API_BASE_URL}")
fi
if [ -n "${AUTH_PROVIDER:-}" ]; then
  defines+=(--dart-define="AUTH_PROVIDER=${AUTH_PROVIDER}")
fi

flutter build web --release "${defines[@]}"
