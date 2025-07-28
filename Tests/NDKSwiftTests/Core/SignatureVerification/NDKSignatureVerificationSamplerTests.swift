import XCTest
@testable import NDKSwift

final class NDKSignatureVerificationSamplerTests: XCTestCase {
    var sampler: NDKSignatureVerificationSampler!
    
    override func setUp() {
        super.setUp()
        sampler = NDKSignatureVerificationSampler()
    }
    
    override func tearDown() {
        sampler = nil
        super.tearDown()
    }
    
    func testShouldVerifyEventWithDefaultRatio() {
        var verifiedCount = 0
        let iterations = 10000
        
        for _ in 0..<iterations {
            if sampler.shouldVerifyEvent() {
                verifiedCount += 1
            }
        }
        
        let verificationRatio = Double(verifiedCount) / Double(iterations)
        XCTAssertGreaterThan(verificationRatio, 0.08)
        XCTAssertLessThan(verificationRatio, 0.12)
    }
    
    func testShouldVerifyEventWithCustomRatio() {
        sampler.setValidationRatio(0.5)
        
        var verifiedCount = 0
        let iterations = 10000
        
        for _ in 0..<iterations {
            if sampler.shouldVerifyEvent() {
                verifiedCount += 1
            }
        }
        
        let verificationRatio = Double(verifiedCount) / Double(iterations)
        XCTAssertGreaterThan(verificationRatio, 0.48)
        XCTAssertLessThan(verificationRatio, 0.52)
    }
    
    func testCalculateDefaultValidationRatio() {
        let ratio = sampler.calculateDefaultValidationRatio()
        XCTAssertEqual(ratio, 0.1)
    }
    
    func testAlwaysVerifyWithRatioOne() {
        sampler.setValidationRatio(1.0)
        
        for _ in 0..<100 {
            XCTAssertTrue(sampler.shouldVerifyEvent())
        }
    }
    
    func testNeverVerifyWithRatioZero() {
        sampler.setValidationRatio(0.0)
        
        for _ in 0..<100 {
            XCTAssertFalse(sampler.shouldVerifyEvent())
        }
    }
    
    func testShouldAlwaysVerifySpecialKinds() {
        let specialKinds: [NDKEventKind] = [
            .metadata,
            .parameterizedReplaceable(30078),
            .deletion
        ]
        
        for kind in specialKinds {
            XCTAssertTrue(sampler.shouldVerifyEvent(kind: kind))
        }
    }
    
    func testShouldSampleRegularKinds() {
        let regularKinds: [NDKEventKind] = [
            .textNote,
            .recommendRelay,
            .reaction
        ]
        
        var anyFalse = false
        var anyTrue = false
        
        for _ in 0..<100 {
            for kind in regularKinds {
                if sampler.shouldVerifyEvent(kind: kind) {
                    anyTrue = true
                } else {
                    anyFalse = true
                }
            }
        }
        
        XCTAssertTrue(anyTrue)
        XCTAssertTrue(anyFalse)
    }
}