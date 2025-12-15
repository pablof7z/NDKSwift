# NDKSwift Documentation

Welcome to the NDKSwift documentation. This directory contains comprehensive guides and references for building Nostr applications with NDKSwift.

## 📚 Documentation Index

### Getting Started
- [Getting Started Guide](GettingStarted/Guide.md) - Installation, setup, and your first Nostr app
- [Common Patterns](GettingStarted/CommonPatterns.md) - Practical examples and best practices for common tasks
- [API Reference](Reference/API.md) - Complete API documentation for all classes and methods
- [NDKSwiftUI Reference](Reference/NDKSwiftUI.md) - SwiftUI components and UI toolkit documentation

### Architecture & Design
- [Architecture Overview](Architecture/Overview.md) - System design, patterns, and internals
- [Nostr Protocol Guide](Architecture/NostrProtocol.md) - Comprehensive guide to the Nostr protocol
- [Local First Architecture](Architecture/LocalFirst.md) - Building offline-first Nostr apps
- [Optimistic Publishing](Architecture/OptimisticPublishing.md) - Fast event publishing with eventual consistency

### Feature Guides
- [Authentication](Guides/Authentication.md) - Complete guide to authentication, sessions, and multi-account support
- [Session Data Management](Guides/SessionData.md) - Reactive filters, follow lists, and web-of-trust
- [NIP-44 Encryption Guide](Guides/NIP44.md) - End-to-end encryption implementation
- [NIP-77 Implementation](Guides/NIP77.md) - Negentropy protocol for set reconciliation
- [NIP-92 Media Attachments](Guides/NIP92.md) - Media file handling and metadata
- [Signature Verification Sampling](Guides/SignatureSampling.md) - Performance optimization for signature verification
- [Relay Health Monitoring](Guides/RelayMonitoring.md) - Monitoring and managing relay connections
- [Profile Management](Guides/ProfileManagement.md) - User profile management with caching and real-time updates
- [Connection Error Rate Limiting](Guides/ConnectionErrorRateLimiting.md) - Handling connection errors and rate limiting

### Wallet Features
- [Cashu Retry Mechanism](Guides/CashuRetry.md) - Robust payment retry handling
- [NIP-60 Wallet Integration](Guides/NIP60Wallet.md) - Cashu wallet integration guide

### Advanced Topics
- [Negentropy Protocol](Architecture/Negentropy.md) - Set reconciliation algorithm
- [Negentropy Examples](Examples/Negentropy.md) - Practical negentropy use cases
- [Subscription Grouping Improvements](Guides/SubscriptionGroupingImprovements.md)
- [Subscription Grouping Metrics](Guides/SubscriptionGroupingMetrics.md)
- [Testing Subscription Grouping](Guides/TestingSubscriptionGrouping.md)

### Architecture Internals
Located in the [Architecture](Architecture/) subdirectory:
- [Outbox Caching](Architecture/OutboxCaching.md) - Efficient relay selection and caching
- [Profile Caching](Architecture/ProfileCaching.md) - User profile caching strategy

### Internals
Located in the [Internals](Internals/) subdirectory:
- [Outbox Model](Internals/Outbox.md) - Deep dive into the outbox implementation
- [NIP-60 Deletion Tag Fix](Internals/NIP60DelTagFix.md) - Handling event deletions in wallets

### Examples
Located in the [Examples](Examples/) subdirectory:
- [Markdown Rendering](Examples/MARKDOWN_RENDERING.md) - Rendering Nostr content with markdown

### Development Resources
Located in the [Development](Development/) subdirectory:
- [Development README](Development/README.md) - Developer guide and contribution guidelines
- [Testing Plan](Development/TestingPlan.md) - Testing strategy and plan
- [NIP-29 Implementation Plan](Development/NIP-29-Implementation-Plan.md) - Community moderation implementation

### Meta
- [Expert Prompt](Meta/ExpertPrompt.md) - Instructions for AI assistants
- [Expert Knowledge Pack](Meta/ExpertKnowledgePack.md) - Knowledge pack for AI assistants

## 🚀 Quick Links

- **New to NDKSwift?** Start with the [Getting Started Guide](GettingStarted/Guide.md)
- **Looking for specific APIs?** Check the [API Reference](Reference/API.md)
- **Building SwiftUI apps?** See the [NDKSwiftUI Reference](Reference/NDKSwiftUI.md)
- **Need code examples?** Browse the [Examples](../Examples/)
- **Want to understand the internals?** Read the [Architecture Overview](Architecture/Overview.md)

## 📝 Version

This documentation is for NDKSwift v0.10.0 and later.
NDKSwiftUI documentation covers v0.2.0 and later.

## 🔧 Running Examples

The [Examples](../Examples/) directory contains runnable demos:

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
