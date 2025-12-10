import XCTest
@testable import NDKSwiftCore

final class FileManagerExtensionsTests: XCTestCase {
    
    private var tempDirectory: URL!
    private let fileManager = FileManager.default
    
    // Test model
    private struct TestModel: Codable, Equatable {
        let id: Int
        let name: String
        let timestamp: Int64
    }
    
    override func setUp() {
        super.setUp()
        // Create temporary directory for tests
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NDKSwiftTests_\(UUID().uuidString)")
        try? fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        super.tearDown()
        // Clean up temporary directory
        try? fileManager.removeItem(at: tempDirectory)
    }
    
    func testSaveAndLoadCodable() throws {
        let testModel = TestModel(id: 1, name: "Test", timestamp: 1234567890)
        let fileURL = tempDirectory.appendingPathComponent("test.json")
        
        // Save
        try fileManager.saveCodable(testModel, to: fileURL)
        
        // Verify file exists
        XCTAssertTrue(fileManager.fileExists(atPath: fileURL.path))
        
        // Load
        let loadedModel = try fileManager.loadCodable(TestModel.self, from: fileURL)
        
        // Verify content
        XCTAssertEqual(loadedModel, testModel)
    }
    
    func testLoadCodable_FileNotFound() {
        let fileURL = tempDirectory.appendingPathComponent("nonexistent.json")
        
        XCTAssertThrowsError(try fileManager.loadCodable(TestModel.self, from: fileURL))
    }
    
    func testLoadCodable_InvalidJSON() throws {
        let fileURL = tempDirectory.appendingPathComponent("invalid.json")
        let invalidData = "not json".data(using: .utf8)!
        try invalidData.write(to: fileURL)
        
        XCTAssertThrowsError(try fileManager.loadCodable(TestModel.self, from: fileURL))
    }
    
    func testLoadAllCodable() throws {
        // Create test models
        let models = [
            TestModel(id: 1, name: "Model 1", timestamp: 1234567890),
            TestModel(id: 2, name: "Model 2", timestamp: 1234567891),
            TestModel(id: 3, name: "Model 3", timestamp: 1234567892)
        ]
        
        // Save models
        for (index, model) in models.enumerated() {
            let fileURL = tempDirectory.appendingPathComponent("model\(index).json")
            try fileManager.saveCodable(model, to: fileURL)
        }
        
        // Add a non-JSON file to verify filtering
        let textFileURL = tempDirectory.appendingPathComponent("readme.txt")
        try "This is not JSON".write(to: textFileURL, atomically: true, encoding: .utf8)
        
        // Load all
        let loadedModels = fileManager.loadAllCodable(
            TestModel.self,
            fromDirectory: tempDirectory
        )
        
        // Verify
        XCTAssertEqual(loadedModels.count, 3)
        XCTAssertTrue(loadedModels.contains(models[0]))
        XCTAssertTrue(loadedModels.contains(models[1]))
        XCTAssertTrue(loadedModels.contains(models[2]))
    }
    
    func testLoadAllCodable_EmptyDirectory() throws {
        let emptyDir = tempDirectory.appendingPathComponent("empty")
        try fileManager.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        
        let loadedModels = fileManager.loadAllCodable(
            TestModel.self,
            fromDirectory: emptyDir
        )
        
        XCTAssertEqual(loadedModels.count, 0)
    }
    
    func testLoadAllCodable_DirectoryNotFound() {
        let nonExistentDir = tempDirectory.appendingPathComponent("nonexistent")
        
        let loadedModels = fileManager.loadAllCodable(
            TestModel.self,
            fromDirectory: nonExistentDir
        )
        
        XCTAssertEqual(loadedModels.count, 0)
    }
    
    func testLoadAllCodableWithFilenames() throws {
        // Create test models
        let models = [
            ("user1", TestModel(id: 1, name: "User 1", timestamp: 1234567890)),
            ("user2", TestModel(id: 2, name: "User 2", timestamp: 1234567891)),
            ("settings", TestModel(id: 3, name: "Settings", timestamp: 1234567892))
        ]
        
        // Save models
        for (filename, model) in models {
            let fileURL = tempDirectory.appendingPathComponent("\(filename).json")
            try fileManager.saveCodable(model, to: fileURL)
        }
        
        // Load all with filenames
        let loadedModels = fileManager.loadAllCodableWithFilenames(
            TestModel.self,
            fromDirectory: tempDirectory
        )
        
        // Verify
        XCTAssertEqual(loadedModels.count, 3)
        XCTAssertEqual(loadedModels["user1"], models[0].1)
        XCTAssertEqual(loadedModels["user2"], models[1].1)
        XCTAssertEqual(loadedModels["settings"], models[2].1)
    }
    
    func testLoadAllCodableWithFilenames_CustomExtension() throws {
        let model = TestModel(id: 1, name: "Custom", timestamp: 1234567890)
        
        // Save with custom extension
        let fileURL = tempDirectory.appendingPathComponent("data.custom")
        try fileManager.saveCodable(model, to: fileURL)
        
        // Also save a JSON file that should be ignored
        let jsonURL = tempDirectory.appendingPathComponent("ignored.json")
        try fileManager.saveCodable(model, to: jsonURL)
        
        // Load with custom extension
        let loadedModels = fileManager.loadAllCodableWithFilenames(
            TestModel.self,
            fromDirectory: tempDirectory,
            matchingExtension: "custom"
        )
        
        // Verify
        XCTAssertEqual(loadedModels.count, 1)
        XCTAssertEqual(loadedModels["data"], model)
        XCTAssertNil(loadedModels["ignored"])
    }
    
    func testLoadAllCodableWithFilenames_SkipsInvalidFiles() throws {
        let validModel = TestModel(id: 1, name: "Valid", timestamp: 1234567890)
        
        // Save valid model
        let validURL = tempDirectory.appendingPathComponent("valid.json")
        try fileManager.saveCodable(validModel, to: validURL)
        
        // Create invalid JSON file
        let invalidURL = tempDirectory.appendingPathComponent("invalid.json")
        try "not json".write(to: invalidURL, atomically: true, encoding: .utf8)
        
        // Load all
        let loadedModels = fileManager.loadAllCodableWithFilenames(
            TestModel.self,
            fromDirectory: tempDirectory
        )
        
        // Verify only valid model is loaded
        XCTAssertEqual(loadedModels.count, 1)
        XCTAssertEqual(loadedModels["valid"], validModel)
        XCTAssertNil(loadedModels["invalid"])
    }
}