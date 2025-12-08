#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Generating Xcode project..."
xcodegen generate

echo "Project generated successfully!"
