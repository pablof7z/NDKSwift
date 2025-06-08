#!/bin/bash

# Script to migrate from old NDKError enum to new NDKError struct

echo "Migrating NDKError enum to NDKError struct..."

# First, let's create a backup of the current state
echo "Creating backup..."
cp -r Sources Sources.backup
cp -r Tests Tests.backup

# Function to perform replacements
migrate_file() {
    local file="$1"
    echo "Migrating: $file"
    
    # Use sed to perform replacements
    # Note: On macOS, use sed -i '' for in-place editing
    
    # Validation errors
    sed -i '' 's/throw NDKError\.invalidPublicKey/throw NDKError.validation("invalid_public_key", "Invalid public key format")/g' "$file"
    sed -i '' 's/throw NDKError\.invalidPrivateKey/throw NDKError.validation("invalid_private_key", "Invalid private key format")/g' "$file"
    sed -i '' 's/throw NDKError\.invalidEventID/throw NDKError.validation("invalid_event_id", "Invalid event ID")/g' "$file"
    sed -i '' 's/throw NDKError\.invalidSignature/throw NDKError.validation("invalid_signature", "Invalid signature")/g' "$file"
    sed -i '' 's/throw NDKError\.invalidFilter/throw NDKError.validation("invalid_filter", "Invalid filter configuration")/g' "$file"
    sed -i '' 's/throw NDKError\.invalidInput(\([^)]*\))/throw NDKError.validation("invalid_input", \1)/g' "$file"
    sed -i '' 's/throw NDKError\.invalidEvent(\([^)]*\))/throw NDKError.validation("invalid_event", \1)/g' "$file"
    sed -i '' 's/throw NDKError\.validation(\([^)]*\))/throw NDKError.validation("validation_error", \1)/g' "$file"
    sed -i '' 's/throw NDKError\.invalidPaymentRequest/throw NDKError.validation("invalid_payment_request", "Invalid payment request")/g' "$file"
    sed -i '' 's/throw NDKError\.insufficientBalance/throw NDKError.validation("insufficient_balance", "Insufficient balance")/g' "$file"
    
    # Crypto errors
    sed -i '' 's/throw NDKError\.signingFailed/throw NDKError.crypto("signing_failed", "Failed to sign event")/g' "$file"
    sed -i '' 's/throw NDKError\.verificationFailed/throw NDKError.crypto("verification_failed", "Failed to verify signature")/g' "$file"
    sed -i '' 's/throw NDKError\.powGenerationFailed/throw NDKError.crypto("pow_generation_failed", "Failed to generate proof of work")/g' "$file"
    sed -i '' 's/throw NDKError\.signerError(\([^)]*\))/throw NDKError.crypto("signer_error", \1)/g' "$file"
    
    # Network errors
    sed -i '' 's/throw NDKError\.relayConnectionFailed(\([^)]*\))/throw NDKError.network("connection_failed", \1)/g' "$file"
    sed -i '' 's/throw NDKError\.subscriptionFailed(\([^)]*\))/throw NDKError.network("subscription_failed", \1)/g' "$file"
    sed -i '' 's/throw NDKError\.timeout/throw NDKError.network("timeout", "Operation timed out")/g' "$file"
    
    # Storage errors
    sed -i '' 's/throw NDKError\.cacheFailed(\([^)]*\))/throw NDKError.storage("cache_failed", \1)/g' "$file"
    
    # Configuration errors
    sed -i '' 's/throw NDKError\.walletNotConfigured/throw NDKError.configuration("wallet_not_configured", "Wallet not configured")/g' "$file"
    
    # Runtime errors
    sed -i '' 's/throw NDKError\.notImplemented/throw NDKError.runtime("not_implemented", "Feature not implemented")/g' "$file"
    sed -i '' 's/throw NDKError\.cancelled/throw NDKError.runtime("cancelled", "Operation was cancelled")/g' "$file"
    sed -i '' 's/throw NDKError\.custom(\([^)]*\))/throw NDKError.runtime("custom", \1)/g' "$file"
    
    # Also handle case statements
    sed -i '' 's/case \.invalidPublicKey:/case let error where error.code == "invalid_public_key":/g' "$file"
    sed -i '' 's/case \.invalidPrivateKey:/case let error where error.code == "invalid_private_key":/g' "$file"
    sed -i '' 's/case \.invalidEventID:/case let error where error.code == "invalid_event_id":/g' "$file"
    sed -i '' 's/case \.invalidSignature:/case let error where error.code == "invalid_signature":/g' "$file"
    sed -i '' 's/case \.signingFailed:/case let error where error.code == "signing_failed":/g' "$file"
    sed -i '' 's/case \.verificationFailed:/case let error where error.code == "verification_failed":/g' "$file"
    sed -i '' 's/case \.timeout:/case let error where error.code == "timeout":/g' "$file"
    sed -i '' 's/case \.cancelled:/case let error where error.code == "cancelled":/g' "$file"
    sed -i '' 's/case \.notImplemented:/case let error where error.code == "not_implemented":/g' "$file"
    
    # Replace NDKUnifiedError with NDKError
    sed -i '' 's/NDKUnifiedError/NDKError/g' "$file"
}

