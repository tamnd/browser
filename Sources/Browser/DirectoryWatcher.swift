import Foundation

// Watches directories with DispatchSource and fires a debounced callback on any change.
final class DirectoryWatcher {
    private var sources: [DispatchSourceFileSystemObject] = []
    private var descriptors: [Int32] = []
    private var pending: DispatchWorkItem?
    private let callback: () -> Void

    init(urls: [URL], onChange: @escaping () -> Void) {
        callback = onChange
        for url in urls {
            let fd = open(url.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .rename, .delete, .extend],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                self?.fire()
            }
            source.resume()
            sources.append(source)
            descriptors.append(fd)
        }
    }

    private func fire() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.callback()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    deinit {
        for source in sources { source.cancel() }
        for fd in descriptors { close(fd) }
    }
}
