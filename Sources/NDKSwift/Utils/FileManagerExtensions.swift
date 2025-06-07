import Foundation

// MARK: - FileManager Extensions for Codable Operations

extension FileManager {
    /// Loads a Codable object from a file
    /// - Parameters:
    ///   - type: The type to decode
    ///   - fileURL: The URL of the file to read
    /// - Returns: The decoded object
    func loadCodable<T: Codable>(_ type: T.Type, from fileURL: URL) throws -> T {
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
    
    /// Saves a Codable object to a file
    /// - Parameters:
    ///   - object: The object to encode and save
    ///   - fileURL: The URL where the file should be saved
    func saveCodable<T: Codable>(_ object: T, to fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(object)
        try data.write(to: fileURL)
    }
    
    /// Loads all Codable objects from a directory
    /// - Parameters:
    ///   - type: The type to decode
    ///   - directoryURL: The directory to scan
    ///   - matchingExtension: The file extension to match (default: "json")
    /// - Returns: An array of decoded objects
    func loadAllCodable<T: Codable>(
        _ type: T.Type,
        fromDirectory directoryURL: URL,
        matchingExtension fileExtension: String = "json"
    ) -> [T] {
        guard let files = try? contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        
        return files
            .filter { $0.pathExtension == fileExtension }
            .compactMap { fileURL in
                try? loadCodable(type, from: fileURL)
            }
    }
    
    /// Loads all Codable objects from a directory with their filenames
    /// - Parameters:
    ///   - type: The type to decode
    ///   - directoryURL: The directory to scan
    ///   - matchingExtension: The file extension to match (default: "json")
    /// - Returns: A dictionary mapping filenames (without extension) to decoded objects
    func loadAllCodableWithFilenames<T: Codable>(
        _ type: T.Type,
        fromDirectory directoryURL: URL,
        matchingExtension fileExtension: String = "json"
    ) -> [String: T] {
        guard let files = try? contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return [:]
        }
        
        var result: [String: T] = [:]
        
        for fileURL in files where fileURL.pathExtension == fileExtension {
            let filename = fileURL.deletingPathExtension().lastPathComponent
            if let object = try? loadCodable(type, from: fileURL) {
                result[filename] = object
            }
        }
        
        return result
    }
}

