#!/bin/bash
set -e
UDID="00008130-000C6CA63C9A001C"
DEVICE_ID="66E3E41D-D1CC-57AD-93E9-FC50FD8BFCD0"

# Regenerate xcodeproj from project.yml
echo "Generating xcodeproj..."
xcodegen generate --quiet

# ── Mac app ──────────────────────────────────────────────────────────────────
echo "Building knep Mac..."
xcodebuild \
  -project knep.xcodeproj \
  -scheme knep-mac \
  -configuration Debug \
  -allowProvisioningUpdates \
  build 2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"

MAC_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "knep.app" \
  -path "*/Build/Products/Debug/knep.app" 2>/dev/null | head -1)
echo "Mac app: $MAC_APP"

pkill -9 -x knep 2>/dev/null || true
sleep 0.5
rm -rf ~/Desktop/knep.app
cp -R "$MAC_APP" ~/Desktop/knep.app

# Reset TCC so the new properly-signed binary can request Screen Recording
tccutil reset ScreenCapture com.djsly.knep 2>/dev/null || true
rm -f /tmp/knep_sck.log

echo "Launching Mac app..."
open ~/Desktop/knep.app
sleep 2

echo ""
echo "═══════════════════════════════════════════════════════"
echo " ACTION REQUIRED:"
echo " System Settings → Privacy → Screen Recording"
echo " Toggle knep ON if it asks"
echo " Then run: pkill -x knep && open ~/Desktop/knep.app"
echo "═══════════════════════════════════════════════════════"
echo ""
read -r -p "Press Enter after granting Screen Recording and relaunching knep..."

# ── iOS app ───────────────────────────────────────────────────────────────────
echo "Building knep iOS..."
xcodebuild \
  -project knep.xcodeproj \
  -scheme knep-ios \
  -destination "id=$UDID" \
  -configuration Debug \
  -allowProvisioningUpdates \
  build 2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED|Installing"

IOS_APP=$(find ~/Library/Developer/Xcode/DerivedData -name "knep.app" -path "*/Debug-iphoneos/*" 2>/dev/null | head -1)
echo "Installing iOS: $IOS_APP"
xcrun devicectl device install app --device "$DEVICE_ID" "$IOS_APP"

echo ""
echo "Done. Open knep on iPhone — it will find the Mac automatically."
echo "If black screen: cat /tmp/knep_sck.log"
