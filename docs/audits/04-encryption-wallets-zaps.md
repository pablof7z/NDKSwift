# Audit: Encryption / Wallets / Zaps / LNURL / Cashu / NIP-05 / Blossom

Scope: NIP-04 / NIP-44 / NIP-59 / NIP-17 encryption, NWC wallet, NIP-57 zaps, LNURL, NIP-60/61 Cashu wallet, NIP-05 manager, Blossom (NIP-96-ish) auth, NDKAuthManager / Keychain (auth-side).

Read-only audit. Each finding cites `file:line`. Bugs are graded by *security and correctness* impact, not stylistic concerns.

---

## Critical (security or correctness bugs)

### C1. NIP-44 MAC comparison is not constant-time
`Sources/NDKSwiftCore/Encryption/NIP44/NIP44Encryption.swift:294`

```swift
guard Data(calculatedMac) == mac else {
    throw NIP44Error.invalidMAC
}
```

`Data ==` is a byte-by-byte comparison that may short-circuit on first mismatch, leaking the position of the first differing byte through timing. The NIP-44 v2 spec explicitly requires constant-time MAC comparison. Use `CryptoKit.HMAC<...>.isValidAuthenticationCode(...)` (which is constant time) or a manual XOR-OR loop.

### C2. Zap-receipt validation bypassed when LNURL provider has no `nostrPubkey`
`Sources/NDKSwiftCore/Zaps/NDKZapManager.swift:366-381`, `Sources/NDKSwiftCore/Zaps/Protocols/NDKLightningZapProtocol.swift:192-202`

In both code paths, if the LNURL provider does not return a `nostrPubkey`, the receipt's *own* `pubkey` is used as the "trusted" provider pubkey for validation:

```swift
// NDKZapManager.swift:367-371
if providerPubkey == nil && resolution.payResponse.allowsNostr == true {
    providerPubkey = receipt.event.pubkey
}
// NDKZapManager.swift:380
providerPubkey = receipt.event.pubkey   // No LNURL configured
// NDKLightningZapProtocol.swift:198-201
} else {
    // No provider pubkey to validate against, accept the receipt
    timeoutTask.cancel()
    return event
}
```

Plus `validate(lnurlProviderPubkey:)` in `NDKZapReceipt.swift:88-93` checks `event.pubkey == lnurlProviderPubkey`, so the comparison degenerates into "did the receipt pubkey equal the receipt pubkey?" — i.e. **always true**. Effect: anybody can publish a forged kind 9735 zap receipt with any amount, sender, and recipient, and it will be accepted as authentic. This destroys the trust model of NIP-57 zaps and powers fake-zap social engineering / fake-revenue dashboards.

### C3. Bolt11 amount returned in *satoshis*, treated as *millisatoshis* in zap-receipt validation
`Sources/NDKSwiftCore/Models/Kinds/NDKZapReceipt.swift:67-78` + `Sources/NDKSwiftCore/Utils/Bolt11Parser.swift:55-73, 211-226`

`Bolt11Parser.Multiplier.value` is in *sats per multiplier-unit* (e.g. `m` = 100_000 sats, `u` = 100 sats). The decoded `Invoice.amount: Satoshi (Decimal)` is therefore in **satoshis**, but:

```swift
// NDKZapReceipt.swift:66-69
public var amountMillisats: Int64? {
    guard let bolt11 = bolt11 else { return nil }
    return parseBolt11Amount(bolt11)       // <- actually returns sats
}
```

Then validation compares:

```swift
// NDKZapReceipt.swift:97-102
if let request = effectiveRequest,
   let requestAmount = request.amountMillisats,  // genuine msat (NDKZapRequest:30,61)
   let receiptAmount = amountMillisats {         // sats, not msat
    guard requestAmount == receiptAmount else { return false }
}
```

A legitimate request for 21 sats (= `21000` in the `amount` tag) versus a receipt parsed as `21` will fail validation; conversely an attacker who serves an invoice for 21000 sats against a 21 msat request would pass. Also `amountSats = amountMillisats.map { millisatsToSats($0) }` (line 72-74) then divides the (already sat) value by 1000, so consumer UIs that surface `amountSats` see numbers 1000× too small. This propagates into `NDKLightningZapProtocol.swift:144` (`ZapResult.amountSats: prepared.paymentRequest.amountSats`) and `NDKUIZapButton.swift:445`.

