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
elif [[ ! "$versionString" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: versionString is not in 'major.minor.patch' format"
    exit 1
fi

bump_version() {
    local version="$1"
    local part="$2"

    # Split the version string into major, minor, and patch parts
    IFS='.' read -r -a version_parts <<< "$version"

    case "$part" in
        "major")
            ((version_parts[0]++))
            version_parts[1]=0
            version_parts[2]=0
            ;;
        "minor")
            ((version_parts[1]++))
            version_parts[2]=0
            ;;
        "patch")
            ((version_parts[2]++))
            ;;
        *)
            echo "Error: Invalid version part $part"
            exit 1
            ;;
    esac

    echo "${version_parts[0]}.${version_parts[1]}.${version_parts[2]}"
}

# Extract version bump
case "$(echo "$CI_TAG" | sed -n 's/^trigger-build-bump-\(.*\)-date-.*$/\1/p')" in
    "patch")
        newVersionString=$(bump_version "$versionString" "patch")
        ;;
    "minor")
        newVersionString=$(bump_version "$versionString" "minor")
        ;;
    "major")
        newVersionString=$(bump_version "$versionString" "major")
        ;;
    *)
        echo "Error: Invalid version bump in CI_TAG: $CI_TAG"
        exit 1
        ;;
esac

# Update Info.plist files
echo "Setting version to $newVersionString"
sed -i "" -e "s/MARKETING_VERSION \= [^\;]*\;/MARKETING_VERSION = $newVersionString;/" ../Zotero.xcodeproj/project.pbxproj

# Install node
which node || HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install node