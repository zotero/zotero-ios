#!/bin/bash

LAST_TAG=`git describe --tags $(git rev-list --tags --max-count=1)`
PARTS=(${LAST_TAG//-/ })
NEW_VERSION=`cat Zotero.xcodeproj/project.pbxproj | grep MARKETING_VERSION | head -n 1 | sed -E 's/.+([0-9]+\.[0-9]+\.[0-9]+).+/\1/'`
NEW_BUILD=$((${PARTS[1]}+1))

TAG="$NEW_VERSION-$NEW_BUILD"

echo "Pushing tag: $TAG"
git tag -a ${TAG} -m "$TAG"
git push origin ${TAG}