### C4. NIP-17 unwrap path does not verify rumor.pubkey == seal.pubkey
`Sources/NDKSwiftCore/Encryption/NIP17/NIP17PrivateMessages.swift:165-181`, `Sources/NDKSwiftCore/Encryption/NIP59/NIP59GiftWrap.swift:224-298`

NIP-59 / NIP-17 explicitly requires that the receiver:
1. unwrap the gift-wrap (1059) — the wrap pubkey is ephemeral and untrusted,
2. unseal the seal (13) — the seal pubkey is the *real* sender,
3. and verify that the inner rumor's `pubkey` matches the seal's pubkey, otherwise reject (because anyone can forge a rumor with another user's pubkey and seal it themselves).

Neither `unwrapEvent`, `unwrap`, nor `unseal` performs that check; `NIP17Error.unwrapFailed` is never thrown for pubkey mismatch. As a result a malicious sender can produce a wrap whose decrypted rumor claims `pubkey = victim`, and consumers who trust `rumor.pubkey` will attribute the message to the victim. This is the canonical NIP-17 forgery vulnerability.

### C5. NIP-59 gift-wrap timestamp randomization can be in the *future*
`Sources/NDKSwiftCore/Encryption/NIP59/NIP59GiftWrap.swift:333-337`

```swift
let twoDaysInSeconds: Int64 = 2 * 24 * 60 * 60
let randomOffset = Int64.random(in: -twoDaysInSeconds ... twoDaysInSeconds)
return .now + randomOffset
```

NIP-59 says the wrap's `created_at` should be a randomized *past* timestamp (so it doesn't leak send time, and to avoid relay drops for events too-far-in-the-future). The current symmetric ± offset produces future timestamps half the time, which many relays reject (`created_at` > now + tolerance) and which leaks "this event is no older than 2 days".

### C6. LNURL bech32 decode performs double 5→8 bit conversion
`Sources/NDKSwiftCore/LNURL/LNURLResolver.swift:80-109` + `Sources/NDKSwiftCore/Utils/Bech32.swift:64`

`Bech32.decode` already calls `convertBits(fromBits: 5, toBits: 8, pad: false)` inside (Bech32.swift:64) and returns the decoded 8-bit data. `LNURLResolver.decodeLNURL` then does:

```swift
let (hrp, data) = try Bech32.decode(lnurl)     // already 8-bit data
let decodedData = try Bech32.convertBits(data: data, fromBits: 5, toBits: 8, pad: false)
```

The second conversion treats already-8-bit bytes as 5-bit and either throws (any byte ≥ 32) or returns garbage. Effect: nearly every real bech32-encoded LNURL fails to decode through this path (the Lightning-Address path 41-58 still works, hiding the bug for many users).

### C7. Cashu DLEQ verification not performed
`Sources/NDKSwiftCashu/Models/Kinds/NDKNutzap.swift:127-132` and `Sources/NDKSwiftCashu/Wallet/Payment.swift:152-155`

```swift
// NDKNutzap.swift:127-132
for proof in proofs where proof.dleq != nil {
    // DLEQ verification would require complex cryptographic operations
    // For now, we assume they're valid if present
    continue
}
```

```swift
// Payment.swift:152-155
if case .fail = meltResult.dleqResult {
    NDKLogger.log(.warning, ... "DLEQ verification failed but continuing since payment was successful. ...")
}
```

DLEQ proofs (NUT-12) are the *only* defence against a malicious mint giving the wallet bogus blinded signatures that look valid but are unspendable / linkable. Accepting proofs without DLEQ verification, and *continuing* on `meltResult.dleqResult == .fail`, defeats this protection. For nutzaps in particular the sender's mint is fully out-of-band — there is no other check.

### C8. NWC response handler trusts arbitrary `p`-tag in multi-pay path
`Sources/NDKSwiftCore/Wallets/NWC/NWCResponseHandler.swift:178-189, 274-283`

