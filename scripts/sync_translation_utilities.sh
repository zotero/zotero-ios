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

if [ ! -f "$UTILITIES_SUBMODULE_DIR/resource/zoteroTypeSchemaData.js" ]; then
    echo "error: The utilities submodule is not initialized. Run:"
    echo "    git submodule update --init --recursive utilities"
    exit 1
fi

if [ ! -d "$TRANSLATE_MODULES_DIR" ]; then
    echo "error: $TRANSLATE_MODULES_DIR not found"
    exit 1
fi

rm -rf "$DESTINATION_DIR"
mkdir -p "$DESTINATION_DIR"
cp -R "$UTILITIES_SUBMODULE_DIR"/[!.]* "$DESTINATION_DIR"

# Remove files not needed at runtime
for i in 'test' 'package.json' 'package-lock.json' 'README.md' 'resource/README.md' 'resource/schema'; do
    rm -rf "$DESTINATION_DIR/$i"
done
