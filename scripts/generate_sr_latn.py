#!/usr/bin/env python3
#
# Generate the Serbian Latin localization (sr-Latn.lproj) from the Cyrillic one (sr.lproj)
#
# Serbian Cyrillic maps one-to-one to Serbian Latin, so every file in sr.lproj is
# copied with Cyrillic letters transliterated. Anything not in Cyrillic (keys,
# format specifiers, markup, names already written in Latin) is left as is. Foreign
# names that the Cyrillic spells phonetically are restored to their original
# spelling via LATIN_NAMES and LATIN_PHRASES.
#
# Zotero desktop uses the same transliteration (scripts/locale/generate_sr_latn in
# zotero/zotero), so new exceptions should be added in both places.

import os
import re
import shutil
import sys

CYRILLIC_TO_LATIN = {
	'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'д': 'd', 'ђ': 'đ', 'е': 'e',
	'ж': 'ž', 'з': 'z', 'и': 'i', 'ј': 'j', 'к': 'k', 'л': 'l', 'љ': 'lj',
	'м': 'm', 'н': 'n', 'њ': 'nj', 'о': 'o', 'п': 'p', 'р': 'r', 'с': 's',
	'т': 't', 'ћ': 'ć', 'у': 'u', 'ф': 'f', 'х': 'h', 'ц': 'c', 'ч': 'č',
	'џ': 'dž', 'ш': 'š',
}

# Transliterated spelling -> original spelling. Serbian case endings after the
# name are kept (e.g., "Vordu" -> "Wordu").
LATIN_NAMES = {
	'Arkajv': 'arXiv',
	'BibTeH': 'BibTeX',
	'Dropboks': 'Dropbox',
	'Eskejp': 'Escape',
	'Gugl': 'Google',
	'Javaskript': 'JavaScript',
	'Kalibre': 'Calibre',
	'Kičejn': 'Keychain',
	'KORider': 'KOReader',
	'Libreofis': 'LibreOffice',
	'Mendeli': 'Mendeley',
	'Šift': 'Shift',
	'VebDAV': 'WebDAV',
	'Vord': 'Word',
}

# Applied after LATIN_NAMES
LATIN_PHRASES = {
	'aj-OS': 'iOS',
	'Arhiv ID': 'arXiv ID',
	'Krijejtiv komons': 'Creative Commons',
	'Mendeley desktop': 'Mendeley Desktop',
	'Van drajv': 'OneDrive',
}

LETTER = r'[^\W\d_]'


def transliterate_char(text, i):
	c = text[i]
	lower = c.lower()
	latin = CYRILLIC_TO_LATIN.get(lower)
	if latin is None:
		return c
	if c == lower:
		return latin
	# Uppercase digraph letters (Љ, Њ, Џ) are all caps within an all-caps word
	# (e.g., "ЉУБАВ" -> "LJUBAV") and title case otherwise ("Љубав" -> "Ljubav")
	if len(latin) > 1:
		neighbors = text[max(i - 1, 0):i] + text[i + 1:i + 2]
		if any(n.isupper() for n in neighbors):
			return latin.upper()
		return latin[0].upper() + latin[1:]
	return latin.upper()


def transliterate(text):
	latin = ''.join(transliterate_char(text, i) for i in range(len(text)))
	for transliterated, original in LATIN_NAMES.items():
		latin = re.sub(
			rf'(?<!{LETTER}){re.escape(transliterated)}(?={LETTER}{{0,3}}(?!{LETTER}))',
			original,
			latin
		)
	for transliterated, original in LATIN_PHRASES.items():
		latin = latin.replace(transliterated, original)
	return latin


def main():
	script_dir = os.path.dirname(os.path.realpath(__file__))
	assets_dir = os.path.join(os.path.dirname(script_dir), 'Zotero', 'Assets')
	source_dir = os.path.join(assets_dir, 'sr.lproj')
	target_dir = os.path.join(assets_dir, 'sr-Latn.lproj')

	if not os.path.isdir(source_dir):
		sys.stderr.write(f'{source_dir} not found\n')
		return 1

	shutil.rmtree(target_dir, ignore_errors=True)
	os.makedirs(target_dir)

	for filename in sorted(os.listdir(source_dir)):
		with open(os.path.join(source_dir, filename), encoding='utf-8') as f:
			text = f.read()
		with open(os.path.join(target_dir, filename), 'w', encoding='utf-8') as f:
			f.write(transliterate(text))

	print('Generated sr-Latn.lproj from sr.lproj')
	return 0


if __name__ == '__main__':
	sys.exit(main())
