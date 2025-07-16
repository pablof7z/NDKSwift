# Logout Fix: Complete Authentication Data Cleanup

## Problem
When users signed out in the NutsackiOS app, they were immediately taken back to the "Welcome back" screen and could re-login without entering credentials. This was because the logout implementation only did a "soft logout" that cleared the active session but preserved all session data in keychain storage.

## Root Cause
The `NDKAuthManager.logout()` method is designed for soft logout behavior:
- It clears the active session (`activeSession = nil`)
- It marks all sessions as inactive
- But it **does not** delete sessions from keychain storage
- This allows users to switch back to sessions without re-authentication

## Solution
Updated the logout implementation to perform a **complete logout** that clears all stored authentication data:

### 1. NostrManager.logout() Changes
```swift
func logout() {
    // Clear all cached data
    Task {
        if let cache = cache {
            try? await cache.clear()
            print("Cleared all cached data")
        }
    }
    
    // Clear all sessions from keychain to prevent "Welcome back" scenario
    for session in ndkAuthManager.availableSessions {
        try? ndkAuthManager.deleteSession(session)
    }
    
    // Clear active authentication state
    ndkAuthManager.logout()
    
    // Clear NDK signer
    ndk?.signer = nil
    
    print("Logged out and cleared all authentication data")
}
```

### 2. WalletManager.clearWalletData() Addition
```swift
func clearWalletData() {
    // Cancel active subscriptions
    walletEventTask?.cancel()
    walletEventTask = nil
    
    Task {
        await historySubscription?.close()
        historySubscription = nil
    }
    
    // Clear wallet state
    activeWallet = nil
    transactions.removeAll()
    availableMints.removeAll()
    currentBalance = 0
    
    print("WalletManager - Cleared all wallet data and cancelled subscriptions")
}
```

### 3. SettingsView.logout() Updates
```swift
private func logout() {
    // Clear wallet data and cancel subscriptions
    walletManager.clearWalletData()
    
    // Clear authentication data
    nostrManager.logout()
    
    // Clear local state
    currentUser = nil
    userProfile = nil
}
```

## What Gets Cleared
The complete logout now clears:

1. **Authentication Data**:
   - All sessions from keychain storage
   - Active session and signer
   - NDK signer reference

2. **Cache Data**:
   - All events from SQLite cache
   - User profiles
   - Mint information
   - Keysets
   - Decrypted content
   - Database compaction (VACUUM)

3. **Wallet Data**:
   - Active wallet instance
   - Transaction history
   - Available mints list
   - Current balance
   - Active subscriptions

4. **UI State**:
   - Current user reference
   - User profile data

## Result
After logout, users will:
- Be taken to the initial login screen
- Need to re-enter their credentials or create a new account
- Not see any cached data from the previous session
- Have all background subscriptions properly cancelled

## Testing
- Build verification: ✅ The app builds successfully
- Logout flow: Users will now need to re-authenticate after logout
- Memory management: Active subscriptions are properly cancelled
- Data privacy: All user data is cleared from storage