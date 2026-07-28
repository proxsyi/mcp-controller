import Foundation

enum HTTPChunkedBodyEncoder {
    static func encode(_ body: Data) -> Data {
        var framed = Data(String(body.count, radix: 16).utf8)
        framed.append(Data("\r\n".utf8))
        framed.append(body)
        framed.append(Data("\r\n".utf8))
        return framed
    }
}
