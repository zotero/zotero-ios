#!/bin/sh

#  ci_pre_xcodebuild.sh
#  Zotero
#
#  Created by Michal Rentka on 01.06.2023.
#  Copyright © 2023 Corporation for Digital Scholarship. All rights reserved.

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

brew install node
npm install
npm install webpack
npm install webpack-cli
npm install html-webpack-plugin
npm install mini-css-extract-plugin
npm install css-minimizer-webpack-plugin
npm install terser-webpack-plugin
npm install clean-webpack-plugin 
npm install babel-loader
npm install postcss-loader