#!/bin/bash

# If the current working directory contains the substring "scripts",
# change to its parent directory.
if [[ $(pwd) == *scripts* ]]; then
    cd ..
fi

# Use the SRC environment variable if it’s set; otherwise default to "icon.png".
: ${SRC:=icon.png}

DEST="AppIcon.iconset"

# Ensure the destination directory exists
mkdir -p "$DEST"

# Helper function: create an icon of the requested size
gen_icon() {
    sips -s format png -z "$1" "$1" "$SRC" --out "$DEST/$2"
}

# Generate standard and retina sizes
gen_icon 16   "icon_16x16.png"
gen_icon 32   "icon_16x16@2x.png"
gen_icon 32   "icon_32x32.png"
gen_icon 64   "icon_32x32@2x.png"
gen_icon 128  "icon_128x128.png"
gen_icon 256  "icon_128x128@2x.png"
gen_icon 256  "icon_256x256.png"
gen_icon 512  "icon_256x256@2x.png"
gen_icon 512  "icon_512x512.png"
gen_icon 1024 "icon_512x512@2x.png"