# List of files to migrate
files=(
    "Sources/NDKSwift/Core/NDK.swift"
    "Sources/NDKSwift/Core/NDKOutbox.swift"
    "Sources/NDKSwift/Core/NDKProfileManager.swift"
    "Sources/NDKSwift/Models/NDKEvent.swift"
    "Sources/NDKSwift/Models/NDKRelay.swift"
    "Sources/NDKSwift/Models/NDKUser.swift"
    "Sources/NDKSwift/Models/Kinds/NDKContactList.swift"
    "Sources/NDKSwift/Models/Kinds/NDKList.swift"
    "Sources/NDKSwift/Models/Kinds/NDKRelayList.swift"
    "Sources/NDKSwift/Relay/NDKRelayConnection.swift"
    "Sources/NDKSwift/Relay/NostrMessage.swift"
    "Sources/NDKSwift/Signers/NDKBunkerSigner.swift"
    "Sources/NDKSwift/Signers/NDKNostrRPC.swift"
    "Sources/NDKSwift/Signers/NDKPrivateKeySigner.swift"
    "Sources/NDKSwift/Utils/JSONCoding.swift"
    "Sources/NDKSwift/Utils/NostrIdentifier.swift"
    "Sources/NDKSwift/Utils/RetryPolicy.swift"
    "Sources/NDKSwift/Wallet/NDKCashuWallet.swift"
    "Sources/NDKSwift/Wallet/NDKPaymentRouter.swift"
    "Sources/NDKSwift/Blossom/NDKBlossomExtensions.swift"
    "Sources/NDKSwift/Outbox/NDKEventExtensions.swift"
    "Sources/NDKSwift/Subscription/NDKSubscriptionBuilder.swift"
    "Tests/NDKSwiftTests/Models/NDKEventTests.swift"
    "Tests/NDKSwiftTests/Models/NDKEventReactionTests.swift"
    "Tests/NDKSwiftTests/Models/NDKRelayTests.swift"
    "Tests/NDKSwiftTests/Models/NDKUserTests.swift"
    "Tests/NDKSwiftTests/Signers/NDKPrivateKeySignerTests.swift"
    "Tests/NDKSwiftTests/TestUtilities/MockObjects.swift"
    "Tests/NDKSwiftTests/Utils/NostrIdentifierTests.swift"
    "Tests/NDKSwiftTests/Utils/RetryPolicyTests.swift"
)

# Migrate each file
for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        migrate_file "$file"
    else
        echo "Warning: File not found: $file"
    fi
done

echo "Migration complete!"
echo "Backup created in Sources.backup and Tests.backup"
echo ""
echo "Next steps:"
echo "1. Remove the old NDKError enum from Sources/NDKSwift/Core/Types.swift (lines 116-189)"
echo "2. Delete Sources/NDKSwift/Utils/UnifiedErrors.swift"
echo "3. Delete Sources/NDKSwift/Utils/ErrorMigrationHelpers.swift"
echo "4. Delete Tests/NDKSwiftTests/Utils/UnifiedErrorsTests.swift"
echo "5. Run tests to verify everything works"