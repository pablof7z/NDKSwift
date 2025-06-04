#!/bin/bash
# Build script for iOS Nostr App

echo "Building iOS Nostr App..."

# Navigate to Examples directory
cd "$(dirname "$0")"

# Clean build
echo "Cleaning..."
xcodebuild -scheme iOSNostrApp clean

# Build for iOS Simulator
echo "Building for iOS Simulator..."
xcodebuild -scheme iOSNostrApp \
           -destination 'generic/platform=iOS Simulator' \
           build

# Check if build succeeded
if [ $? -eq 0 ]; then
    echo "✅ Build succeeded!"
    echo "App location: ~/Library/Developer/Xcode/DerivedData/iOSNostrApp-*/Build/Products/Debug-iphonesimulator/iOSNostrApp.app"
else
    echo "❌ Build failed!"
    exit 1
fi