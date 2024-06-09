#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath "$0"`
SCRIPT_DIR=`dirname "$SCRIPT_PATH"`
EDITOR_DIR="$SCRIPT_DIR/../bundled/note_editor"

if [ -d "$EDITOR_DIR" ]; then
    rm -rf "$EDITOR_DIR"
fi

cd "$SCRIPT_DIR/../note-editor"
npm ci
npm run build:ios
mv "$SCRIPT_DIR/../note-editor/build/ios" "$SCRIPT_DIR/../bundled/note_editor"