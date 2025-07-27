# NDKSwift Documentation

Welcome to the NDKSwift documentation. This directory contains comprehensive guides and references for building Nostr applications with NDKSwift.

## 📚 Documentation Index

### Getting Started
- [Getting Started Guide](GETTING_STARTED.md) - Installation, setup, and your first Nostr app
- [API Reference](API_REFERENCE.md) - Complete API documentation for all classes and methods
- [NDKSwiftUI Reference](NDKSWIFTUI_REFERENCE.md) - SwiftUI components and UI toolkit documentation

### Architecture & Design
- [Architecture Overview](ARCHITECTURE.md) - System design, patterns, and internals
- [Nostr Protocol Guide](NOSTR_PROTOCOL_GUIDE.md) - Comprehensive guide to the Nostr protocol
- [Local First Architecture](LOCAL_FIRST.md) - Building offline-first Nostr apps
- [Optimistic Publishing](OPTIMISTIC_PUBLISHING.md) - Fast event publishing with eventual consistency

### Feature Guides
- [Authentication Guide](AUTHENTICATION.md) - Complete guide to authentication, sessions, and multi-account support
- [Session Data Management](SESSION_DATA_MANAGEMENT.md) - Reactive filters, follow lists, and web-of-trust
- [NIP-44 Encryption Guide](NIP44_ENCRYPTION_GUIDE.md) - End-to-end encryption implementation
- [NIP-77 Implementation](NIP77Implementation.md) - Negentropy protocol for set reconciliation
- [NIP-92 Media Attachments](NIP92_MEDIA_ATTACHMENTS.md) - Media file handling and metadata
- [Signature Verification Sampling](SIGNATURE_VERIFICATION_SAMPLING.md) - Performance optimization for signature verification
- [Relay Health Monitoring](RELAY_HEALTH_MONITORING.md) - Monitoring and managing relay connections
- [Reactive Profiles](ReactiveProfiles.md) - Real-time profile updates and caching

### Wallet Features
- [Cashu Retry Mechanism](CASHU_RETRY_MECHANISM.md) - Robust payment retry handling
- [API Reference - Cashu Retry](API_REFERENCE_CASHU_RETRY.md) - Cashu retry API documentation

### Advanced Topics
- [Negentropy Protocol](Negentropy.md) - Set reconciliation algorithm
- [Negentropy Examples](NegentropyExamples.md) - Practical negentropy use cases
- [NIP-60 Deletion Tag Fix](NIP60_DEL_TAG_FIX.md) - Handling event deletions in wallets

### Architecture Internals
Located in the [Architecture](Architecture/) subdirectory:
- [Outbox Caching](Architecture/OutboxCaching.md) - Efficient relay selection and caching
- [Profile Caching](Architecture/ProfileCaching.md) - User profile caching strategy

### Internals
Located in the [Internals](Internals/) subdirectory:
- [Outbox Model](Internals/Outbox.md) - Deep dive into the outbox implementation

### Examples
Located in the [Examples](Examples/) subdirectory:
- [Markdown Rendering](Examples/MARKDOWN_RENDERING.md) - Rendering Nostr content with markdown

### Development Resources
Located in the [Development](Development/) subdirectory:
- [Development README](Development/README.md) - Developer guide and contribution guidelines
- [NIP-29 Implementation Plan](Development/NIP-29-Implementation-Plan.md) - Community moderation implementation

## 🚀 Quick Links

- **New to NDKSwift?** Start with the [Getting Started Guide](GETTING_STARTED.md)
- **Looking for specific APIs?** Check the [API Reference](API_REFERENCE.md)
- **Building SwiftUI apps?** See the [NDKSwiftUI Reference](NDKSWIFTUI_REFERENCE.md)
- **Need code examples?** Browse the [Examples](EXAMPLES.md)
- **Want to understand the internals?** Read the [Architecture Overview](ARCHITECTURE.md)

## 📝 Version

This documentation is for NDKSwift v0.6.2 and later.
NDKSwiftUI documentation covers v0.2.0 and later.

## 🔧 Running Examples

The [Examples directory](../Examples/) contains runnable demos:

```bash
# Run standalone demo (no compilation needed)
swift Examples/StandaloneDemo.swift

# Run compiled examples
swift run --package-path Examples SimpleDemo
swift run --package-path Examples NWCDemo
swift run --package-path Examples BlossomDemo
```

## 🤝 Contributing

To contribute to the documentation:

1. Follow the existing documentation style
2. Include code examples where appropriate
3. Keep examples up-to-date with the latest API
4. Test all code examples before submitting

## 📄 License

NDKSwift is released under the MIT License. See [LICENSE](../LICENSE) for details.