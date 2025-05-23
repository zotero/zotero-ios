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

generate_feature_gates_line() {
    local featureGates="$1"
    local line='SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited)'

    case "$featureGates" in
        all)
            line="$line FEATURE_GATES_ALL"
            ;;
        none)
            # No feature gates added
            ;;
        +*|*+|*[^a-zA-Z0-9+_-]*)
            echo "Error: Invalid feature gates format: $featureGates" >&2
            return 1
            ;;
        *)
            IFS='+' read -ra FEATURES <<< "$featureGates"
            for feature in "${FEATURES[@]}"; do
                UPPERCASE_FEATURE=$(echo "$feature" | tr '[:lower:]-' '[:upper:]_')
                line="$line FEATURE_GATE_${UPPERCASE_FEATURE}"
            done
            ;;
    esac

    echo "$line"
}


# Extract version bump
case "$(echo "$CI_TAG" | sed -n 's/^trigger-build-bump-\(.*\)-feature-gates-\(.*\)-date-.*$/\1/p')" in
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

# Extract feature gates
featureGates="$(echo "$CI_TAG" | sed -n 's/^trigger-build-bump-\(.*\)-feature-gates-\(.*\)-date-.*$/\2/p')"
if [[ -z "$featureGates" ]]; then
    echo "Error: Could not extract feature gates from CI_TAG: $CI_TAG"
    exit 1
fi
featureGatesLine="$(generate_feature_gates_line "$featureGates")" || exit 1

# Update Info.plist files
echo "Setting version to $newVersionString"
sed -i "" -e "s/MARKETING_VERSION \= [^\;]*\;/MARKETING_VERSION = $newVersionString;/" ../Zotero.xcodeproj/project.pbxproj

# Update FeatureGates.xcconfig
echo "Setting FeatureGates.xcconfig to $featureGatesLine"
echo "$featureGatesLine" > FeatureGates.xcconfig

# Install node
which node || HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install node