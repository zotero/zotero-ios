#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname $SCRIPT_PATH`
SCHEMA_FILE="$SCRIPT_DIR/../Zotero/Assets/schema.json"

curl --compressed https://api.zotero.org/schema --output $SCHEMA_FILE
