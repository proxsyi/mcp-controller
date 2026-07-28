import Foundation

enum HTTPChunkedBodyDecoder {
    static func decode(_ data: Data) -> Data? {
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
                if bytes[cursor] == 13 && bytes[cursor + 1] == 10 { return decoded }
                var index = cursor
                while index + 3 < bytes.count {
                    if bytes[index] == 13 && bytes[index + 1] == 10 && bytes[index + 2] == 13 && bytes[index + 3] == 10 {
                        return decoded
                    }
                    index += 1
                }
                return nil
            }

            guard cursor + size + 1 < bytes.count else { return nil }
            let chunkEnd = cursor + size
            guard bytes[chunkEnd] == 13 && bytes[chunkEnd + 1] == 10 else { return nil }
            decoded.append(contentsOf: bytes[cursor..<chunkEnd])
            cursor = chunkEnd + 2
        }
    }
}
