#!/bin/sh

#  ci_pre_xcodebuild.sh
#  Zotero
#
#  Created by Michal Rentka on 01.06.2023.
#  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.


set -euo pipefail

# Install NVM
export NVM_DIR="$HOME/.nvm"
echo "Installing nvm..."
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash
# Verify install completed and source it
if [ -s "$NVM_DIR/nvm.sh" ]; then
  echo "Sourcing nvm..."
  \. "$NVM_DIR/nvm.sh"
else
  echo "Error: nvm.sh not found after install!"
  exit 1
fi
# Install and use Node
nvm install 21.7.3
nvm use 21.7.3
# Confirm
node -v
npm -v


git clone https://github.com/zotero/pdf-keys.git
license=$(grep -Eo '\"license_key\":\"[A-Za-z0-9_=\-]+\"' pdf-keys/ios_license.json | cut -c 15- | tr -d '"')
plist='<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>pspdfkit</key>
	<string>'"$license"'</string>
</dict>
</plist>'
echo "$plist" > licenses/licenses.plist
rm -rf pdf-keys