import Foundation

@main
struct MemoryTests {
    static func packets(_ buffer: [UInt8]) -> [String] {
        String(decoding: buffer, as: UTF8.self).split(separator: "$").map(String.init)
    }

    static func main() throws {
        // Include the JVM's RX mapping and failing code page from hs_err.
        let addresses: [UInt64] = [0x100004000, 0x7000000000, 0x7007534000, UInt64.max]
        for address in addresses {
            let packet = String(decoding: JITMemory.packet(address: address), as: UTF8.self)
            let hex = String(address, radix: 16)
            let body = "M" + String(repeating: "0", count: 16 - hex.count) + hex + ",1:69"
            let checksum = body.utf8.reduce(0) { ($0 + Int($1)) % 256 }
            precondition(packet == "$" + body + "#" + String(format: "%02x", checksum))
        }

        var batches = [[UInt8]]()
        var received = 0
        let count = try JITMemory.prepare(address: 0x7000000000, length: 129 * JITMemory.pageSize,
            send: { batches.append($0) }, receive: { received += 1; return "OK" })
        precondition(count == 129 && received == 129 && batches.count == 2)
        precondition(packets(batches[0]).count == 128 && packets(batches[1]).count == 1)
        let all = batches.flatMap(packets)
        for (page, packet) in all.enumerated() {
            let address = UInt64(0x7000000000) + UInt64(page) * JITMemory.pageSize
            precondition(packet.hasPrefix("M000000" + String(address, radix: 16) + ",1:69#"))
        }

        batches = []
        let crossing = try JITMemory.prepare(address: 0x7000003fff, length: 2,
            send: { batches.append($0) }, receive: { "OK" })
        precondition(crossing == 2 && packets(batches[0]).count == 2)
        precondition(packets(batches[0])[0].hasPrefix("M0000007000000000,"))
        precondition(packets(batches[0])[1].hasPrefix("M0000007000004000,"))

        // A remote E response used to be silently counted as a blessed page.
        for response in ["E01", "", "unexpected"] {
            var sends = 0
            var reads = 0
            do {
                try JITMemory.prepare(address: 0x7000000000, length: 129 * JITMemory.pageSize,
                    send: { _ in sends += 1 }, receive: {
                        reads += 1
                        return reads == 2 ? response : "OK"
                    })
                preconditionFailure("Rejected memory write was accepted")
            } catch JITMemory.Failure.rejectedWrite(let address, let detail) {
                precondition(address == 0x7000004000 && detail == response)
                precondition(sends == 1 && reads == 2)
            }
        }

        enum TransportError: Error { case disconnected }
        for failSend in [true, false] {
            do {
                try JITMemory.prepare(address: 0x7000000000, length: JITMemory.pageSize,
                    send: { _ in if failSend { throw TransportError.disconnected } },
                    receive: { throw TransportError.disconnected })
                preconditionFailure("Transport failure was accepted")
            } catch TransportError.disconnected {}
        }

        do {
            try JITMemory.prepare(address: UInt64.max, length: 2,
                send: { _ in preconditionFailure("Overflow sent a packet") }, receive: { "OK" })
            preconditionFailure("Overflow was accepted")
        } catch JITMemory.Failure.invalidRange {}
        let empty = try JITMemory.prepare(address: 0, length: 0,
            send: { _ in preconditionFailure("Empty range sent a packet") }, receive: { "OK" })
        precondition(empty == 0)
        print("JIT memory address, checksum, batch, alignment and failure tests passed")
    }
}