In `waitForMultipleResponses` and `subscribeToNotifications`, the wallet pubkey for decryption is taken from the response event's `p` tag rather than from the trusted `NWCConnectionURI.walletPubkey`. Any party publishing a 23195 event to the relay (relays are public) can choose an arbitrary `p` tag value; if they encrypted the response under the corresponding key (which the attacker controls because they chose it), the client will decrypt their content and treat it as a wallet response. While the impact is limited because the original request is also encrypted to the legitimate wallet (so the attacker cannot read it), this still lets an attacker forge `failed` responses, deny service, or inject crafted `notification_type` strings consumed by app code at line 294-299.

### C9. NIP-04 IV passed unauthenticated; ciphertext+iv has no integrity guarantee
`Sources/NDKSwiftCore/Encryption/NIP04/NIP04Encryption.swift:67-109`

NIP-04 inherits no MAC by spec, so this is partially an inherited weakness. However, the implementation also:
- Does not validate IV length is exactly 16 bytes on decrypt (line 99 just base64-decodes whatever); a short IV reaches `AES(blockMode: CBC(iv:...))` which can throw or silently misbehave.
- Does not validate ciphertext length is a positive multiple of 16; PKCS7 padding stripping (`pkcs7Unpad`, line 157-174) operates on whatever the AES library returns. For a maliciously crafted payload the padding check may be misleading.

This is rated Critical because NIP-04 is still on the default scheme-detection path (`NDKEncryption.swift:130-136`: any string without `?iv=` is treated as NIP-44, so any string *with* `?iv=` is NIP-04 — and the scheme is chosen by the *attacker*-controlled `content`). A malicious sender can downgrade arbitrary NIP-44-looking content to NIP-04 by adding `?iv=` to mislead the client.

### C10. `SecRandomCopyBytes` failure swallowed; Linux fallback uses non-CSPRNG
`Sources/NDKSwiftCore/Utils/Crypto.swift:113-124`

```swift
public static func randomBytes(count: Int) -> Data {
    var bytes = [UInt8](repeating: 0, count: count)
    #if canImport(Security)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
    #else
        for i in 0 ..< count {
            bytes[i] = UInt8.random(in: 0 ... 255)
        }
    #endif
    return Data(bytes)
}
```

This is the only RNG used for:
- NIP-04 IV (`NIP04Encryption.swift:69`)
- NIP-44 v2 nonce (`NIP44Encryption.swift:314`)
- NIP-59 gift-wrap signer keys are generated via `NDKPrivateKeySigner.generate()` (not shown here, but signer code uses the same primitive elsewhere)

A failure of `SecRandomCopyBytes` would silently produce an all-zero nonce/IV. For ChaCha20 in NIP-44 a constant nonce per conversation key is **catastrophic** — it leaks the XOR of two plaintexts. The Linux fallback `UInt8.random(in:)` is the standard non-cryptographic Swift PRNG; using it for cryptographic nonces / IVs is unacceptable. Even if practically unreachable on Apple platforms, the error path must `precondition` / `fatalError` rather than silently return zeros.

---

## High

### H1. NIP-05 returned `pubkey` not validated as hex
`Sources/NDKSwiftCore/NIP05/NIP05Manager.swift:355-403`

`names[name]` is decoded as `String` and stored straight into `NIP05CacheEntry.pubkey` and returned to callers. A NIP-05 server can return `"hello-world"` or `"' OR 1=1 --"` and downstream code (filters, signers, NIP-46 routing using `nip46Relays`) will use it as a pubkey. Should `HexValidator.isValid32ByteHex(pubkey)` before accepting.

### H2. NIP-05 URL constructed with unescaped name
`Sources/NDKSwiftCore/NIP05/NIP05Manager.swift:310-314`

```swift
let normalizedName = name == "_" ? "" : name
let urlString = "https://\(domain)\(WellKnownPath.nostrJson)?name=\(normalizedName)"
```

`name` was lowercased by `identifier.normalized` but not URL-encoded. NIP-05 names are `^[a-z0-9-_.]+$`, so the regex enforces no escape need — but the input is *not* validated against that regex before being interpolated. Names containing `&`, `=`, `#`, whitespace, or even backslashes go straight into the URL string. At minimum, query construction should use `URLComponents` with `queryItems`.

### H3. Blossom auth events created without required `expiration` tag
`Sources/NDKSwiftCore/Blossom/BlossomClient.swift:138`, `Sources/NDKSwiftCore/Blossom/BlossomTypes.swift:138-216`

