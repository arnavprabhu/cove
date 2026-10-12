import Foundation

/// Stored as `Snapshots/<id>/meta.json`.
struct Snapshot: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()
    /// True when the snapshot includes a saved machine state (shown as "+ memory").
    var includesMemory: Bool
    /// True for snapshots Cove made itself (e.g. before a restore).
    var automatic: Bool = false
    var osVersion: String?
}
