#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname $SCRIPT_PATH`
LICENSES_DIR="$SCRIPT_DIR/../pdf-keys"
LICENSES_FILE="$LICENSES_DIR/licenses.plist"
POD_FILE="$LICENSES_DIR/pspdfkit_pod.txt"

if [ -d "$LICENSES_DIR" ]; then
exit
fi

mkdir "pdf-keys"

cat > "$LICENSES_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>pspdfkit</key>
<string></string>
</dict>
</plist>
EOF

touch "$POD_FILE"