The Blossom auth spec (BUD-01) requires the kind 24242 event to have an `expiration` tag. In `BlossomClient.performUpload` line 138 the call is always `expiration: nil`, and `createDeleteAuth` / `createListAuth` don't accept an `expiration` parameter at all and never add one. Strict Blossom servers will reject these events; lax servers turn the auth into an effectively perpetual capability that anyone in possession of the event can replay forever.

### H4. HTTPS not enforced anywhere
`Sources/NDKSwiftCore/Utils/URLUtils.swift:12-17`, `Sources/NDKSwiftCore/LNURL/LNURLResolver.swift:103-106`, `Sources/NDKSwiftCore/Blossom/BlossomClient.swift:27, 107, 247, 322, 364`

`URLUtils.validateURL` only checks `URL(string:) != nil`. `http://` and even `file://` URLs are accepted for:
- Blossom server discovery, upload, list, delete, download (all of `BlossomClient`),
- Cashu mint URLs (`Nutzap.swift:52, 308`, mint loading),
- NWC relay URLs (validated only for parse-ability, `NWCConnectionURI.swift:64-67, 102-105`).

LNURL has a partial check (`LNURLResolver.swift:104-106`) but only on bech32-decoded LNURLs; LUD16 derives `https://...` so is fine, but the "already a URL" branch (`getLNURLEndpoint`, lines 47-49) accepts any scheme. `NDKLightningZapProtocol.resolveLNURL` lines 244-249 likewise accepts any URL string.

LN invoices and Cashu proofs over plaintext HTTP are interceptable / modifiable by a network attacker.

### H5. LN invoice returned by LNURL callback not validated against expected amount / description hash
`Sources/NDKSwiftCore/Zaps/Protocols/NDKLightningZapProtocol.swift:287-328`

`fetchInvoice` retrieves `pr` from the callback and returns it unchecked. NIP-57 (and LNURL-pay) require the client to verify:
- the invoice's amount matches the requested `amountMillisats`,
- the description hash matches `sha256(serialized zapRequest event)` (for zaps with nostr) or `sha256(metadata)` (vanilla LNURL).

Without these checks, an LNURL provider (or an attacker MITM-ing over HTTP per H4) can substitute an invoice for an arbitrary amount and / or pointing at an arbitrary destination. The user's wallet will pay it.

### H6. Cross-mint transfer accepts mint payment receipt with empty proofs and no DLEQ
`Sources/NDKSwiftCashu/Wallet/Payment.swift:247-303`

Combined with C7 (`meltResult.dleqResult == .fail` is logged-only), and the structural reliance on `mintRetryHandler` returning `newProofs.isEmpty` + `wasUserNotified == true` as the only error path, a mint can:
- Receive the Lightning payment at source mint,
- Withhold blinded signatures at destination mint until eventually returning a `wasUserNotified = false, newProofs = []` state through any retry-handler bug,
which would throw `paymentFailed` (line 282) without "requires user intervention" recovery — funds stranded at source mint silently.

### H7. NWC `description` includes secret hex in `CustomStringConvertible`
`Sources/NDKSwiftCore/Wallets/NWC/NWCConnectionURI.swift:154-158`

```swift
extension NWCConnectionURI: CustomStringConvertible {
    public var description: String {
        return uri
    }
}
```

`uri` contains `?secret=<hex>`. Any `print()` / log line / error message that includes a `NWCConnectionURI` will reveal the wallet client private key, which is sufficient to spend up to the configured budget. Recommend redaction in `description` and a separate explicit `.fullURI()` method.

### H8. P2PK private key prefix logged to debug log
`Sources/NDKSwiftCashu/Wallet/NIP60Wallet.swift:340`

```swift
NDKLogger.log(.debug, category: .wallet, "🔑 Found P2PK private key in wallet config: \(privkey.prefix(StringConstants.DisplayFormatting.hexPrefixLength))...")
```

Truncated, but logging *any* prefix of a private key materially reduces brute-force search space and is bad hygiene. Prefer logging only an opaque ID (e.g. SHA-256(pubkey).prefix(8)) or nothing.

---

## Medium

