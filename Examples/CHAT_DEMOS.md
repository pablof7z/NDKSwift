# Nostr Chat Demos

This directory contains two NIP-44 encrypted chat applications demonstrating secure messaging on Nostr.

## SecureChatCLI

A simple, straightforward CLI chat application using NIP-44 encryption.

### Features
- NIP-44 encryption for all messages
- Auto-generate identity or use existing nsec
- Real-time bidirectional messaging
- Multi-relay support
- Basic commands (/quit, /status, /clear)

### Usage
```bash
# Run directly
swift Examples/SecureChatCLI.swift

# Or build and run
cd Examples
swift build
.build/debug/SecureChatCLI
```

### Example Session
```
🔐 Nostr Secure Chat (NIP-44 Encrypted)
     Kind 9999 Messages

🔑 User Setup
─────────────
Enter your nsec (or press Enter to generate new identity):
> [Enter for new identity]

👤 Recipient Setup
──────────────────
Enter recipient's npub:
> npub1234567890abcdef...

[You] Hello there!
[12:34] <alice123...> Hi! How are you?
[You] Great! This is encrypted with NIP-44!
```

## MircStyleChat

A more advanced mIRC-inspired chat client with colored output and enhanced features.

### Features
- Full-color mIRC-style interface
- Message history (last 24 hours)
- Nickname support
- Sound notifications (bell)
- Advanced commands
- Beautiful ASCII art banner
- Real-time status updates

### Usage
```bash
# Run directly
swift Examples/MircStyleChat.swift

# Or build and run
cd Examples
swift build
.build/debug/MircStyleChat
```

### Commands
- `/quit`, `/q` - Exit the chat
- `/status`, `/s` - Show relay connection status
- `/clear`, `/cls` - Clear and redraw screen
- `/history` - Show message count
- `/help`, `/?` - Show help

### Example Session
```
╔══════════════════════════════════════════════════════════════════╗
║       _   _  ___  ____ _____ ____     ____ _   _    _  _____    ║
║      | \ | |/ _ \/ ___|_   _|  _ \   / ___| | | |  / \|_   _|   ║
║      |  \| | | | \___ \ | | | |_) | | |   | |_| | / _ \ | |     ║
║      | |\  | |_| |___) || | |  _ <  | |___|  _  |/ ___ \| |     ║
║      |_| \_|\___/|____/ |_| |_| \_\  \____|_| |_/_/   \_\_|     ║
║                                                                  ║
║              🔐 NIP-44 Encrypted • Kind 9999 Events             ║
╚══════════════════════════════════════════════════════════════════╝

 NOSTR CHAT v1.0 - Secure Messaging 
─────────────────────────────────────────────────────────────────────
● You: npub1yourpubkey...
● Chatting with: Alice (npub1alicepubkey...)
─────────────────────────────────────────────────────────────────────

[12:34] <You> Hey Alice!
[12:34] <Alice> Hi! Nice chat client!
[12:35] <You> Thanks! It's using NIP-44 encryption

> _
```

## Technical Details

Both chat applications use:
- **Kind 9999**: Custom event kind for encrypted chat messages
- **NIP-44 Encryption**: Modern encryption standard with ChaCha20
- **Tags**: 
  - `["p", "<recipient_pubkey>"]` - Identifies the recipient
  - `["encrypted", "nip44"]` - Indicates encryption method

## Security Notes

1. **Private Keys**: Your nsec is your identity. Keep it secure!
2. **Encryption**: All messages are end-to-end encrypted using NIP-44
3. **Metadata**: Timestamps and recipient pubkeys are visible on relays
4. **Forward Secrecy**: NIP-44 does not provide forward secrecy

## Running the Examples

### Prerequisites
- Swift 5.9 or later
- macOS 12.0 or later
- Internet connection for relay access

### Quick Start
```bash
# Clone the repository
git clone <repo-url>
cd NDKSwift

# Run the simple chat
swift Examples/SecureChatCLI.swift

# Or run the mIRC-style chat
swift Examples/MircStyleChat.swift
```

### Building Executables
```bash
cd Examples
swift build -c release

# Executables will be in .build/release/
.build/release/SecureChatCLI
.build/release/MircStyleChat
```

## Customization

You can modify these examples to:
- Use different event kinds
- Add file sharing with Blossom
- Implement group chats
- Add message reactions
- Create a GUI version

## Troubleshooting

- **Can't connect to relays**: Check your internet connection
- **Messages not appearing**: Ensure both parties are using the same event kind
- **Decryption errors**: Verify you're using the correct nsec/npub pairs
- **No history**: Messages older than 24 hours are not loaded by default