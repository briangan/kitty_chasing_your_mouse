#!/bin/bash

# Define Source and Destination
SRC="icon.png"
DEST="AppIcon.iconset"

mkdir $DEST

# Helper function
gen_icon() { sips -s format png -z $1 $1 "$SRC" --out "$DEST/$2"; }

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
