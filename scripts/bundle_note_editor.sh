#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath "$0"`
SCRIPT_DIR=`dirname "$SCRIPT_PATH"`
EDITOR_SUBMODULE_DIR="$SCRIPT_DIR/../note-editor"
EDITOR_DIR="$SCRIPT_DIR/../bundled/note_editor"
HASH_FILE="$EDITOR_DIR/note_editor_hash.txt"
CURRENT_HASH=`git ls-tree --object-only HEAD "$EDITOR_SUBMODULE_DIR"`

if [ -d "$EDITOR_DIR" ]; then
    if [ -d "$HASH_FILE" ]; then
        CACHED_HASH=`cat "$HASH_FILE"`
    else 
        CACHED_HASH=0
    fi

    if [ $CACHED_HASH == $CURRENT_HASH ]; then
        exit
    else
        rm -rf "$EDITOR_DIR"
    fi
fi

cd "$EDITOR_SUBMODULE_DIR"
npm ci
npm run build:ios
mv "$SCRIPT_DIR/../note-editor/build/ios" "$EDITOR_DIR"
echo "$CURRENT_HASH" > "$HASH_FILE"