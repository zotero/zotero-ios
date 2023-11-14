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
  TESTFLIGHT_FILE_PATH=$TESTFLIGHT_DIR_PATH/WhatToTest.en-US.txt

  cat <<EOF > "$TESTFLIGHT_FILE_PATH"
(To unsubscribe from TestFlight emails, open the TestFlight app, tap on Zotero, and disable Email Notifications. We’re not able to unsubscribe you from TestFlight emails on our end.)

You’re using the beta version of Zotero for iOS. You can reinstall the production version of the app from the App Store at any time.

New in this version:

- Miscellaneous bug fixes

Please post to the Zotero Forums with all bug reports and feature requests.

Thanks for helping to test Zotero for iOS.

EOF

  if [[ -n "$CI_BRANCH" ]]; then
    echo "branch: $CI_BRANCH" >> "$TESTFLIGHT_FILE_PATH"
  fi
  echo "commit: $(git log -n 1 --pretty=format:"%h")" >> "$TESTFLIGHT_FILE_PATH"
  echo "message: $(git log -n 1 --pretty=format:"%s")" >> "$TESTFLIGHT_FILE_PATH"

  # Push version-build tag to origin
  VERSION=$(cat ../${CI_PRODUCT}.xcodeproj/project.pbxproj | grep -m1 'MARKETING_VERSION' | cut -d'=' -f2 | tr -d ';' | tr -d ' ')
  TAG="${VERSION}-${CI_BUILD_NUMBER}"
  git tag -a ${TAG} -m "$TAG"
  git push $github_pat_repo_url $TAG
fi