### M1. NIP-44 `unpad` allows `unpaddedLen == 0` rejection but spec also says reject when padded len differs
`Sources/NDKSwiftCore/Encryption/NIP44/NIP44Encryption.swift:114-135`

The check `padded.count == calcPaddedLen(unpaddedLen) + 2` is correct, but `padded[0]`, `padded[1]` use absolute indexing on a Swift `Data`; if `padded` is ever a slice (not the case for the current decrypt path but easily refactored to be), these are *offset by the slice start* on most operations but indexed in absolute coordinates by subscript. The current call site passes `Data(decrypted)` (fresh data), so it works today; this should still be `padded.first` / `padded.dropFirst().first` or copy-into-array to avoid future slice bugs.

### M2. NIP-59 seal validation accepts events where only one of id/sig is empty
`Sources/NDKSwiftCore/Encryption/NIP59/NIP59GiftWrap.swift:84-86`

```swift
guard rumor.id.isEmpty || rumor.sig.isEmpty else {
    throw NIP59Error.invalidRumor("Rumor must be unsigned")
}
```

A rumor with `id` set but `sig` empty (or vice-versa) passes. The intent ("unsigned") is satisfied by an empty `sig`, but a non-empty `id` means the rumor has been canonicalised once already. Combined with C4 (no inner-pubkey check on unwrap), this loosens what is acceptable on the wire. Use `&&` plus an explicit "non-empty pubkey" guard.

### M3. NIP-44 `decrypt` accepts truncated base64 payload
`Sources/NDKSwiftCore/Encryption/NIP44/NIP44Encryption.swift:253-262`

`payload.count` (line 254) checks the *base64 character length*, but `Data(base64Encoded:)` can succeed for strings that are not multiples of 4 only if it tolerates them (depending on `decodingOptions`). The base64 length check `minPayloadSize = 132` is not the same as the spec's "base64 length must be in [132,87472] characters". The check is correct against the spec, but should also reject any non-`A-Za-z0-9+/=` characters before length comparison to make `"#"`-prefixed strings the only future-flag path.

### M4. NIP-17 `wrapManyEvents` always treats sender pubkey first; ordering can leak metadata
`Sources/NDKSwiftCore/Encryption/NIP17/NIP17PrivateMessages.swift:130-150`

```swift
let allRecipients = [NIP17Recipient(pubkey: senderPubkey)] + targetRecipients
```

Sender is always wrapped first, and the iteration order of recipients is deterministic from the caller's list. Multiple identically-ordered wraps published in batch will trivially be linkable (and may leak the sender's pubkey first to relays via timing). Shuffle the array before wrapping.

### M5. NWC `NWCResponseHandler.executeRequestAndWaitForResponse` accepts responses from any signer that can decrypt
`Sources/NDKSwiftCore/Wallets/NWC/NWCResponseHandler.swift:72-80`

```swift
let senderPubkey = responseEvent.pubkey
let decryptedContent = try await signer.decrypt(senderPubkey: senderPubkey, value: eventContent, scheme: .nip04)
```

The filter (line 25-29) is `kinds: [23195]` + `e: requestId` — anyone can publish such an event. Decryption with the wrong sender pubkey fails, so an attacker cannot read the response — but they can spam decryption attempts (CPU DoS) and, importantly, the handler never compares `responseEvent.pubkey == walletPubkey`. The trusted wallet pubkey is held by `NWCRequestBuilder` but never propagated to `NWCResponseHandler`. Add a filter `authors: [walletPubkey]` and a hard equality check.

### M6. Zap `subscribeToZaps` interprets `kind 9321` `amount` tag as Int64 without bounds
`Sources/NDKSwiftCore/Zaps/NDKZapManager.swift:293-306`

```swift
let amountStr = event.tags.first(where: { $0.first == "amount" })?[safe: 1] ?? "0"
let totalAmount = Int64(amountStr) ?? 0
```

For nutzaps the amount in the `amount` tag is the **sender's claim**, not derived from the proofs. UIs that display this value will be tricked by a nutzap event that claims `amount=1000000` but contains 1 sat of proofs. The receiver-side path (`Nutzap.processIncoming`) sums proof amounts and uses that for actual credit, but the subscription handler emits an untrusted `ZapInfo.amountSats`. Compute from proofs (or document explicitly that this is sender-claimed).

