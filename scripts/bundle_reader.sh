#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath "$0"`
SCRIPT_DIR=`dirname "$SCRIPT_PATH"`
READER_DIR="$SCRIPT_DIR/../bundled/reader"

if [ -d "$READER_DIR" ]; then
 rm -rf "$READER_DIR"
fi

cd "$SCRIPT_DIR/../reader"
NODE_OPTIONS=--openssl-legacy-provider npm ci
NODE_OPTIONS=--openssl-legacy-provider npm run build:ios
mv "$SCRIPT_DIR/../reader/build/ios" "$READER_DIR"