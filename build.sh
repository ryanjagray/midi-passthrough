#!/bin/zsh
# Local build of "Midi Passthrough.app" into ./build, ad-hoc signed with the sandbox entitlements.
set -e
cd "$(dirname "$0")"
xcodebuild -project MidiPassthrough.xcodeproj -scheme "Midi Passthrough" -configuration Release \
  -derivedDataPath build/xc CODE_SIGNING_ALLOWED=NO build | tail -1
rm -rf "build/Midi Passthrough.app"
cp -R "build/xc/Build/Products/Release/Midi Passthrough.app" build/
xattr -cr "build/Midi Passthrough.app"
codesign --force --sign - --options runtime --entitlements Sources/MidiPassthrough/MidiPassthrough.entitlements "build/Midi Passthrough.app"
echo "Built build/Midi Passthrough.app"