### M7. Zap receipt validation does not check description-hash of the bolt11
`Sources/NDKSwiftCore/Models/Kinds/NDKZapReceipt.swift:88-119`

NIP-57 explicitly requires that `sha256(description tag)` matches the bolt11 `h` (description hash) field, otherwise the receipt does not bind to the request. Current `validate(...)` only re-parses the description as JSON; an attacker can take any legitimate receipt, swap its `description` tag for any other zap request, and the validator accepts it. (`Bolt11Parser` parses but does not expose the `h` field — `FieldTypes.fieldTypeH` is in the enum but handled as `break` at line 173-175.)

### M8. NIP-44 `getConversationKey` salt is duplicated (constants + local var) — drift hazard
`Sources/NDKSwiftCore/Encryption/NIP44/NIP44Encryption.swift:50, 179`

```swift
static let salt = "nip44-v2".data(using: .utf8)!     // Constants.salt
...
let salt = Data("nip44-v2".utf8)                     // local in getConversationKey
```

Two declarations of the same constant. `Constants.salt` is unused (the local literal is). Functionally equivalent today, but a future change to one and not the other silently breaks interop.

### M9. `BlossomBlob.dimensions` tuple coded with separate keys — Codable will silently drop on JSON encode/decode if upstream changes
`Sources/NDKSwiftCore/Blossom/BlossomTypes.swift:64-97`

Custom Codable splits tuple into `dimensionWidth`/`dimensionHeight`. There is no failure mode — encoding `nil` for one and a value for the other produces a `nil` tuple on decode. Low-impact, but the asymmetry can produce confused diagnostics.

### M10. `BlossomClient.discoverServer` returns cached value forever
`Sources/NDKSwiftCore/Blossom/BlossomClient.swift:22-46`

`serverCache[serverURL]` is never invalidated. A server can change its accepted MIME types or max size, but the client uses stale capabilities until process restart. Add TTL.

### M11. NIP-04 `decrypt` parses `parts[1]` as if guaranteed to start with `iv=` but doesn't validate format strictly
`Sources/NDKSwiftCore/Encryption/NIP04/NIP04Encryption.swift:87-109`

The string can contain multiple `?` chars (`split(separator: "?")` with default `omittingEmptySubsequences == true`) — for `"a?b?iv=…"` it produces 3 parts and is rejected (count != 2). But `"a??iv=…"` produces 2 with `parts[1] = "iv=…"`. Edge cases like a malformed payload starting with `?iv=` (parts.count == 1) are rejected. OK in practice; the `split` strategy should be replaced with a single `range(of: "?iv=")` for clarity.

### M12. NIP-05 batch verification ignores `forceVerify` re-entry
`Sources/NDKSwiftCore/NIP05/NIP05Manager.swift:162-182`

`batchVerifyStaleEntries` calls `resolvePubkey(..., forceVerify: true)`, but the in-flight-task dedup (line 46) keys on `normalizedIdentifier` without including the `forceVerify` flag. A non-forced call already running will short-circuit a parallel forced call, returning cached data instead of re-verifying. Include `forceVerify` in the in-flight cache key.

### M13. NIP-05 caches `errorMessage` but does not surface it on success path
`Sources/NDKSwiftCore/NIP05/NIP05Manager.swift:336-353`

JSON-parse failures cache an `invalidEntry` and throw `nameNotFound`; the `errorMessage` field is "Invalid JSON format" but the thrown error says "name not found". Misleading for debugging.

### M14. `RecipientZapInfo` does not consider 10019 mint relays for the LNURL fallback case
`Sources/NDKSwiftCore/Zaps/RecipientZapInfo.swift:65-73`

`nutzapRelays` aggregates per-mint relays for nutzap routing, but `NDKLightningZapProtocol.prepareZap:73-74` uses `ndk.connectedRelays()` for the zap-request `relays` tag rather than the recipient's *write* relays. This means the zap receipt may be published to relays the recipient does not read.

---

## Low

### L1. `NIP44.calcPaddedLen` uses `Double` log2 — precision drift on extreme inputs
`Sources/NDKSwiftCore/Encryption/NIP44/NIP44Encryption.swift:70-82`

