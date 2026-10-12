import Foundation

enum Bytes {
    static let gib: UInt64 = 1 << 30

    static func gb(_ value: Int) -> UInt64 { UInt64(value) * gib }

    static func toGB(_ bytes: UInt64) -> Int { Int((bytes + gib / 2) / gib) }

    /// Host file sizes and free space — base-10 like Finder ("26.6 GB").
    static func format(_ bytes: UInt64) -> String { string(bytes, .file) }

    /// Memory sizes, binary ("8 GB" for 8 GiB).
    static func formatMemory(_ bytes: UInt64) -> String { string(bytes, .memory) }

    /// Virtual disk sizes — binary, so an 80 GB slider value reads "80 GB", not "85.9 GB".
    static func formatDisk(_ bytes: UInt64) -> String { string(bytes, .memory) }

    private static func string(_ bytes: UInt64, _ style: ByteCountFormatter.CountStyle) -> String {
        let f = ByteCountFormatter()
        f.countStyle = style
        f.allowsNonnumericFormatting = false // "0 bytes", not "Zero KB"
        return f.string(fromByteCount: Int64(bytes))
    }
}
