#!/bin/bash
# Interactive demo of the iOS Nostr App functionality

echo "📱 iOS Nostr App Interactive Demo"
echo "================================="
echo ""
echo "This demonstrates the iOS app functionality with automated inputs"
echo ""

# Create account and test basic functionality
(
  echo "1"        # Create Account
  sleep 2
  echo "1"        # Show Account Info
  sleep 1
  echo "2"        # Publish Message
  echo "Hello from the iOS app demo! 🎉"
  sleep 2
  echo "4"        # Show Relay Status
  sleep 1
  echo "5"        # Exit
) | swift run iOSAppDemo 2>/dev/null | grep -v "warning:"

echo ""
echo "✅ Demo completed!"
echo ""
echo "To run the full iOS app with SwiftUI interface:"
echo "1. Open Xcode"
echo "2. Create new iOS App project"  
echo "3. Add NDKSwift as local package dependency"
echo "4. Copy iOSNostrApp files (ContentView.swift, NostrViewModel.swift)"
echo "5. Run on simulator/device"