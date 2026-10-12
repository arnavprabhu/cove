import Foundation

enum Bytes {
    static let gib: UInt64 = 1 << 30

    static func gb(_ value: Int) -> UInt64 { UInt64(value) * gib }

    static func toGB(_ bytes: UInt64) -> Int { Int((bytes + gib / 2) / gib) }

    /// "8 GB", "1.2 TB" — base-10 like Finder.
    static func format(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Memory sizes read better in binary units ("8 GB" for 8 GiB).
    static func formatMemory(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}
