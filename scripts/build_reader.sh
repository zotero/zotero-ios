#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath "$0"`
SCRIPT_DIR=`dirname "$SCRIPT_PATH"`
READER_DIR="$SCRIPT_DIR/../reader"
BUILD_DIR="$READER_DIR/build/ios"
BUNDLED_DIR="$SCRIPT_DIR/../bundled/reader"

if [ ! -d "$READER_DIR" ]; then
exit
fi

cd "$READER_DIR"
NODE_OPTIONS=--openssl-legacy-provider npm i
NODE_OPTIONS=--openssl-legacy-provider npm run build:ios

if [ ! -d "$BUILD_DIR" ]; then
exit
fi

if [ -d "$BUNDLED_DIR" ]; then
rm -r "$BUNDLED_DIR"
fi

mv "$BUILD_DIR" "$BUNDLED_DIR"