# QR Code Standardization Summary

## Overview
Implemented a reusable QR code generation utility to standardize QR code functionality across the NutsackiOS wallet application.

## Changes Made

### 1. Created Reusable QR Code Utility (`QRCodeGenerator.swift`)
- **QRCodeGenerator**: Static utility for generating QR code images from strings
  - Cross-platform support (iOS/macOS)
  - Uses Core Image filters with medium error correction
  - Configurable scale factor
  
- **QRCodeView**: SwiftUI view component for displaying QR codes
  - Customizable size, background color, and corner radius
  - Fallback UI for generation failures
  - Consistent styling across the app

- **QRCodeDisplayView**: Full-screen QR code presentation view
  - Includes copy functionality
  - Consistent navigation and toolbar styling
  - Animated copy confirmation

### 2. Updated Existing Views
- **MintView.swift**: Refactored to use `QRCodeView` component
- **SendView.swift**: Refactored to use `QRCodeView` component
- Removed duplicate QR generation code from both views

### 3. Enhanced NutzapView
- Added QR scanner button for recipient input
- Integrated with existing QRScannerView
- Supports scanning npub, hex pubkeys, or NIP-05 identifiers

## Benefits
1. **Code Reusability**: Eliminated duplicate QR generation code
2. **Consistency**: Uniform QR code appearance and behavior across all views
3. **Maintainability**: Single source of truth for QR code generation
4. **Extensibility**: Easy to add QR codes to new views using the reusable components
5. **Cross-Platform**: Works seamlessly on both iOS and macOS

## Usage Example
```swift
// Simple QR code display
QRCodeView(content: "bitcoin:bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh")

// Full-screen QR with copy functionality
.qrCodeSheet(for: invoice, title: "Lightning Invoice", isPresented: $showQR)
```