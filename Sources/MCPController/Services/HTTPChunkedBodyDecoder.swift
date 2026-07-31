import Foundation

enum HTTPChunkedBodyDecoder {
    static func decode(_ data: Data) -> Data? {
        decodeWithConsumed(data)?.body
    }

    static func decodeWithConsumed(_ data: Data) -> (body: Data, bytesConsumed: Int)? {
        let bytes = [UInt8](data)
        var cursor = 0
        var decoded = Data()

        func firstCRLF(from start: Int) -> Int? {
            guard start < bytes.count else { return nil }
            var index = start
            while index + 1 < bytes.count {
                if bytes[index] == 13 && bytes[index + 1] == 10 { return index }
                index += 1
            }
            return nil
        }

        while true {
            guard let lineEnd = firstCRLF(from: cursor),
                  let line = String(bytes: bytes[cursor..<lineEnd], encoding: .utf8) else { return nil }
            let sizeText = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces)
            guard let size = Int(sizeText, radix: 16), size >= 0 else { return nil }
            cursor = lineEnd + 2

            if size == 0 {
                guard cursor + 1 < bytes.count else { return nil }
                if bytes[cursor] == 13 && bytes[cursor + 1] == 10 {
                    return (decoded, cursor + 2)
                }
                var index = cursor
                while index + 3 < bytes.count {
                    if bytes[index] == 13 && bytes[index + 1] == 10 && bytes[index + 2] == 13 && bytes[index + 3] == 10 {
                        return (decoded, index + 4)
                    }
                    index += 1
                }
                return nil
            }

            guard cursor <= bytes.count,
                  size <= bytes.count - cursor else { return nil }
            let chunkEnd = cursor + size
            guard chunkEnd + 1 < bytes.count,
                  bytes[chunkEnd] == 13,
                  bytes[chunkEnd + 1] == 10 else { return nil }
            decoded.append(contentsOf: bytes[cursor..<chunkEnd])
            cursor = chunkEnd + 2
        }
    }

    static func decodeAvailableChunks(_ data: Data) -> (body: Data, bytesConsumed: Int)? {
        let bytes = [UInt8](data)
        var cursor = 0
        var decoded = Data()

        func partialResult(before chunkStart: Int) -> (body: Data, bytesConsumed: Int)? {
            decoded.isEmpty ? nil : (decoded, chunkStart)
        }

        func firstCRLF(from start: Int) -> Int? {
            guard start < bytes.count else { return nil }
            var index = start
            while index + 1 < bytes.count {
                if bytes[index] == 13 && bytes[index + 1] == 10 { return index }
                index += 1
            }
            return nil
        }

        while cursor < bytes.count {
            let chunkStart = cursor
            guard let lineEnd = firstCRLF(from: cursor),
                  let line = String(bytes: bytes[cursor..<lineEnd], encoding: .utf8) else {
                return partialResult(before: chunkStart)
            }
            let sizeText = line.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces)
            guard let size = Int(sizeText, radix: 16), size >= 0 else {
                return partialResult(before: chunkStart)
            }
            cursor = lineEnd + 2
            if size == 0 {
                return partialResult(before: chunkStart)
            }
            guard cursor <= bytes.count,
                  size <= bytes.count - cursor else {
                return partialResult(before: chunkStart)
            }
            let chunkEnd = cursor + size
            guard chunkEnd + 1 < bytes.count,
                  bytes[chunkEnd] == 13,
                  bytes[chunkEnd + 1] == 10 else {
                return partialResult(before: chunkStart)
            }
            decoded.append(contentsOf: bytes[cursor..<chunkEnd])
            cursor = chunkEnd + 2
        }

        return decoded.isEmpty ? nil : (decoded, cursor)
    }
}
