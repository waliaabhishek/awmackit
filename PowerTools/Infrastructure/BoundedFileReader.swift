import Foundation

enum BoundedFileReaderError: LocalizedError {
    case fileTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let maximumBytes):
            "The file exceeds the \(maximumBytes)-byte safety limit."
        }
    }
}

enum BoundedFileReader {
    static func read(from url: URL, maximumBytes: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var result = Data()
        while result.count <= maximumBytes {
            let remaining = maximumBytes - result.count + 1
            guard let chunk = try handle.read(upToCount: min(64 * 1_024, remaining)), !chunk.isEmpty else {
                return result
            }
            result.append(chunk)
        }
        throw BoundedFileReaderError.fileTooLarge(maximumBytes)
    }
}
