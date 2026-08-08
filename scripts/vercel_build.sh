#!/usr/bin/env bash
#
# Builds the web app on Vercel.
#
# Vercel has no Flutter runtime, so the SDK is fetched here. It lands in the
# build cache, which Vercel restores between deploys — the first build pays
# a few minutes for the download, every one after it does not.
#
# The version is pinned rather than tracking stable. A Flutter release that
# changes analyzer or codegen behaviour must break a local build first, where
# there is someone to read the error, not a deploy nobody is watching.
set -euo pipefail

FLUTTER_VERSION=3.44.9

CACHE_DIR="${VERCEL_BUILD_CACHE_DIR:-.vercel/cache}"
FLUTTER_DIR="$CACHE_DIR/flutter-$FLUTTER_VERSION"

if [ ! -x "$FLUTTER_DIR/bin/flutter" ]; then
  echo "==> Fetching Flutter $FLUTTER_VERSION"
  rm -rf "$FLUTTER_DIR"
  mkdir -p "$FLUTTER_DIR"

  url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
  if curl -fsSL "$url" | tar -xJ -C "$FLUTTER_DIR" --strip-components=1; then
    echo "==> Unpacked the release archive"
  else
    # Falls back to a shallow clone when the image has no xz. Slower, but git
    # is the one tool a build image always has.
    echo "==> Archive unavailable, cloning the tag instead"
    rm -rf "$FLUTTER_DIR"
    git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$FLUTTER_DIR"
  fi
else
  echo "==> Flutter $FLUTTER_VERSION restored from the build cache"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

# The SDK sits outside the repo and is owned by whoever the build runs as;
# without this git refuses to read it and every flutter command fails.
git config --global --add safe.directory "$FLUTTER_DIR" || true

flutter --version
flutter pub get
flutter build web --release
