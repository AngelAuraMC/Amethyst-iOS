// Real JavaScriptCore/Swift callbacks, with only the remote transport replaced.
import Foundation
import Darwin

enum StikJIT {
    enum Script {
        case regression
        var name: String { "regression" }
    }
}
enum StikJITError: LocalizedError {
    case scriptUnavailable
    case scriptExecution(String)
    var errorDescription: String? {
        switch self {
        case .scriptUnavailable: return "JavaScriptCore unavailable"
        case .scriptExecution(let message): return message
        }
    }
}
enum BundledScript {
    static func source(for script: StikJIT.Script) throws -> String { Transport.source }
}
struct IdeviceFfiError {}
enum IdeviceFFI {
    static func consume(_ error: UnsafeMutablePointer<IdeviceFfiError>, fallback: String) -> StikJITError {
        error.deallocate()
        return .scriptExecution("Disconnected: " + fallback)
    }
}
enum Transport {
    static var source = ""
    static var replies = [String]()
    static var buffers = [[UInt8]]()
    static var progress = [String]()
    static var failCommand = false
    static var failSend = false
    static var failRead = false
    static func error() -> UnsafeMutablePointer<IdeviceFfiError> { .allocate(capacity: 1) }
}
func debugserver_command_new(_ name: UnsafePointer<CChar>, _ argv: UnsafePointer<UnsafePointer<CChar>?>?, _ count: Int) -> OpaquePointer? {
    OpaquePointer(strdup(name))
}
func debugserver_command_free(_ command: OpaquePointer) { free(UnsafeMutableRawPointer(command)) }
func idevice_string_free(_ value: UnsafeMutablePointer<CChar>) { free(value) }
func debug_proxy_send_command(_ proxy: OpaquePointer, _ command: OpaquePointer,
                              _ response: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> UnsafeMutablePointer<IdeviceFfiError>? {
    if Transport.failCommand { return Transport.error() }
    response.pointee = strdup("OK")
    return nil
}
func debug_proxy_send_raw(_ proxy: OpaquePointer, _ bytes: UnsafePointer<UInt8>, _ count: UInt) -> UnsafeMutablePointer<IdeviceFfiError>? {
    if Transport.failSend { return Transport.error() }
    Transport.buffers.append(Array(UnsafeBufferPointer(start: bytes, count: Int(count))))
    return nil
}
func debug_proxy_read_response(_ proxy: OpaquePointer,
                             _ response: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> UnsafeMutablePointer<IdeviceFfiError>? {
    if Transport.failRead { return Transport.error() }
    response.pointee = strdup(Transport.replies.isEmpty ? "OK" : Transport.replies.removeFirst())
    return nil
}

@main
struct ScriptRunnerTests {
    static func run(_ source: String) throws {
        Transport.source = source
        Transport.buffers = []
        Transport.progress = []
        // Match JITSession's temporary instance and compile with optimization.
        try ScriptRunner(targetPID: 42, debugProxy: OpaquePointer(bitPattern: 1)!,
            script: .regression, progress: { Transport.progress.append($0) }).run()
    }
    static func mustStop(_ source: String, message: String) throws {
        do {
            try run(source + "; log('continued after failure')")
            preconditionFailure("Native error was swallowed")
        } catch {
            precondition(error.localizedDescription.contains(message), error.localizedDescription)
            precondition(!Transport.progress.contains("continued after failure"))
        }
    }
    static func main() throws {
        try run("""
            if (get_pid() !== 42) throw new Error('ScriptRunner released');
            if (send_command('qTest') !== 'OK') throw new Error('command failed');
            if (prepare_memory_region(0x7000000000, 0x8000) !== 'OK') throw new Error('prepare failed');
            log('callbacks complete');
            """)
        precondition(Transport.progress.contains("callbacks complete"))
        let expected = JITMemory.packet(address: 0x7000000000) + JITMemory.packet(address: 0x7000004000)
        precondition(Transport.buffers == [expected])

        Transport.replies = ["E01"]
        try mustStop("prepare_memory_region(0x7000000000, 0x8000)", message: "0x7000000000: E01")
        Transport.failSend = true
        try mustStop("prepare_memory_region(0x7000000000, 0x8000)", message: "debug_proxy_send_raw")
        Transport.failSend = false
        Transport.failRead = true
        try mustStop("prepare_memory_region(0x7000000000, 0x8000)", message: "debug_proxy_read_response")
        Transport.failRead = false
        Transport.failCommand = true
        try mustStop("send_command('qTest')", message: "send_command")
        Transport.failCommand = false
        for argument in ["NaN", "Infinity", "-1", "1.5", "9007199254740992"] {
            try mustStop("prepare_memory_region(\(argument), 16384)", message: "Invalid JIT memory range")
        }
        print("Optimized ScriptRunner lifetime and real JavaScriptCore error propagation passed")
    }
}
