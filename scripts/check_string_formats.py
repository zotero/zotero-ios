#!/usr/bin/env python3
#
# Check that translated strings use the same format arguments as the English ones
#
# A translation that reorders unnumbered placeholders (e.g., "%@ in %@ (%d / %d)" for
# "Syncing %@ (%d / %d) in %@") passes arguments of the wrong type to String(format:),
# which crashes the app. Every string in the translated Localizable.strings and
# Localizable.stringsdict files is compared against en.lproj, and mismatches are listed.

import os
import plistlib
import re
import sys

ASSETS_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.realpath(__file__))), 'Zotero', 'Assets')
SPECIFIER = re.compile(r'%(?:(\d+)\$)?[-#+ 0\']*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j|L)?([@a-zA-Z%])')
TYPES = {
	'd': 'int', 'i': 'int', 'u': 'int', 'D': 'int', 'U': 'int', 'x': 'int', 'X': 'int', 'o': 'int', 'O': 'int', 'c': 'int',
	'f': 'float', 'F': 'float', 'e': 'float', 'E': 'float', 'g': 'float', 'G': 'float', 'a': 'float', 'A': 'float',
	'@': 'object', 's': 'cstring', 'S': 'cstring', 'p': 'pointer',
}
STRINGS_ENTRY = re.compile(r'/\*.*?\*/|//[^\n]*|"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.S)
VARIABLE = re.compile(r'%#@([A-Za-z_]\w*)@')
PLURAL_FORMS = ('zero', 'one', 'two', 'few', 'many', 'other')


def arg_types(text):
	"""Map each argument position to the types the string formats it as"""
	types = {}
	position = 0
	for match in SPECIFIER.finditer(text):
		conversion = match.group(2)
		if conversion == '%':
			continue
		if match.group(1):
			index = int(match.group(1))
		else:
			position += 1
			index = position
		types.setdefault(index, set()).add(TYPES.get(conversion, conversion))
	return types


def load_strings(path):
	strings = {}
	if os.path.exists(path):
		with open(path, encoding='utf-8') as f:
			for match in STRINGS_ENTRY.finditer(f.read()):
				if match.group(1) is not None:
					strings[match.group(1)] = [match.group(2)]
	return strings


def load_stringsdict(path):
	"""Expand each plural entry into one format string per plural form"""
	strings = {}
	if not os.path.exists(path):
		return strings
	with open(path, 'rb') as f:
		entries = plistlib.load(f)
	for key, entry in entries.items():
		format_key = entry.get('NSStringLocalizedFormatKey', '')
		variables = VARIABLE.findall(format_key)
		texts = []
		for form in PLURAL_FORMS:
			if not any(form in entry.get(variable, {}) for variable in variables):
				continue
			def expand(match):
				variable = entry.get(match.group(1), {})
				return variable.get(form, variable.get('other', ''))
			texts.append(VARIABLE.sub(expand, format_key))
		strings[key] = texts
	return strings


def load(lproj):
	strings = load_strings(os.path.join(lproj, 'Localizable.strings'))
	strings.update(load_stringsdict(os.path.join(lproj, 'Localizable.stringsdict')))
	return strings


def compatible(english, translation):
	"""Every argument the translation uses must exist in the English with the same type.
	Plural forms may leave out the count."""
	for index, types in translation.items():
		if index not in english or not types <= english[index]:
			return False
	return True


def main():
	english = load(os.path.join(ASSETS_DIR, 'en.lproj'))
	problems = []
	for folder in sorted(os.listdir(ASSETS_DIR)):
		if not folder.endswith('.lproj') or folder == 'en.lproj':
			continue
		for key, texts in load(os.path.join(ASSETS_DIR, folder)).items():
			if key not in english:
				continue
			expected = {}
			for text in english[key]:
				for index, types in arg_types(text).items():
					expected.setdefault(index, set()).update(types)
			for text in texts:
				if not compatible(expected, arg_types(text)):
					problems.append(f'{folder}: {key}: {text!r} (English: {english[key][-1]!r})')
	if problems:
		print(f'{len(problems)} translated strings have format arguments that don\'t match the English:')
		for problem in problems:
			print('  ' + problem)
		return 1
	print('All translated strings match the English format arguments')
	return 0


if __name__ == '__main__':
	sys.exit(main())
