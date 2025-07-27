# NDKSwift Development Documentation

This directory contains technical documentation for developers working on NDKSwift itself, including implementation plans, technical analysis, and testing strategies.

## Contents

### Implementation Plans
- **[NIP-29 Implementation Plan](NIP-29-Implementation-Plan.md)** - Detailed plan for implementing community moderation features
- **[NIP-60/61 Implementation Plan](NIP-60-61-Implementation-Plan.md)** - Wallet protocol implementation with Cashu integration

### Technical Analysis
- **[Technical Debt](TECHNICAL_DEBT.md)** - Documentation of known technical debt, particularly around mint caching architecture
- **[Test Coverage Analysis](TEST_COVERAGE_ANALYSIS.md)** - Current test coverage report and gap analysis
- **[Test Implementation Plan](TEST_IMPLEMENTATION_PLAN.md)** - Comprehensive testing strategy and implementation roadmap

### Performance Testing
- **Large Subscription Performance Tests** - Tests for handling 10,000+ events and 100+ concurrent subscriptions
  - Located in `Tests/NDKSwiftTests/Unit/Subscription/LargeSubscriptionPerformanceTests.swift`
  - Validates performance goals: 2000+ events/second processing, <50MB memory increase for 10K events
  - Tests filter matching performance, cache lookup efficiency, and multi-subscription handling

## Purpose

These documents are intended for:
- Contributors working on NDKSwift core features
- Developers planning major feature additions
- Anyone interested in the technical roadmap and architecture decisions

## Contributing

When adding new development documentation:
1. Place implementation plans and technical specs in this directory
2. Update this README with a description of the new document
3. Keep documents focused on technical implementation details
4. User-facing documentation should go in the parent Documentation directory