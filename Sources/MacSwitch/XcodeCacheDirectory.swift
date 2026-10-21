import Foundation
import Darwin

final class XcodeCacheDirectory {
    private static let directoryFlags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
    private let descriptor: Int32

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) throws {
        // Resolve only the trusted home anchor. Every component below it must
        // be a real directory, and all subsequent operations stay relative to
        // the opened cache, even if its pathname is renamed or replaced.
        var current = Darwin.open(homeDirectory.resolvingSymlinksInPath().path, Self.directoryFlags)
        guard current >= 0 else { throw Self.systemError() }
        do {
            for component in ["Library", "Developer", "Xcode", "DerivedData"] {
                let next = openat(current, component, Self.directoryFlags)
                guard next >= 0 else { throw Self.systemError() }
                close(current)
                current = next
            }
        } catch {
            close(current)
            throw error
        }
        descriptor = current
    }

    deinit { close(descriptor) }

    func itemNames() throws -> [String] {
        try Self.itemNames(in: descriptor)
    }

    func removeItem(named name: String) throws {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw Self.systemError(EINVAL)
        }
        var root = stat()
        guard fstat(descriptor, &root) == 0 else { throw Self.systemError() }
        try Self.remove(name, from: descriptor, device: root.st_dev)
    }

    private static func itemNames(in descriptor: Int32) throws -> [String] {
        // A fresh descriptor has an independent enumeration offset.
        let copy = openat(descriptor, ".", directoryFlags)
        guard copy >= 0 else { throw systemError() }
        guard let directory = fdopendir(copy) else {
            let error = systemError()
            close(copy)
            throw error
        }
        defer { closedir(directory) }
        var names: [String] = []
        while true {
            errno = 0
            guard let entry = readdir(directory) else {
                guard errno == 0 else { throw systemError() }
                return names.sorted()
            }
            let name = withUnsafeBytes(of: entry.pointee.d_name) {
                String(validatingCString: $0.bindMemory(to: CChar.self).baseAddress!)
            }
            guard let name else { throw systemError(EILSEQ) }
            if name != ".", name != ".." { names.append(name) }
        }
    }

    private static func remove(_ name: String, from parent: Int32, device: dev_t) throws {
        var info = stat()
        guard fstatat(parent, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw systemError() }
        if info.st_mode & S_IFMT == S_IFDIR {
            guard info.st_dev == device else { throw systemError(EXDEV) }
            let child = openat(parent, name, directoryFlags)
            guard child >= 0 else { throw systemError() }
            defer { close(child) }
            var opened = stat()
            guard fstat(child, &opened) == 0 else { throw systemError() }
            guard opened.st_dev == info.st_dev, opened.st_ino == info.st_ino else {
                throw systemError(ESTALE)
            }
            for entry in try itemNames(in: child) {
                try remove(entry, from: child, device: device)
            }
            guard unlinkat(parent, name, AT_REMOVEDIR) == 0 else { throw systemError() }
        } else {
            // A symlink is unlinked, never opened. If the item becomes a
            // directory during cleanup, unlinkat fails rather than recursing.
            guard unlinkat(parent, name, 0) == 0 else { throw systemError() }
        }
    }

    private static func systemError(_ code: Int32 = errno) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: nil)
    }
}
