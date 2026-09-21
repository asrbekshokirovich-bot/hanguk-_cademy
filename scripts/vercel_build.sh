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

# Absolute, always. git rejects a relative path in safe.directory — with a
# warning, not an error — and then refuses to read the SDK at all:
#
#   warning: safe.directory '.vercel/cache/flutter-3.44.9' not absolute
#   fatal: detected dubious ownership in repository at '/vercel/path0/...'
CACHE_DIR="${VERCEL_BUILD_CACHE_DIR:-$PWD/.vercel/cache}"
mkdir -p "$CACHE_DIR"
CACHE_DIR="$(cd "$CACHE_DIR" && pwd)"
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

# The SDK is cloned by root and read by the build user, so git calls it
# "dubious ownership" and refuses. Every flutter command shells out to git,
# so this is not cosmetic — without it nothing runs.
git config --global --add safe.directory "$FLUTTER_DIR" || true
git config --global --add safe.directory "$PWD" || true

flutter --version
flutter pub get

# The commit and the date go into the binary and print under the login card,
# the same way the Windows release does it. Without it every deploy reports
# "Build dev", which is worse than blank — it reads like a local build.
stamp="$(echo "${VERCEL_GIT_COMMIT_SHA:-local}" | cut -c1-7)·$(date -u '+%d.%m %H:%M')"
echo "BUILD_STAMP=$stamp"

# --no-web-resources-cdn: serve CanvasKit from our own origin. By default the
# loader fetches ~7MB of it from www.gstatic.com, which is not reliably
# reachable from Uzbekistan — and there is no fallback, so a blocked host is
# a blank page rather than a slow one. The files are already deployed under
# build/web/canvaskit and vercel.json caches them for a year; this flag is
# what makes the page actually ask for them.
flutter build web --release \
  --no-web-resources-cdn \
  --dart-define="BUILD_STAMP=$stamp"