`floor(log2(Double(unpadded - 1)))` for `unpadded` near `Int.max` loses precision. Inputs are bounded `1..65535` so OK in practice, but a defensive integer-bitscan (`Int.bitWidth - (unpadded-1).leadingZeroBitCount - 1`) would be exact.

### L2. NIP-04 `pkcs7Unpad` returns first byte as paddingLength without `paddingLength > 16` strict check on data shorter than 16
`Sources/NDKSwiftCore/Encryption/NIP04/NIP04Encryption.swift:157-174`

For a deliberately malformed 8-byte buffer with `lastByte = 7`, the check passes and 1 byte is returned. Combined with NIP-04's lack of authentication, this could enable padding-oracle-style attacks against careless callers. NIP-04 is deprecated; recommend banning new encrypts and emitting a deprecation warning.

### L3. `BlossomAuth.authorizationHeaderValue` force-unwraps `.utf8` encoding
`Sources/NDKSwiftCore/Blossom/BlossomTypes.swift:219-223`

```swift
let eventData = eventJSON.data(using: .utf8)!
```

`event.serialize()` should always produce valid UTF-8, but the explicit force-unwrap is a foot-gun. Replace with `Data(eventJSON.utf8)`.

### L4. `MintManager.getMintInfo` uses `appending(path:)` on a base URL with potential trailing slash
`Sources/NDKSwiftCashu/Wallet/MintManager.swift:96`

```swift
let infoUrl = url.appending(path: "/v1/info")
```

If `url` already ends in `/`, this produces `…//v1/info`. Cashu mints generally tolerate it, but normalize.

### L5. `NDKAuthManager.logout` deletes keychain in background `Task` without awaiting
`Sources/NDKSwiftCore/Auth/NDKAuthManager.swift:643-674`

If the app is terminated between `Task` launch and keychain `deleteSignerData` completion, the signer remains. `logoutAsync()` is provided for safety, but `logout()` is the more inviting API. Document the trade-off prominently.

### L6. `NWCConnectionURI.relayURLs` validation only checks URL parseability, not scheme
`Sources/NDKSwiftCore/Wallets/NWC/NWCConnectionURI.swift:64-67, 102-105`

`"javascript:alert(1)"` is a valid URL string. Restrict to `wss://` / `ws://` for relay endpoints (this is also the NDKSwift convention enforced by `URLNormalizer.tryNormalizeRelayUrl` elsewhere — apply consistently here).

### L7. `NDKZapRequest.relays` returns *all entries after the first*, including the tag name's leading "relays"
`Sources/NDKSwiftCore/Models/Kinds/NDKZapRequest.swift:81-83`

```swift
return event.tags.first(where: { $0.first == "relays" })?.dropFirst().map { String($0) } ?? []
```

`dropFirst()` on `[String]` is correct (drops "relays"); but if there were stray empties or whitespace in the URL list, those are not filtered. Minor.

### L8. `NIP44.decrypt` slicing uses absolute indices into `Data`
`Sources/NDKSwiftCore/Encryption/NIP44/NIP44Encryption.swift:270-280`

`data[0]`, `data[1 ..< (1+nonceSize)]`, etc. all assume `data.startIndex == 0`. This is true when constructed via `Data(base64Encoded:)`, so OK today, but is the same fragile pattern noted in M1.

### L9. `Crypto.randomBytes` Linux fallback hidden by `#if canImport(Security)` — fine on Apple but worth flagging
See C10. Not all Swift builds (e.g. Vapor on Linux for relay servers) include `Security` framework.

### L10. `getConversationKey` retries `0x02`/`0x03` parity with no caching of which parity worked
`Sources/NDKSwiftCore/Encryption/NIP44/NIP44Encryption.swift:147-163`

For peers exchanging many messages with one another, this is a ~2× speedup if the cache is per-conversation-key. Not security-relevant.

### L11. `NDKLightningZapProtocol.resolveLNURL` ignores `tag != "payRequest"` in returned JSON
`Sources/NDKSwiftCore/Zaps/Protocols/NDKLightningZapProtocol.swift:258-285`

The `tag` field is decoded but never verified to equal `"payRequest"`. The general `LNURLResolver` does check (`LNURLResolver.swift:120-122`), so the *zap-specific* resolver is the looser path. An LNURL server could return `tag: "withdrawRequest"` and this code would attempt to fetch an invoice from a withdraw callback.

