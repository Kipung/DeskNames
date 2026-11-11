#!/bin/zsh
set -eu
cd "${0:A:h}/.."
VERSION=2.10.1
CHECKSUM=1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27
ARCHIVE="$PWD/.build-deps/Sparkle-$VERSION.tar.xz"
mkdir -p .build-deps
if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --proto '=https' --tlsv1.2 --retry 3 \
    "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$ARCHIVE.download"
  mv "$ARCHIVE.download" "$ARCHIVE"
fi
printf '%s  %s\n' "$CHECKSUM" "$ARCHIVE" | shasum -a 256 --check
if [[ ! -d .build-deps/sparkle/Sparkle.framework ]]; then
  mkdir -p .build-deps/sparkle
  tar -xf "$ARCHIVE" -C .build-deps/sparkle
fi
