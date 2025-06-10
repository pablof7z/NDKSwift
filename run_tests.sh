#!/bin/bash

echo "Building tests..."
swift build --target NDKSwiftTests

echo "Running BasicTests..."
swift test --filter BasicTests --parallel

echo "Done"