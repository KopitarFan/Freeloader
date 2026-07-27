import Darwin
import Foundation

final class DirectoryWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: Int32 = -1

    func watch(_ url: URL, onChange: @escaping @MainActor @Sendable () -> Void) {
        stop()
        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )
        newSource.setEventHandler {
            Task { @MainActor in onChange() }
        }
        newSource.setCancelHandler { [descriptor] in close(descriptor) }
        source = newSource
        newSource.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }

    deinit { stop() }
}
