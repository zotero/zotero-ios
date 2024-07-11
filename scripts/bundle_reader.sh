#!/bin/bash

 realpath() {
     [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
 }

 SCRIPT_PATH=`realpath "$0"`
 SCRIPT_DIR=`dirname "$SCRIPT_PATH"`
 READER_DIR="$SCRIPT_DIR/../bundled/reader"

 if [ -d "$EDITOR_DIR" ]; then
     rm -rf "$READER_DIR"
 fi

 cd "$SCRIPT_DIR/../reader"
 npm ci
 npm run build:ios
 mv "$SCRIPT_DIR/../reader/build/ios" "$READER_DIR"