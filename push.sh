#!/bin/bash
set -e
UDID="00008130-000C6CA63C9A001C"

echo "Building knep iOS..."
xcodebuild \
  -project knep.xcodeproj \
  -scheme knep-ios \
  -destination "id=$UDID" \
  -configuration Debug \
  -allowProvisioningUpdates \
  build 2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED|Installing"

APP=$(find ~/Library/Developer/Xcode/DerivedData -name "knep.app" -path "*/Debug-iphoneos/*" 2>/dev/null | head -1)
echo "Installing: $APP"
xcrun devicectl device install app --device "66E3E41D-D1CC-57AD-93E9-FC50FD8BFCD0" "$APP"
echo "Done — knep on iPhone"
