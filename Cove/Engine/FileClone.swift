import Foundation

enum FileClone {
    /// APFS copy-on-write clone; falls back to a regular copy on other file systems.
    static func clone(_ src: URL, to dst: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
        if clonefile(src.path, dst.path, 0) != 0 {
            try fm.copyItem(at: src, to: dst)
        }
    }

    static func allocatedSize(of url: URL) -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in e {
            let v = try? file.resourceValues(forKeys: Set(keys))
            if v?.isRegularFile == true { total += UInt64(v?.totalFileAllocatedSize ?? 0) }
        }
        return total
    }
}
