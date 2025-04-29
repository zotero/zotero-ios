#!/bin/bash

set -eo pipefail

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath "$0"`
SCRIPT_DIR=`dirname "$SCRIPT_PATH"`
WORKER_SUBMODULE_DIR="$SCRIPT_DIR/../pdf-worker"
WORKER_DIR="$SCRIPT_DIR/../bundled/pdf_worker"
HASH_FILE="$WORKER_DIR/pdf_worker_hash.txt"
CURRENT_HASH=`git ls-tree --object-only HEAD "$WORKER_SUBMODULE_DIR"`

# Check if the pdf-worker submodule is initialized
if ! git -C "$SCRIPT_DIR" submodule status "$WORKER_SUBMODULE_DIR" | grep -qv '^-'; then
    echo "Error: The pdf-worker submodule is not initialized. Run:"
    echo "    git submodule update --init --recursive pdf-worker"
    exit 1
fi

if [ -d "$WORKER_DIR" ]; then
    if [ -f "$HASH_FILE" ]; then
        CACHED_HASH=`cat "$HASH_FILE"`
    else 
        CACHED_HASH=0
    fi

    if [ "$CACHED_HASH" == "$CURRENT_HASH" ]; then
        exit
    else
        rm -rf "$WORKER_DIR"
    fi
fi

cd "$WORKER_SUBMODULE_DIR" 
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
nvm install 21.7.3
npm ci
npm run build
mv "$SCRIPT_DIR/../pdf-worker/build" "$WORKER_DIR"
echo "$CURRENT_HASH" > "$HASH_FILE"