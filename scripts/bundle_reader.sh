#!/bin/bash

set -eo pipefail

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath "$0"`
SCRIPT_DIR=`dirname "$SCRIPT_PATH"`
READER_SUBMODULE_DIR="$SCRIPT_DIR/../reader"
READER_DIR="$SCRIPT_DIR/../bundled/reader"
HASH_FILE="$READER_DIR/reader_hash.txt"
CURRENT_HASH=`git ls-tree --object-only HEAD "$READER_SUBMODULE_DIR"`

# Check if the reader submodule is initialized
if ! git -C "$SCRIPT_DIR" submodule status "$READER_SUBMODULE_DIR" | grep -qv '^-'; then
    echo "Error: The reader submodule is not initialized. Run:"
    echo "    git submodule update --init --recursive reader"
    exit 1
fi

if [ -d "$READER_DIR" ]; then
    if [ -f "$HASH_FILE" ]; then
        CACHED_HASH=`cat "$HASH_FILE"`
    else
        CACHED_HASH=0
    fi

    if [ "$CACHED_HASH" == "$CURRENT_HASH" ]; then
        exit
    else
        rm -rf "$READER_DIR"
    fi
fi

cd "$READER_SUBMODULE_DIR"
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 21.7.3
NODE_OPTIONS=--openssl-legacy-provider npm config set maxsockets 3
NODE_OPTIONS=--openssl-legacy-provider npm ci
NODE_OPTIONS=--openssl-legacy-provider npm run build:ios
mv "$READER_SUBMODULE_DIR/build/ios" "$READER_DIR"
echo "$CURRENT_HASH" > "$HASH_FILE"