#!/bin/zsh
#
# Builds a universal Release copy of gesture_lens and packages it into a styled
# drag-to-Applications disk image at the top of the repo (gesture_lens.dmg), where
# people downloading the project can find it. Commit the new DMG after rebuilding it.
#
# Usage: ./dmg/make_dmg.sh
#
# Finder lays out the window via AppleScript, so the first run asks for permission
# to control Finder.

set -euo pipefail

ROOT=${0:A:h:h}
WORK=$ROOT/build/dmg
DERIVED=$WORK/DerivedData
STAGING=$WORK/staging
VOLUME_NAME=gesture_lens
RW_DMG=$WORK/gesture_lens-rw.dmg
FINAL_DMG=$ROOT/gesture_lens.dmg

rm -rf $STAGING $RW_DMG $FINAL_DMG
mkdir -p $STAGING/.background

echo "> building release app"
xcodebuild -project $ROOT/gesture_lens.xcodeproj -scheme gesture_lens -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath $DERIVED ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    clean build -quiet
cp -R $DERIVED/Build/Products/Release/gesture_lens.app $STAGING/
ln -s /Applications $STAGING/Applications

echo "> rendering background"
# Compiled rather than run as a script so the module cache can live in a writable place.
swiftc -module-cache-path $WORK/ModuleCache -O $ROOT/dmg/render_background.swift -o $WORK/render_background
$WORK/render_background $WORK
# One TIFF holding both resolutions, so the background is sharp on Retina displays.
tiffutil -cathidpicheck $WORK/background.png $WORK/background@2x.png -out $STAGING/.background/background.tiff

echo "> creating disk image"
# Leave some free space so Finder can save the window layout (.DS_Store) onto the volume.
SIZE_MB=$(( $(du -sm $STAGING | cut -f1) + 20 ))
hdiutil create -quiet -srcfolder $STAGING -volname $VOLUME_NAME -fs HFS+ -format UDRW -size ${SIZE_MB}m -ov $RW_DMG
# Detach any copy left mounted by an earlier run, so the volume name is free.
if [[ -d /Volumes/$VOLUME_NAME ]]; then
    hdiutil detach -quiet /Volumes/$VOLUME_NAME
fi
MOUNT_DIR=$(hdiutil attach -readwrite -noverify -noautoopen $RW_DMG | awk -F'\t' '/\/Volumes\// { print $NF }')

echo "> laying out window"
# Window bounds and icon positions match the art in render_background.swift
# (a 640×400 window, icons centered at (170, 190) and (470, 190)).
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 840, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 96
        set text size of viewOptions to 12
        set background picture of viewOptions to file ".background:background.tiff"
        set position of item "gesture_lens.app" of container window to {170, 190}
        set position of item "Applications" of container window to {470, 190}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Make sure Finder has written .DS_Store before unmounting.
sync
hdiutil detach -quiet $MOUNT_DIR

echo "> compressing"
hdiutil convert -quiet $RW_DMG -format UDZO -imagekey zlib-level=9 -o $FINAL_DMG
rm -f $RW_DMG

echo "> done: $FINAL_DMG"
