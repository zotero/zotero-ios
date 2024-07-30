#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath "$0"`
SCRIPT_DIR=`dirname "$SCRIPT_PATH"`
HASH_FILE="$SCRIPT_DIR/note_editor_hash.txt"
EDITOR_SUBMODULE_DIR="$SCRIPT_DIR/../note-editor"
EDITOR_DIR="$SCRIPT_DIR/../bundled/note_editor"

if [ ! -d "$HASH_FILE" ]; then
    echo "0" > "$HASH_FILE"
fi

CACHED_HASH=`cat "$HASH_FILE"`
CURRENT_HASH=`git ls-tree --object-only HEAD "$EDITOR_SUBMODULE_DIR"`

if [ -d "$EDITOR_DIR" ] && [ $CACHED_HASH != $CURRENT_HASH ]; then
    rm -rf "$EDITOR_DIR"
fi

if [ -d "$EDITOR_DIR" ]; then
    exit
fi

cd "$EDITOR_SUBMODULE_DIR"
npm ci
npm run build:ios
mv "$SCRIPT_DIR/../note-editor/build/ios" "$SCRIPT_DIR/../bundled/note_editor"
echo "$CURRENT_HASH" > "$HASH_FILE"