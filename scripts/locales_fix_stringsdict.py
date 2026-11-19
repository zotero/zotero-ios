#!/usr/bin/env python3
"""
Post-process Localizable.stringsdict files after `tx pull`.

The Transifex client's STRINGSDICT serializer:
  - drops the <!DOCTYPE> line
  - emits 2/4-space indentation instead of tabs
  - flattens any literal text wrapping a %#@key@ reference in
    NSStringLocalizedFormatKey into each plural string (e.g.
    "%#@files@ (%.2f %@)" becomes "%#@files@" with " (%.2f %@)"
    appended to every plural value)

This script reformats each translated file with tab indentation and the
correct DOCTYPE, and restores the NSStringLocalizedFormatKey wrapper text
from en.lproj while stripping it back out of the plural strings.
"""

import plistlib
import re
import sys
from pathlib import Path

ASSETS_DIR = Path(__file__).resolve().parent.parent / "Zotero" / "Assets"
SOURCE = ASSETS_DIR / "en.lproj" / "Localizable.stringsdict"

FORMAT_KEY = "NSStringLocalizedFormatKey"
SPEC_KEYS = {"NSStringFormatSpecTypeKey", "NSStringFormatValueTypeKey"}
FORMAT_PATTERN = re.compile(r"(.*?)%#@([A-Za-z_][\w]*)@(.*)", re.DOTALL)


def load(path):
	with open(path, "rb") as f:
		return plistlib.load(f, dict_type=dict)


def split_format(value):
	m = FORMAT_PATTERN.fullmatch(value)
	if not m:
		return None
	return m.group(1), m.group(2), m.group(3)


def restore_entry(src_entry, dst_entry):
	src_fmt = src_entry.get(FORMAT_KEY)
	dst_fmt = dst_entry.get(FORMAT_KEY)
	if not isinstance(src_fmt, str) or not isinstance(dst_fmt, str):
		return
	src_split = split_format(src_fmt)
	dst_split = split_format(dst_fmt)
	if not src_split or not dst_split:
		return
	src_prefix, src_name, src_suffix = src_split
	_, dst_name, _ = dst_split
	if src_name != dst_name:
		return
	if not src_prefix and not src_suffix:
		return
	dst_entry[FORMAT_KEY] = src_fmt
	plural = dst_entry.get(src_name)
	if not isinstance(plural, dict):
		return
	for key, val in list(plural.items()):
		if key in SPEC_KEYS or not isinstance(val, str):
			continue
		if src_prefix and val.startswith(src_prefix):
			val = val[len(src_prefix):]
		if src_suffix and val.endswith(src_suffix):
			val = val[:-len(src_suffix)]
		plural[key] = val


def fix_file(path, source_data):
	data = load(path)
	for top_key, entry in data.items():
		src_entry = source_data.get(top_key)
		if isinstance(entry, dict) and isinstance(src_entry, dict):
			restore_entry(src_entry, entry)
	body = plistlib.dumps(data, fmt=plistlib.FMT_XML, sort_keys=False)
	# plistlib writes literal apostrophes; existing files use &apos;.
	body = body.replace(b"'", b"&apos;")
	with open(path, "wb") as f:
		f.write(body)


def main():
	if not SOURCE.exists():
		print(f"Source not found: {SOURCE}", file=sys.stderr)
		return 1
	source_data = load(SOURCE)
	failed = False
	for lproj in sorted(ASSETS_DIR.glob("*.lproj")):
		path = lproj / "Localizable.stringsdict"
		if not path.exists() or path.resolve() == SOURCE.resolve():
			continue
		try:
			fix_file(path, source_data)
		except Exception as e:
			print(f"Failed: {path}: {e}", file=sys.stderr)
			failed = True
	return 1 if failed else 0


if __name__ == "__main__":
	sys.exit(main())
