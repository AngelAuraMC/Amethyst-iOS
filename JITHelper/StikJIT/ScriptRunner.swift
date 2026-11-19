// StikJIT 2.0.1, modified by Amethyst under MPL-2.0.
// Upstream: StikDebug/StikJIT b3e01a30ded4cd0b27cf1b6bd42f123bbdf49c3a.
// Preserve full addresses, validate each page write, and stop JS on failure.
import Foundation
import JavaScriptCore
@_implementationOnly import idevice

final class ScriptRunner {

    private let targetPID: Int32
    private let debugProxy: OpaquePointer
    private let script: StikJIT.Script
    private let progress: (String) -> Void
    private var context: JSContext?
    private var executionError: StikJITError?

    init(targetPID: Int32, debugProxy: OpaquePointer, script: StikJIT.Script, progress: @escaping (String) -> Void) {
        self.targetPID = targetPID
        self.debugProxy = debugProxy
        self.script = script
        self.progress = progress
    }

    func run() throws {
        let source = try BundledScript.source(for: script)

        guard let context = JSContext() else { throw StikJITError.scriptUnavailable }
        self.context = context

        context.exceptionHandler = { [weak self] _, value in
            let detail = value?.toString() ?? "unknown JavaScript exception"
            self?.recordExecutionError(.scriptExecution(detail))
        }

        let getPID: @convention(block) () -> Int = { [targetPID] in Int(targetPID) }
        let send: @convention(block) (String?) -> String = { [weak self] command in
            guard let self, let command else { return "" }
            guard let response = self.sendCommand(command) else {
                self.raiseExecutionError()
                return ""
            }
            return response
        }
        let prepare: @convention(block) (Double, Double) -> String = { [weak self] address, length in
            guard let self else { return "" }
            // JS numbers must be exact integers, otherwise conversion can trap
            // or silently prepare a different region.
            guard address <= 9007199254740991, length <= 9007199254740991,
                  let address = UInt64(exactly: address), let length = UInt64(exactly: length) else {
                self.recordExecutionError(.scriptExecution("Invalid JIT memory range."))
                self.raiseExecutionError()
                return ""
            }
            guard let response = self.prepareMemoryRegion(address, length: length) else {
                self.raiseExecutionError()
                return ""
            }
            return response
        }
        let log: @convention(block) (JSValue?) -> Void = { [weak self] value in
            self?.progress(value?.toString() ?? "")
        }

        context.setObject(getPID,  forKeyedSubscript: "get_pid" as NSString)
        context.setObject(send,    forKeyedSubscript: "send_command" as NSString)
        context.setObject(prepare, forKeyedSubscript: "prepare_memory_region" as NSString)
        context.setObject(log,     forKeyedSubscript: "log" as NSString)

        progress("Running \(script.name) against pid \(targetPID)…")
        // JITSession invokes run() on a temporary ScriptRunner. Keep it alive
        // across the C/JS call so optimized builds cannot clear weak callbacks.
        withExtendedLifetime(self) {
            _ = context.evaluateScript(source)
        }
        if let executionError { throw executionError }
        progress("JIT script finished (region blessed, detached).")
    }

    private func sendCommand(_ command: String) -> String? {
        guard let handle = command.withCString({ debugserver_command_new($0, nil, 0) }) else {
            recordExecutionError(.scriptExecution("Failed to create debugserver command."))
            return nil
        }
        defer { debugserver_command_free(handle) }
        var response: UnsafeMutablePointer<CChar>?
        defer { if let response { idevice_string_free(response) } }
        if let error = debug_proxy_send_command(debugProxy, handle, &response) {
            recordExecutionError(IdeviceFFI.consume(error, fallback: "send_command"))
            return nil
        }
        guard let response else { return "" }
        return String(cString: response)
    }

    private func prepareMemoryRegion(_ address: UInt64, length: UInt64) -> String? {
        do {
            let pageCount = try JITMemory.prepare(address: address, length: length, send: { buffer in
                let error = buffer.withUnsafeBytes { rawBuffer in
                    debug_proxy_send_raw(self.debugProxy, rawBuffer.bindMemory(to: UInt8.self).baseAddress!, UInt(buffer.count))
                }
                if let error { throw IdeviceFFI.consume(error, fallback: "debug_proxy_send_raw") }
            }, receive: {
                var response: UnsafeMutablePointer<CChar>?
                let readError = debug_proxy_read_response(self.debugProxy, &response)
                defer { if let response { idevice_string_free(response) } }
                if let readError {
                    throw IdeviceFFI.consume(readError, fallback: "debug_proxy_read_response")
                }
                guard let response else { return "missing response" }
                return String(cString: response)
            })
            progress("Blessed \(pageCount) JIT page(s) at 0x\(String(address, radix: 16))")
            return "OK"
        } catch {
            recordExecutionError((error as? StikJITError) ?? .scriptExecution(error.localizedDescription))
            return nil
        }
    }

    private func recordExecutionError(_ error: StikJITError) {
        if executionError == nil {
            executionError = error
            progress(error.localizedDescription)
        }
    }

    private func raiseExecutionError() {
        guard let context, let executionError else { return }
        context.exception = JSValue(newErrorFromMessage: executionError.localizedDescription, in: context)
    }
}
