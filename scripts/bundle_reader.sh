#!/bin/bash

set -eo pipefail

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath "$0"`
SCRIPT_DIR=`dirname "$SCRIPT_PATH"`
SUBMODULE_DIR="$SCRIPT_DIR/../reader"
DESTINATION_DIR="$SCRIPT_DIR/../bundled/reader"
HASH_FILE="$DESTINATION_DIR/reader_hash.txt"
CURRENT_HASH=`git ls-tree --object-only HEAD "$SUBMODULE_DIR"`
DOWNLOAD_URL="https://zotero-download.s3.amazonaws.com/ci/client-reader/${CURRENT_HASH}.zip"
BUILD_SOURCE_DIR="ios"

if [ -d "$DESTINATION_DIR" ]; then
    if [ -f "$HASH_FILE" ]; then
        CACHED_HASH=`cat "$HASH_FILE"`
    else
        CACHED_HASH=0
    fi

    if [ "$CACHED_HASH" == "$CURRENT_HASH" ]; then
        echo "Build already up to date."
        exit
    else
        rm -rf "$DESTINATION_DIR"
    fi
fi

TMP_DIR=$(mktemp -d)
echo "Created temp dir: $TMP_DIR"

echo "Downloading build from: $DOWNLOAD_URL"
curl -L "$DOWNLOAD_URL" -o "$TMP_DIR/build.zip"

echo "Unzipping..."
unzip -q "$TMP_DIR/build.zip" -d "$TMP_DIR/build"

if [ ! -d "$TMP_DIR/build/$BUILD_SOURCE_DIR" ]; then
    echo "Error: $BUILD_SOURCE_DIR build not found in the archive."
    exit 1
fi

mkdir -p "$DESTINATION_DIR"
shopt -s dotglob
cp -r "$TMP_DIR/build/$BUILD_SOURCE_DIR/"* "$DESTINATION_DIR"
shopt -u dotglob

echo "$CURRENT_HASH" > "$HASH_FILE"
echo "Build $BUILD_SOURCE_DIR installed at $DESTINATION_DIR from hash $CURRENT_HASH"

rm -rf "$TMP_DIR"