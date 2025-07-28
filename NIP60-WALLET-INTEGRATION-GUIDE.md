# NIP-60 Wallet Integration Guide: Lessons from Real-World Implementations

This guide presents architectural patterns and anti-patterns learned from analyzing production Nostr wallet applications. It addresses critical mistakes commonly made when integrating NIP-60 wallets with NDKSwift, particularly around reactive state management and data flow architecture.

## Table of Contents

1. [The Fundamental Architecture Question](#the-fundamental-architecture-question)
2. [Understanding NIP-60 Data Types](#understanding-nip-60-data-types)
3. [The Cache vs Compute Decision Framework](#the-cache-vs-compute-decision-framework)
4. [Reactive vs Direct Access Patterns](#reactive-vs-direct-access-patterns)
5. [Configuration vs Transactional Data](#configuration-vs-transactional-data)
6. [Common Anti-Patterns and Solutions](#common-anti-patterns-and-solutions)
7. [Recommended Architecture Patterns](#recommended-architecture-patterns)
8. [Testing Your Implementation](#testing-your-implementation)

---

## The Fundamental Architecture Question

**Should wallet managers cache wallet data or access it directly?**

This seemingly simple question reveals a fundamental misunderstanding of NIP-60 wallet architecture. The answer depends entirely on **what type of data** you're dealing with and **where it comes from**.

### Key Insight: NDKSwift's NIP60Wallet is NOT a Remote API

Many developers mistakenly treat `NIP60Wallet` like a remote service that requires caching for performance. **This is wrong.** The NIP60Wallet is a local state manager that:

- Computes balance from in-memory proof state (synchronous operation)
- Maintains transaction history in local storage
- Calculates mint configurations from cached Nostr events

**Performance is not a reason to cache wallet data in a wrapper layer.**

---

## Understanding NIP-60 Data Types

### 1. **Computed Values** (Never Cache These)
```swift
// Balance: Sum of available proof amounts
public func getTotalBalance() -> Int64 {  // Note: NOT async!
    let availableProofs = proofState.values.filter { $0.state == .available }
    return availableProofs.reduce(0) { $0 + Int64($1.proof.amount) }
}

// Transaction list: Queried from local storage
public func getRecentTransactions(limit: Int) -> [WalletTransaction] {
    return await transactionHistory.getAllTransactions().prefix(limit)
}

// Mint URLs: Extracted from NIP-60 configuration events
public func getMintURLs() -> [String] {
    return currentWalletConfiguration.mints
}
```

**Why never cache:** These are calculations/queries over the source of truth, not expensive operations.

### 2. **Source of Truth Data** (This Gets Cached by NDKSwift)
```swift
// Proof state (managed internally by ProofStateManager)
private var proofState: [String: ProofEntry] = [:]

// Transaction history (managed internally by WalletTransactionHistory)  
private var transactionStore: [WalletTransaction] = []

// Configuration events (cached by NDK's cache layer)
// Kind 17375 wallet configuration events
```

**Why NDKSwift caches this:** These are the actual data that everything else derives from.

---

## The Cache vs Compute Decision Framework

Use this framework to decide whether to cache data in your app layer:

### ✅ **Cache When:**
- Data requires expensive network calls
- Data changes infrequently relative to access frequency  
- Computing the data is expensive (complex algorithms, large datasets)
- The data has no single source of truth

### ❌ **Don't Cache When:**
- Data is computed from local state (like balance from proofs)
- The computation is trivial (sum, count, filter)
- You're not the source of truth (another component owns the data)
- The data changes frequently

### **Examples Applied to NIP-60:**

```swift
// ❌ DON'T CACHE: Balance is computed from local proof state
@Published var currentBalance: Int64 = 0  // WRONG!

// ✅ COMPUTE ON-DEMAND: Balance is a trivial calculation
var currentBalance: Int64 {
    get async {
        guard let wallet = wallet else { return 0 }
        return (try? await wallet.getBalance()) ?? 0
    }
}

// ❌ DON'T CACHE: Mint URLs come from cached Nostr events  
@Published var mintURLs: [String] = []  // WRONG!

// ✅ ACCESS DIRECTLY: Configuration is already cached by NDK
func getActiveMintURLs() async -> [String] {
    guard let wallet = wallet else { return [] }
    return await wallet.mints.getMintURLs()
}
```

---

## Reactive vs Direct Access Patterns

### The Modern Pattern: UI-Level Reactivity

**Instead of caching in managers, let UI components manage their own state:**

```swift
// ❌ OLD PATTERN: Manager caches everything
@MainActor
class WalletManager: ObservableObject {
    @Published var currentBalance: Int64 = 0      // Cached computed value
    @Published var recentTransactions: [Transaction] = []  // Cached query result
    @Published var mintURLs: [String] = []        // Cached configuration
}

// ✅ NEW PATTERN: Manager is thin, UI handles reactivity
@MainActor
class WalletManager: ObservableObject {
    @Published var wallet: NIP60Wallet?
    @Published var isLoading = false
    @Published var error: Error?
    
    // Direct access - no caching
    var currentBalance: Int64 {
        get async {
            guard let wallet = wallet else { return 0 }
            return (try? await wallet.getBalance()) ?? 0
        }
    }
}

// UI manages its own reactive state
struct WalletView: View {
    @ObservedObject var walletManager: WalletManager
    @State private var balance: Int64 = 0
    @State private var transactions: [Transaction] = []
    
    var body: some View {
        VStack {
            Text("\(balance) sats")
            TransactionList(transactions: transactions)
        }
        .task {
            await refreshData()
        }
        .refreshable {
            await refreshData()
        }
    }
    
    private func refreshData() async {
        async let newBalance = walletManager.currentBalance
        async let newTransactions = walletManager.wallet?.getRecentTransactions(limit: 50) ?? []
        
        balance = await newBalance
        transactions = await newTransactions
    }
}
```

---

## Configuration vs Transactional Data

This is the most critical distinction for NIP-60 wallets:

### Configuration Data: Local State + Manual Save Pattern

**Why:** NIP-60 stores wallet config as Nostr events. Frequent updates = event spam.

```swift
// ✅ CORRECT: Local editing with batch save
struct MintManagementView: View {
    @State private var editableMints: [MintInfo] = []  // Local editing state
    @State private var hasUnsavedChanges = false
    
    var body: some View {
        List {
            ForEach(editableMints) { mint in
                MintRow(mint: mint, onRemove: { removeMintLocally(mint) })
            }
        }
        .toolbar {
            Button("Save") {
                Task { await saveAllChanges() }  // Single NIP-60 event
            }
            .disabled(!hasUnsavedChanges)
        }
        .onAppear {
            await loadCurrentConfiguration()  // Load from wallet
        }
    }
    
    private func saveAllChanges() async {
        let mintURLs = editableMints.map { $0.url.absoluteString }
        try await walletManager.saveMintConfiguration(mintURLs: mintURLs)
        hasUnsavedChanges = false
    }
}
```

### Transactional Data: Direct Access Pattern  

**Why:** Balance and transactions change frequently and users expect immediate updates.

```swift
// ✅ CORRECT: Direct access for transactional data
struct WalletDashboard: View {
    @ObservedObject var walletManager: WalletManager
    @State private var balance: Int64 = 0
    @State private var recentTransactions: [Transaction] = []
    
    var body: some View {
        VStack {
            Text("\(balance) sats")
            List(recentTransactions, id: \.id) { transaction in
                TransactionRow(transaction: transaction)
            }
        }
        .task {
            await refreshWalletData()
        }
        .refreshable {
            await refreshWalletData()
        }
    }
    
    private func refreshWalletData() async {
        guard let wallet = walletManager.wallet else { return }
        
        async let newBalance = wallet.getBalance()
        async let newTransactions = wallet.getRecentTransactions(limit: 20)
        
        balance = (try? await newBalance) ?? 0
        recentTransactions = await newTransactions
    }
}
```

---

## Common Anti-Patterns and Solutions

### Anti-Pattern 1: The "Caching Manager"

```swift
// ❌ WRONG: Duplicating wallet state in manager
@MainActor
class BadWalletManager: ObservableObject {
    @Published var wallet: NIP60Wallet?
    @Published var currentBalance: Int64 = 0
    @Published var recentTransactions: [Transaction] = []
    @Published var mintURLs: [String] = []
    
    private func updateCachedState() async {
        // This creates duplicate state and sync issues!
        currentBalance = (try? await wallet?.getBalance()) ?? 0
        recentTransactions = await wallet?.getRecentTransactions() ?? []
        mintURLs = await wallet?.mints.getMintURLs() ?? []
    }
}
```

**Problems:**
- Duplicate state requires complex synchronization
- Cache can become stale
- More code to maintain and debug
- Race conditions between updates

**Solution:** Don't cache - access directly.

### Anti-Pattern 2: The "Reactive Configuration Editor"

```swift
// ❌ WRONG: Reactive updates for configuration
func addMint(_ url: URL) async {
    // Each call publishes a new NIP-60 event - creates event spam!
    try await wallet.addMint(url)
    
    // This causes event spam on Nostr relays
    await updateUI()
}
```

**Solution:** Use local state with manual save.

### Anti-Pattern 3: The "Event Observation Trap"

```swift
// ❌ WRONG: Observing configuration events
private func handleWalletEvent(_ event: NIP60WalletEvent) async {
    switch event.type {
    case .balanceChanged(let newBalance):
        currentBalance = newBalance  // ✅ This is correct
    case .mintsAdded(let mints):
        mintURLs.append(contentsOf: mints)  // ❌ Don't cache configuration!
    }
}
```

**Solution:** Only observe transactional events, not configuration.

---

## Recommended Architecture Patterns

### Pattern 1: Minimal Wallet Manager

```swift
@MainActor
class WalletManager: ObservableObject {
    @Published var wallet: NIP60Wallet?
    @Published var isLoading = false
    @Published var error: Error?
    
    private let nostrManager: NostrManager
    
    init(nostrManager: NostrManager) {
        self.nostrManager = nostrManager
    }
    
    // ONLY lifecycle management
    func loadWallet() async throws {
        isLoading = true
        defer { isLoading = false }
        
        guard let ndk = nostrManager.ndk else {
            throw WalletError.ndkNotInitialized
        }
        
        let wallet = try NIP60Wallet(ndk: ndk, cache: nostrManager.cache)
        try await wallet.load()
        
        self.wallet = wallet
    }
    
    func clearWalletData() async {
        await wallet?.stop()
        wallet = nil
    }
    
    // Configuration operations (batch updates)
    func saveMintConfiguration(mintURLs: [String]) async throws {
        guard let wallet = wallet else {
            throw WalletError.noActiveWallet
        }
        
        let relays = await wallet.walletConfigRelays
        try await wallet.setup(
            mints: mintURLs,
            relays: relays,
            publishMintList: true
        )
    }
    
    // NO caching, NO convenience methods
    // Views access wallet directly
}
```

### Pattern 2: Direct Wallet Access in Views

```swift
struct WalletOperationView: View {
    @ObservedObject var walletManager: WalletManager
    @State private var balance: Int64 = 0
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            Text("\(balance) sats")
            
            Button("Send Payment") {
                Task { await sendPayment() }
            }
            .disabled(isLoading)
        }
        .task {
            await refreshBalance()
        }
    }
    
    private func refreshBalance() async {
        guard let wallet = walletManager.wallet else { return }
        balance = (try? await wallet.getBalance()) ?? 0
    }
    
    private func sendPayment() async {
        guard let wallet = walletManager.wallet else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Direct wallet access - no manager convenience methods
            let token = try await wallet.send(
                amount: 1000,
                to: recipientP2PK,
                mint: selectedMintURL
            )
            
            // Handle success
            await refreshBalance()  // Update local state
        } catch {
            // Handle error
        }
    }
}
```

### Pattern 3: Configuration Views with Local State

```swift
struct MintConfigurationView: View {
    @ObservedObject var walletManager: WalletManager
    @State private var editableMints: [MintInfo] = []
    @State private var originalMintURLs: [String] = []
    @State private var hasUnsavedChanges = false
    @State private var isSaving = false
    
    var body: some View {
        List {
            ForEach(editableMints) { mint in
                MintRow(mint: mint) {
                    removeMintFromLocal(mint)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    if hasUnsavedChanges {
                        revertToOriginal()
                    }
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    Task { await saveChanges() }
                }
                .disabled(!hasUnsavedChanges || isSaving)
            }
        }
        .onAppear {
            await loadCurrentConfiguration()
        }
    }
    
    private func loadCurrentConfiguration() async {
        guard let wallet = walletManager.wallet else { return }
        
        let mintURLs = await wallet.mints.getMintURLs()
        originalMintURLs = mintURLs
        editableMints = mintURLs.compactMap { urlString in
            guard let url = URL(string: urlString) else { return nil }
            return MintInfo(url: url, name: url.host ?? "Unknown Mint")
        }
        hasUnsavedChanges = false
    }
    
    private func saveChanges() async {
        isSaving = true
        defer { isSaving = false }
        
        let mintURLs = editableMints.map { $0.url.absoluteString }
        
        do {
            try await walletManager.saveMintConfiguration(mintURLs: mintURLs)
            originalMintURLs = mintURLs
            hasUnsavedChanges = false
        } catch {
            // Handle error
        }
    }
    
    private func removeMintFromLocal(_ mint: MintInfo) {
        editableMints.removeAll { $0.id == mint.id }
        hasUnsavedChanges = true
    }
}
```

---

## Testing Your Implementation

### Test 1: No Stale Cached State

```swift
func testNoStaleCachedState() async {
    // Directly modify wallet data
    try await wallet.receive(proofs: testProofs)
    
    // Manager should not have cached state that can become stale
    let balance1 = await walletManager.currentBalance
    
    // Modify again
    _ = try await wallet.send(amount: 100, to: testP2PK, mint: testMint)
    
    // Should get fresh data every time
    let balance2 = await walletManager.currentBalance
    
    XCTAssertNotEqual(balance1, balance2)
    // No cached state to become inconsistent
}
```

### Test 2: Configuration Uses Local State

```swift
func testConfigurationUsesLocalState() async {
    let view = MintManagementView(walletManager: walletManager)
    
    // Simulate user adding mint locally
    await view.addMintToLocal(url: testMintURL)
    
    // Should not have published NIP-60 event yet
    let events = await getNIP60Events()
    let initialEventCount = events.count
    
    // Only when user hits save should event be published
    await view.saveChanges()
    
    let finalEvents = await getNIP60Events()
    XCTAssertEqual(finalEvents.count, initialEventCount + 1)
}
```

### Test 3: Manager is Minimal

```swift
func testManagerIsMinimal() {
    let manager = WalletManager(nostrManager: nostrManager)
    
    // Manager should only have essential properties
    XCTAssertNotNil(manager.wallet) // Wallet reference: ✅
    XCTAssertNotNil(manager.isLoading) // Loading state: ✅
    XCTAssertNotNil(manager.error) // Error state: ✅
    
    // Manager should NOT have cached data
    // These properties should not exist:
    // XCTAssertNotNil(manager.currentBalance) // ❌
    // XCTAssertNotNil(manager.recentTransactions) // ❌
    // XCTAssertNotNil(manager.mintURLs) // ❌
}
```

---

## Key Takeaways

1. **Don't Cache Computed Values**: Balance, transaction lists, and mint URLs are computed/queried, not fetched.

2. **Configuration ≠ Transactional Data**: Use local state + manual save for configuration, direct access for transactions.

3. **UI-Level Reactivity**: Let views manage their own state instead of caching in managers.

4. **Minimal Managers**: Wallet managers should handle lifecycle only, not data caching.

5. **Understand NDKSwift**: It's not a remote API - it's a local state manager with efficient internal caching.

6. **Follow the async getter Pattern**: Use computed properties with `get async` for on-demand data access.

7. **Test Your Assumptions**: Verify that your architecture doesn't create stale state or unnecessary complexity.

By following these patterns, you'll build wallet integrations that are reactive, performant, and maintainable while avoiding the common pitfalls that lead to "leave screen and come back" bugs and other state synchronization issues.