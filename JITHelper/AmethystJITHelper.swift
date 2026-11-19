import Foundation
import StikJIT

// Blocking StikJIT calls must remain ordered on a dedicated queue, separate
// from the host process that participates in the Universal JIT protocol.
@objc(AmethystJITHelperHandler)
final class AmethystJITHelperHandler: NSObject, NSExtensionRequestHandling {
    private static let queue = DispatchQueue(label: "org.angelauramc.amethyst.jit-helper")

    func beginRequest(with context: NSExtensionContext) {
        let request = (context.inputItems.first as? NSExtensionItem)?.userInfo?["amethyst-jit-request"] as? [String: Any]
        Self.queue.async {
            let response = Self.handle(request)
            let item = NSExtensionItem()
            item.userInfo = ["amethyst-jit-response": response]
            context.completeRequest(returningItems: [item], completionHandler: nil)
        }
    }

    private static func handle(_ request: [String: Any]?) -> [String: Any] {
        let manager = FileManager.default
        let root = manager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StikJIT", isDirectory: true)
        let paths = DDIPaths.default(in: root)
        func response(_ success: Bool, _ message: String) -> [String: Any] {
            var result: [String: Any] = ["success": success, "message": message]
            if let present = StikJIT.isTXMPresent { result["txmPresent"] = present }
            return result
        }
        func report(_ stage: StikJIT.PreparationStage) {
            NSLog("[AmethystStikJIT] prepare: %@", String(describing: stage))
        }
        do {
            guard let request, let operation = request["operation"] as? String,
                  ["prepare", "enable", "resetDDI"].contains(operation) else {
                throw failure("Invalid JIT helper request.")
            }
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            // A cancelled/crashed extension cannot execute defer. Remove only
            // our own protected temporary records on the next serial request.
            let leftovers = (try? manager.contentsOfDirectory(at: manager.temporaryDirectory,
                includingPropertiesForKeys: nil)) ?? []
            for file in leftovers where file.lastPathComponent.hasPrefix("amethyst-jit-pairing-") && file.pathExtension == "plist" {
                try? manager.removeItem(at: file)
            }
            if operation == "resetDDI" {
                try StikJIT.resetCachedDDI(at: paths)
                return response(true, "Developer Disk Image cache reset.")
            }
            guard let pairing = request["pairingData"] as? Data, !pairing.isEmpty else {
                throw failure("The pairing file is missing.")
            }
            let pairingURL = manager.temporaryDirectory.appendingPathComponent("amethyst-jit-pairing-\(UUID().uuidString).plist")
            defer { try? manager.removeItem(at: pairingURL) }
            try pairing.write(to: pairingURL, options: [.atomic, .completeFileProtection])
            if operation == "prepare" {
                switch StikJIT.prepareDevice(pairingFile: pairingURL, paths: paths, progress: report) {
                case .ready:
                    return response(true, "The device is ready.")
                case .unreachable(let reason), .preparationFailed(let reason):
                    return response(false, reason)
                }
            }
            guard let pid = request["targetPID"] as? Int32, pid > 0, pid != getpid(),
                  let script = request["scriptBase64"] as? String, !script.isEmpty else {
                throw failure("The target process or Universal JIT script is missing.")
            }
            try StikJIT.enableJIT(targetPID: pid, pairingFile: pairingURL, ddiPaths: paths,
                script: .customBase64(script), forceScript: request["forceScript"] as? Bool ?? false,
                preparationProgress: report,
                progress: { NSLog("[AmethystStikJIT] %@", $0) })
            // On TXM devices this returns only after the host's script detaches.
            return response(true, "JIT session completed.")
        } catch {
            return response(false, error.localizedDescription)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "AmethystJITHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
