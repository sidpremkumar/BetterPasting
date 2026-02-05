#!/bin/bash
set -e

echo "=== BetterPasting Production Build ==="
echo ""

# Ensure we're in the project root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Check for required tools
if ! command -v swift &> /dev/null; then
    echo "Error: swift is not installed"
    exit 1
fi

# App name and bundle identifier
APP_NAME="BetterPasting"
BUNDLE_ID="com.sidpremkumar.BetterPasting"

# Build the Swift package in release mode
echo "[1/3] Building Swift package (Release)..."
swift build -c release

# Create the .app bundle structure
echo "[2/3] Creating app bundle..."
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_DIR="$SCRIPT_DIR/.build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# Clean previous bundle
rm -rf "$APP_DIR"

# Create directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"

# Copy resources if they exist
if [ -d "$SCRIPT_DIR/BetterPasting/Resources" ]; then
    cp -R "$SCRIPT_DIR/BetterPasting/Resources/"* "$RESOURCES_DIR/" 2>/dev/null || true
fi

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
EOF

# Sign the app (ad-hoc signing for local development)
echo "[3/3] Signing app bundle..."

# Check if we have a developer identity, otherwise use ad-hoc
SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Apple Development" | head -1 | sed 's/.*"\(.*\)".*/\1/' || echo "")

if [ -n "$SIGNING_IDENTITY" ]; then
    echo "Using identity: $SIGNING_IDENTITY"
    codesign --force --sign "$SIGNING_IDENTITY" "$APP_DIR"
else
    echo "Using ad-hoc signing (no developer identity found)"
    codesign --force --sign - "$APP_DIR"
fi

echo ""
echo "=== Build Complete ==="
echo "App bundle: $APP_DIR"

# Install to Applications
echo ""
echo "Installing to /Applications..."

# Kill running instance if any
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

rm -rf "/Applications/$APP_NAME.app"
cp -R "$APP_DIR" /Applications/

echo "Installed to /Applications/$APP_NAME.app"
echo ""
echo "You can now launch BetterPasting from /Applications"
echo "Note: You may need to grant Input Monitoring permission in System Settings > Privacy & Security"
