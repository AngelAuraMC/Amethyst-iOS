// Amethyst's StikJIT memory preparation fix. Licensed under MPL-2.0.
import Foundation

enum JITMemory {
    static let pageSize: UInt64 = 16384
    static let commandsPerBatch = 128

    enum Failure: LocalizedError {
        case invalidRange
        case rejectedWrite(UInt64, String)

        var errorDescription: String? {
            switch self {
            case .invalidRange:
                return "Invalid JIT memory range."
            case .rejectedWrite(let address, let response):
                return "JIT page preparation failed at 0x\(String(address, radix: 16)): \(response)"
            }
        }
    }

    // Keep batching, but encode every address bit. The upstream nine-digit
    // format truncates JVM mappings such as 0x7000000000 to 0x000000000.
    static func packet(address: UInt64) -> [UInt8] {
        let hex = String(address, radix: 16)
        let body = Array(("M" + String(repeating: "0", count: 16 - hex.count) + hex + ",1:69").utf8)
        let checksum = body.reduce(UInt8(0)) { $0 &+ $1 }
        let digits = Array("0123456789abcdef".utf8)
        return [UInt8(ascii: "$")] + body + [UInt8(ascii: "#"),
            digits[Int(checksum >> 4)], digits[Int(checksum & 15)]]
    }

    @discardableResult
    static func prepare(address: UInt64, length: UInt64,
                        send: ([UInt8]) throws -> Void,
                        receive: () throws -> String) throws -> Int {
        guard length > 0 else { return 0 }
        let (lastByte, overflow) = address.addingReportingOverflow(length - 1)
        guard !overflow else { throw Failure.invalidRange }
        let firstPage = address & ~(pageSize - 1)
        let pageCount = Int((lastByte - firstPage) / pageSize + 1)

        for batchStart in stride(from: 0, to: pageCount, by: commandsPerBatch) {
            let count = min(commandsPerBatch, pageCount - batchStart)
            var buffer = [UInt8]()
            for page in batchStart..<(batchStart + count) {
                buffer += packet(address: firstPage + UInt64(page) * pageSize)
            }
            try send(buffer)
            for page in batchStart..<(batchStart + count) {
                let response = try receive()
                guard response == "OK" else {
                    throw Failure.rejectedWrite(firstPage + UInt64(page) * pageSize, response)
                }
            }
        }
        return pageCount
    }
}
