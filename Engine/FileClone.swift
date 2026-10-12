import Foundation

enum FileClone {
    /// APFS copy-on-write clone (regular copy on other file systems), replacing `dst` atomically.
    /// The copy is made beside `dst` first and renamed over it, so a failure (e.g. a full disk) never
    /// leaves `dst` missing or half-written.
    static func clone(_ src: URL, to dst: URL) throws {
        let fm = FileManager.default
        let tmp = dst.deletingLastPathComponent()
            .appending(path: ".\(dst.lastPathComponent).cove-tmp-\(UUID().uuidString)")
        do {
            if clonefile(src.path, tmp.path, UInt32(CLONE_NOFOLLOW)) != 0 {
                try fm.copyItem(at: src, to: tmp)
            }
            guard rename(tmp.path, dst.path) == 0 else {
                throw CoveError.io("Couldn’t replace \(dst.lastPathComponent): \(String(cString: strerror(errno)))")
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
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
