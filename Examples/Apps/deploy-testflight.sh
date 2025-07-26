#!/bin/bash

# TestFlight deployment script for NDKSwift iOS apps
# Usage: ./deploy-testflight.sh [AppName]

set -e

# Configuration
API_KEY_ID="6VZ4NHWMQN"
API_ISSUER_ID="0acdb473-8d3f-4eba-85bc-d2de82234bea"
API_KEY_PATH="$HOME/.appstoreconnect/AuthKey_6VZ4NHWMQN.p8"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Check if app name is provided
if [ -z "$1" ]; then
    print_error "Please provide an app name"
    echo "Available apps:"
    ls -d */ | grep -v "ExportOptions" | sed 's/\///'
    exit 1
fi

APP_NAME="$1"
APP_DIR="$APP_NAME"

# Check if app directory exists
if [ ! -d "$APP_DIR" ]; then
    print_error "App directory '$APP_DIR' not found"
    exit 1
fi

# Check if API key exists
if [ ! -f "$API_KEY_PATH" ]; then
    print_error "API key not found at $API_KEY_PATH"
    exit 1
fi

cd "$APP_DIR"

print_status "Starting TestFlight deployment for $APP_NAME"

# Step 1: Refresh project
if [ -f "./refresh-project.sh" ]; then
    print_status "Refreshing Xcode project..."
    ./refresh-project.sh
else
    print_warning "No refresh-project.sh found, skipping project refresh"
fi

# Step 2: Clean build directory
print_status "Cleaning build directory..."
rm -rf build/

# Step 3: Archive the app
print_status "Building archive..."
xcodebuild archive \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -archivePath "build/$APP_NAME.xcarchive" \
    -destination "generic/platform=iOS" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="456SHKPP26" \
    | xcbeautify

# Check if archive was created
if [ ! -d "build/$APP_NAME.xcarchive" ]; then
    print_error "Archive creation failed"
    exit 1
fi

# Step 4: Export IPA
print_status "Exporting IPA..."
xcodebuild -exportArchive \
    -archivePath "build/$APP_NAME.xcarchive" \
    -exportPath "build" \
    -exportOptionsPlist "../ExportOptions-TestFlight.plist" \
    | xcbeautify

# Check if IPA was created
IPA_FILE=$(find build -name "*.ipa" -type f | head -1)
if [ -z "$IPA_FILE" ]; then
    print_error "IPA export failed"
    exit 1
fi

print_status "IPA created: $IPA_FILE"

# Step 5: Upload to TestFlight
print_status "Uploading to TestFlight..."
xcrun altool --upload-app \
    -f "$IPA_FILE" \
    -t ios \
    --apiKey "$API_KEY_ID" \
    --apiIssuer "$API_ISSUER_ID" \
    --verbose

print_status "TestFlight deployment complete for $APP_NAME!"
print_status "The build will be available in TestFlight after processing (usually 5-10 minutes)"

# Clean up (optional)
# rm -rf build/