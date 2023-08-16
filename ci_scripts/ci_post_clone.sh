#!/bin/bash

#  ci_post_clone.sh
#  Zotero
#
#  Created by Miltiadis Vasilakis on 3/8/23.
#  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.

set -euo pipefail

which swiftgen || HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install swiftgen
which swiftlint || HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install swiftlint
which openssl || HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install openssl
which python3 || HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install python3
which jq || HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install jq
pip3 install joserfc

# Generate JWT token
jwt_token=$(./generate_jtw_token.py)

# App Store Connect API request
response=$(curl -s --header "Authorization: Bearer $jwt_token" "https://api.appstoreconnect.apple.com/v1/apps/$zotero_app_id/appStoreVersions?filter%5BappStoreState%5D=READY_FOR_SALE&fields%5BappStoreVersions%5D=versionString")
versionString=$(echo "$response" | jq -r '.data[0].attributes.versionString')
if [[ "$versionString" == "null" ]]; then
    echo "Error: versionString is null"
    exit 1
fi

# Increment version string
newVersionString=$(awk -F. -v OFS=. '{$NF = $NF + 1; print}' <<< "$versionString")

# Update Info.plist files
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $newVersionString" ../Zotero/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $newVersionString" ../ZShare/Info.plist
