#!/bin/bash

realpath() {
    [[ $1 = /* ]] && echo "$1" || echo "$PWD/${1#./}"
}

script_path=`realpath "$0"`
script_dir=`dirname "$script_path"`

font_url="https://raw.githubusercontent.com/notofonts/noto-cjk/refs/heads/main/google-fonts/NotoSansSC%5Bwght%5D.ttf"
output_directory="$script_dir/../Bundled/fonts"
mkdir -p $output_directory
output_filename="NotoSansSC[wght].ttf"
output_path="$output_directory/$output_filename"

if [ -f "$output_path" ]; then
	exit
fi

curl -fL -o "$output_path" $font_url || { echo "Font download failed"; exit 1; }
echo "Verifying downloaded font file..."
if file "$output_path" | grep -q "TrueType Font data"; then
    echo "Font file verification passed: $output_path is a TTF file."
else
    echo "Font file verification failed: $output_path is not a TTF file."
    rm -f "$output_path"
    exit 1
fi
