#!/bin/sh

#  pre-xcodebuild.sh
#  Zotero
#
#  Created by Michal Rentka on 01.06.2023.
#  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.

git clone https://github.com/zotero/pdf-keys.git
mv pdf-keys/licenses.plist licenses/licenses.plist
rm -rf pdf-keys
