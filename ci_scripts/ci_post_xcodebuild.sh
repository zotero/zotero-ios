#!/bin/bash

#  ci_post_xcodebuild.sh
#  Zotero
#
#  Created by Miltiadis Vasilakis on 28/8/23.
#  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.

set -eo pipefail

if [[ -d "$CI_APP_STORE_SIGNED_APP_PATH" ]]; then
  TESTFLIGHT_DIR_PATH=../TestFlight
  mkdir -p $TESTFLIGHT_DIR_PATH
  cat <<EOF > "$TESTFLIGHT_DIR_PATH/WhatToTest.en-US.txt"
branch: $CI_BRANCH
commit: $(git log -n 1 --pretty=format:"%h")
message: $(git log -n 1 --pretty=format:"%s")
EOF

  # Push version-build tag to origin
  VERSION=$(cat ../${CI_PRODUCT}.xcodeproj/project.pbxproj | grep -m1 'MARKETING_VERSION' | cut -d'=' -f2 | tr -d ';' | tr -d ' ')
  TAG="${VERSION}-${CI_BUILD_NUMBER}"
  git tag -a ${TAG} -m "$TAG"
  git push $github_pat_repo_url $TAG
fi
