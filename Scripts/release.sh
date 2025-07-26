#!/bin/bash

# NDKSwift Release Script
# This script helps prepare and create a new release

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

# Check if we're in the root directory
if [ ! -f "Package.swift" ]; then
    print_error "Please run this script from the root of the NDKSwift repository"
    exit 1
fi

# Get current version
CURRENT_VERSION=$(cat VERSION)
print_info "Current version: $CURRENT_VERSION"

# Ask for new version
echo -n "Enter new version (format: X.Y.Z): "
read NEW_VERSION

# Validate version format
if ! [[ "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    print_error "Invalid version format. Please use X.Y.Z format (e.g., 0.2.0)"
    exit 1
fi

# Compare versions
IFS='.' read -ra CURRENT_PARTS <<< "$CURRENT_VERSION"
IFS='.' read -ra NEW_PARTS <<< "$NEW_VERSION"

if [ "${NEW_PARTS[0]}" -lt "${CURRENT_PARTS[0]}" ] || \
   ([ "${NEW_PARTS[0]}" -eq "${CURRENT_PARTS[0]}" ] && [ "${NEW_PARTS[1]}" -lt "${CURRENT_PARTS[1]}" ]) || \
   ([ "${NEW_PARTS[0]}" -eq "${CURRENT_PARTS[0]}" ] && [ "${NEW_PARTS[1]}" -eq "${CURRENT_PARTS[1]}" ] && [ "${NEW_PARTS[2]}" -le "${CURRENT_PARTS[2]}" ]); then
    print_error "New version must be greater than current version"
    exit 1
fi

print_status "Version validation passed"

# Check for uncommitted changes
if ! git diff-index --quiet HEAD --; then
    print_warning "You have uncommitted changes. Please commit or stash them before releasing."
    exit 1
fi

# Update VERSION file
echo "$NEW_VERSION" > VERSION
print_status "Updated VERSION file"

# Check if there are unreleased changes in CHANGELOG
if ! grep -q "## \[Unreleased\]" CHANGELOG.md; then
    print_error "No unreleased changes found in CHANGELOG.md"
    print_info "Please update CHANGELOG.md with your changes before releasing"
    exit 1
fi

# Update CHANGELOG.md
print_info "Updating CHANGELOG.md..."
DATE=$(date +"%Y-%m-%d")
sed -i '' "s/## \[Unreleased\]/## \[Unreleased\]\n\n## \[$NEW_VERSION\] - $DATE/" CHANGELOG.md
print_status "Updated CHANGELOG.md"

# Run tests
print_info "Running tests..."
swift test --parallel
print_status "All tests passed"

# Build release
print_info "Building release..."
swift build -c release
print_status "Release build successful"

# Commit changes
git add VERSION CHANGELOG.md
git commit -m "Release version $NEW_VERSION"
print_status "Committed version changes"

# Create and push tag
git tag -a "v$NEW_VERSION" -m "Release version $NEW_VERSION"
print_status "Created tag v$NEW_VERSION"

# Ask to push
echo -n "Push changes and tag to origin? (y/n): "
read PUSH_CONFIRM

if [ "$PUSH_CONFIRM" = "y" ]; then
    git push origin main
    git push origin "v$NEW_VERSION"
    print_status "Pushed to origin"
    print_info "GitHub Actions will now create the release"
else
    print_warning "Changes not pushed. To push manually, run:"
    print_info "  git push origin main"
    print_info "  git push origin v$NEW_VERSION"
fi

print_status "Release preparation complete!"