### L12. `NIP04Encryption.computeSharedSecret` returns raw x-coordinate without HKDF
`Sources/NDKSwiftCore/Encryption/NIP04/NIP04Encryption.swift:48-58`

Inherited NIP-04 weakness — the raw ECDH x-coordinate is fed directly into AES-256 as the key. Distinguishing-attack surface is well-known. Document as deprecated and discourage use.

---

## Observations

### O1. Encryption schemes detected by content shape, not declared
`Sources/NDKSwiftCore/Encryption/NDKEncryption.swift:130-136`

```swift
if content.contains("?iv=") {
    scheme = .nip04
} else {
    scheme = .nip44
}
```

This is a content-based dispatch; the sender effectively chooses the encryption scheme by the wire format. A consumer that has explicitly opted into NIP-44 cannot prevent receipt-side downgrade to NIP-04. Consider requiring the caller to specify the expected scheme, or storing the chosen scheme alongside the cached decryption result.

### O2. No rate limiting on NIP-44 decrypt failures
`Sources/NDKSwiftCore/Encryption/NIP44/NIP44Encryption.swift:247-304`

An attacker spamming kind 1059 events to a recipient forces a NIP-44 decrypt + HMAC compute per event. While individually cheap, large volumes drive battery and CPU on mobile clients. Consider per-sender rate caps.

### O3. Wallets, Cashu mints, NIP-46 bunkers, and NIP-05 servers are all "trusted external services" with very different threat models
The codebase does not consistently apply the same input-validation pattern (hex/URL/scheme/length) across these. A shared `TrustedExternalResponse<T>` helper that requires explicit validators would reduce risk.

### O4. `BlossomServer.url` is `String` not `URL`
`Sources/NDKSwiftCore/Blossom/BlossomTypes.swift:7`

Persisting URLs as strings is fine; the issue is that no constructor validates the string is a parseable URL. Combined with H4, a misconfigured server entry is only discovered at upload time.

### O5. P2PK private key stored as `String` (hex), not `Data`, in actor memory indefinitely
`Sources/NDKSwiftCashu/Wallet/P2PKManager.swift:9, 77-93`

Strings are heap-allocated, copied around, hashed for interning, and cannot be zeroed. Use `Data` + an explicit clear method, and minimize the number of `.hexString` round trips. Same applies to `NWCConnectionURI.secret`.

### O6. NIP-17 multi-recipient `sealedEvent` is the same for all recipients
`Sources/NDKSwiftCore/Encryption/NIP17/NIP17PrivateMessages.swift:135-139`

The seal is encrypted *to sender's own pubkey* and reused across all recipient wraps. This is intentional ("self-encrypt for the seal" — line 138 comment), letting the sender decrypt their own sent messages. Just note: it means the seal's pubkey is the sender; if the sender's pubkey is ever doxed with the seal in hand, all sent messages become linkable.

### O7. `NDKZapManager.subscribeToZaps` hardcodes nutzap kind `9321`
`Sources/NDKSwiftCore/Zaps/NDKZapManager.swift:253`

Magic number `9321` should reference `EventKind.nutzap`. There is also no protocol-registration check — even if the Nutzap protocol is not registered, this subscription still emits "nutzap" `ZapInfo` events.

### O8. `ProofStateManager` rollback in `reserveProofs` skips the failing proof correctly
`Sources/NDKSwiftCashu/Wallet/ProofStateManager.swift:193-209`

Reviewed; the logic is right (`!=` skips the *failing* proof, only earlier `.reserved` entries are restored — later ones in the input array were never touched). Worth keeping a unit test that captures this exact scenario.

### O9. `NDKZapReceipt` `validate` is called with optional `lnurlProviderPubkey` everywhere — the absence of pubkey is functionally an opt-out
See C2. A `validate(strict:)` flavor that *requires* an `lnurlProviderPubkey` would make consumers' intent explicit.

### O10. The codebase has no test for "forged sender" cases in NIP-17 or "forged provider" cases in NIP-57
A property-test that generates arbitrary `seal.pubkey != rumor.pubkey` events and asserts unwrap rejects them would catch C4. Likewise for C2.

---

End of report.
