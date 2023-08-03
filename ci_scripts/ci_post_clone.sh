#!/bin/sh

#  ci_post_clone.sh
#  Zotero
#
#  Created by Miltiadis Vasilakis on 3/8/23.
#  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.

which swiftgen || HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install swiftgen
which swiftlint || HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install swiftlint
