#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath "$0"`
SCRIPT_DIR=`dirname "$SCRIPT_PATH"`
UTILITIES_SUBMODULE_DIR="$SCRIPT_DIR/../utilities"
UTILITIES_DIR="$SCRIPT_DIR/../Zotero/Controllers/Citation/citation/utilities"
HASH_FILE="$UTILITIES_DIR/utilities_hash.txt"
CURRENT_HASH=`git ls-tree --object-only HEAD "$UTILITIES_SUBMODULE_DIR"`

if [ -d "$UTILITIES_DIR" ]; then
    if [ -f "$HASH_FILE" ]; then
        CACHED_HASH=`cat "$HASH_FILE"`
    else 
        CACHED_HASH=0
    fi

    if [ "$CACHED_HASH" == "$CURRENT_HASH" ]; then
        exit
    else
        rm -rf "$UTILITIES_DIR"
    fi
fi

mkdir -p "$UTILITIES_DIR"
cp -R "$UTILITIES_SUBMODULE_DIR"/[!.]* "$UTILITIES_DIR"
echo "$CURRENT_HASH" > "$HASH_FILE"