#!/usr/bin/env python3
#
# Check that every localized file in Zotero/Assets is part of the Xcode project
#
# The project lists each language's copy of each strings file individually, and a
# file that isn't listed is silently left out of the app. Files pulled from Transifex
# for a new language, or a language's first copy of a file, have to be added in Xcode
# (or to Zotero.xcodeproj/project.pbxproj) before they ship.

import os
import re
import sys

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
ASSETS_DIR = os.path.join(ROOT_DIR, 'Zotero', 'Assets')
PROJECT = os.path.join(ROOT_DIR, 'Zotero.xcodeproj', 'project.pbxproj')
FILES = ('InfoPlist.strings', 'Localizable.strings', 'Localizable.stringsdict')


def main():
	with open(PROJECT, encoding='utf-8') as f:
		project = f.read()
	registered = set(re.findall(r'path = "?([\w-]+\.lproj/[\w.]+)"?;', project))
	regions = set(re.findall(r'^\t*"?([\w-]+)"?,$', project[project.index('knownRegions = ('):].split(');', 1)[0], re.M))

	missing = []
	for folder in sorted(os.listdir(ASSETS_DIR)):
		if not folder.endswith('.lproj'):
			continue
		language = folder[:-len('.lproj')]
		if language not in regions:
			missing.append(f'{language} (not in knownRegions)')
		for filename in FILES:
			path = f'{folder}/{filename}'
			if os.path.exists(os.path.join(ASSETS_DIR, path)) and path not in registered:
				missing.append(path)

	if missing:
		print(f'{len(missing)} localized files aren\'t in the Xcode project and won\'t be included in the app:')
		for path in missing:
			print('  ' + path)
		return 1
	print('All localized files are in the Xcode project')
	return 0


if __name__ == '__main__':
	sys.exit(main())
