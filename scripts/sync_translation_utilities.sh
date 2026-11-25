#!/bin/bash

# The translate submodule pins its own (outdated) utilities submodule. Its field definitions (zoteroTypeSchemaData.js)
# can fall behind bundled/schema.json, which provides the CSL mappings at runtime. Like the Zotero Connector, ignore the
# nested copy and bundle the top-level utilities submodule in its place.

set -eo pipefail

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath "$0"`
SCRIPT_DIR=`dirname "$SCRIPT_PATH"`
UTILITIES_SUBMODULE_DIR="$SCRIPT_DIR/../utilities"
TRANSLATE_MODULES_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/translation/translate/modules"
DESTINATION_DIR="$TRANSLATE_MODULES_DIR/utilities"

# Only the files that are used: the scripts loaded by translation/index.html and translation/lookup.html, dateFormats.json,
# which is read natively, and the license. Keep in sync with the HTML files.
FILES="
COPYING
cachedTypes.js
date.js
openurl.js
schema.js
utilities.js
utilities_item.js
xregexp-all.js
xregexp-unicode-zotero.js
resource/zoteroTypeSchemaData.js
resource/dateFormats.json
"

if [ ! -f "$UTILITIES_SUBMODULE_DIR/resource/zoteroTypeSchemaData.js" ]; then
    echo "error: The utilities submodule is not initialized. Run:"
    echo "    git submodule update --init utilities"
    exit 1
fi

for FILE in $FILES; do
    if [ ! -f "$UTILITIES_SUBMODULE_DIR/$FILE" ]; then
        echo "error: utilities/$FILE not found"
        exit 1
    fi
done

if [ ! -d "$TRANSLATE_MODULES_DIR" ]; then
    echo "error: $TRANSLATE_MODULES_DIR not found"
    exit 1
fi

rm -rf "$DESTINATION_DIR"
for FILE in $FILES; do
    mkdir -p "$DESTINATION_DIR/`dirname "$FILE"`"
    cp "$UTILITIES_SUBMODULE_DIR/$FILE" "$DESTINATION_DIR/$FILE"
done
