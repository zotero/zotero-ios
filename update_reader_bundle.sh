#!/bin/bash
# Quick script to update reader bundle after making changes

set -e

cd "$(dirname "$0")/reader"

echo "Building reader..."
npm run build:ios

cd ..

echo "Copying bundle..."
mkdir -p bundled/reader
rm -rf bundled/reader/*
cp -r reader/build/ios/* bundled/reader/

echo "Updating hash..."
git ls-tree --object-only HEAD reader > bundled/reader/reader_hash.txt

echo "Done! Now rebuild in Xcode (Cmd+B)"
