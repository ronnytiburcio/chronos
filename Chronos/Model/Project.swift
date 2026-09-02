import Foundation

/// A thing time is tracked against. The list is fixed and user-managed; there
/// is no hierarchy, no client, no rate (SPEC §2).
///
/// Persisted as an array in `projects.json`. `colorHex` is optional because a
/// project that has never been given a color falls back to the palette's
/// default in the UI, and `Optional` decodes as `nil` when the key is absent,
/// so files written by older builds keep loading.
struct Project: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// Display name, always stored trimmed and never empty.
    var name: String
    /// `#RRGGBB`, or `nil` for the palette default.
    var colorHex: String?
    /// Position in the panel list; the engine keeps these contiguous from 0.
    var sortOrder: Int
    /// Archived projects keep their history but drop out of the panel.
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        sortOrder: Int,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortOrder = sortOrder
        self.isArchived = isArchived
    }
}
