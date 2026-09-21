import Darwin
import Foundation

/// Watch the running code and its enclosing app, so an atomic app update reloads the helper
/// without unregistering its already-approved service.
public final class ExecutableReplacementMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private var sources: [DispatchSourceFileSystemObject] = []
    private let onReplacement: @Sendable () -> Void

    public init(urls: [URL], onReplacement: @escaping @Sendable () -> Void) throws {
        self.onReplacement = onReplacement
        for url in urls {
            let descriptor = open(url.path, O_EVTONLY | O_CLOEXEC)
            guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.delete, .rename, .revoke], queue: .global(qos: .utility))
            source.setEventHandler { [weak self] in self?.notifyOnce() }
            source.setCancelHandler { close(descriptor) }
            sources.append(source)
            source.resume()
        }
    }

    private func notifyOnce() {
        let shouldNotify = lock.withLock {
            if fired { return false }
            fired = true
            return true
        }
        if shouldNotify { onReplacement() }
    }

    deinit { sources.forEach { $0.cancel() } }
}
