#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath "$0"`
SCRIPT_DIR=`dirname "$SCRIPT_PATH"`

"$SCRIPT_DIR/licenses.sh"
"$SCRIPT_DIR/fetch_bundled_jsons.sh"