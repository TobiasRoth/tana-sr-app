import Foundation

/// Ein Eintrag in reviews-pending.json -- das Mac-Skript liest diese Datei,
/// berechnet SM-2 serverseitig nach (Quelle der Wahrheit bleibt cards.json)
/// und schreibt das neue Datum ins Tana-srs-Feld zurueck.
struct PendingReview: Codable {
    let tanaNodeId: String
    let grade: Grade
    let reviewedAt: String

    enum CodingKeys: String, CodingKey {
        case tanaNodeId = "tana_node_id"
        case grade
        case reviewedAt = "reviewed_at"
    }

    init(tanaNodeId: String, grade: Grade, reviewedAt: Date = Date()) {
        self.tanaNodeId = tanaNodeId
        self.grade = grade
        self.reviewedAt = ISO8601DateFormatter().string(from: reviewedAt)
    }
}
