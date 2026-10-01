import CCHMLib
import Foundation

public enum CHMError: Error, LocalizedError {
    case cannotOpen(URL)

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let url): return "無法開啟 CHM 檔案：\(url.lastPathComponent)"
        }
    }
}

/// Thin, thread-safe wrapper over a CHMLib archive handle.
public final class CHMFile: @unchecked Sendable {
    public let url: URL
    private let handle: OpaquePointer
    private let lock = NSRecursiveLock()
    private lazy var lowercasedPaths: [String: String] = {
        Dictionary(allPaths().map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
    }()

    public init(url: URL) throws {
        guard let handle = url.withUnsafeFileSystemRepresentation({ $0.flatMap { chm_open($0) } }) else {
            throw CHMError.cannotOpen(url)
        }
        self.url = url
        self.handle = handle
    }

    deinit { chm_close(handle) }

    /// Returns the bytes of an archive object, matching paths case-insensitively as Windows does.
    public func data(at path: String) -> Data? {
        let path = path.hasPrefix("/") ? path : "/" + path
        if let data = read(path) { return data }
        if let actual = lock.withLock({ lowercasedPaths[path.lowercased()] }), actual != path {
            return read(actual)
        }
        return nil
    }

    public func allPaths() -> [String] {
        final class Box { var paths: [String] = [] }
        let box = Box()
        lock.withLock {
            _ = chm_enumerate(handle, CHM_ENUMERATE_ALL, { _, ui, context in
                guard let ui, let context else { return CHM_ENUMERATOR_CONTINUE }
                let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
                box.paths.append(CHMFile.path(of: ui.pointee))
                return CHM_ENUMERATOR_CONTINUE
            }, Unmanaged.passUnretained(box).toOpaque())
        }
        return box.paths
    }

    private func read(_ path: String) -> Data? {
        lock.withLock {
            var ui = chmUnitInfo()
            guard chm_resolve_object(handle, path, &ui) == CHM_RESOLVE_SUCCESS else { return nil }
            let length = Int(ui.length)
            guard length > 0 else { return Data() }
            var data = Data(count: length)
            let read = data.withUnsafeMutableBytes { buffer in
                chm_retrieve_object(
                    handle, &ui, buffer.baseAddress!.assumingMemoryBound(to: UInt8.self), 0, LONGINT64(length))
            }
            guard read > 0 else { return nil }
            if Int(read) < length { data.count = Int(read) }
            return data
        }
    }

    private static func path(of ui: chmUnitInfo) -> String {
        withUnsafeBytes(of: ui.path) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
