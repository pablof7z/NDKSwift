# NDKSwift Documentation

Welcome to the NDKSwift documentation. This directory contains comprehensive guides and references for building Nostr applications with NDKSwift.

## 📚 Documentation Index

### Getting Started
- [Getting Started Guide](GETTING_STARTED.md) - Installation, setup, and your first Nostr app
- [API Reference](API_REFERENCE.md) - Complete API documentation for all classes and methods
- [Examples](EXAMPLES.md) - Practical code examples for common use cases

### Architecture & Design
- [Architecture Overview](ARCHITECTURE.md) - System design, patterns, and internals

### Feature Guides
- [NIP-44 Encryption Guide](NIP44_ENCRYPTION_GUIDE.md) - End-to-end encryption implementation
- [Signature Verification Sampling](SIGNATURE_VERIFICATION_SAMPLING.md) - Performance optimization for signature verification

## 🚀 Quick Links

- **New to NDKSwift?** Start with the [Getting Started Guide](GETTING_STARTED.md)
- **Looking for specific APIs?** Check the [API Reference](API_REFERENCE.md)
- **Need code examples?** Browse the [Examples](EXAMPLES.md)
- **Want to understand the internals?** Read the [Architecture Overview](ARCHITECTURE.md)

## 📝 Version

This documentation is for NDKSwift v0.6.1 and later.

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