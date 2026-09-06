import Foundation

struct Card: Codable, Identifiable, Equatable {
    var id: String { tanaNodeId }

    let tanaNodeId: String
    var question: String?
    var imageUrl: String?
    var audioUrl: String? = nil
    var answerMarkdown: String
    var dueDate: String
    var easeFactor: Double
    var intervalDays: Int
    var repetitions: Int
    var lastReviewedAt: String?

    enum CodingKeys: String, CodingKey {
        case tanaNodeId = "tana_node_id"
        case question
        case imageUrl = "image_url"
        case audioUrl = "audio_url"
        case answerMarkdown = "answer_markdown"
        case dueDate = "due_date"
        case easeFactor = "ease_factor"
        case intervalDays = "interval_days"
        case repetitions
        case lastReviewedAt = "last_reviewed_at"
    }

    var answerBullets: [String] {
        answerMarkdown
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("- ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty }
    }

    var isDue: Bool {
        guard let due = Card.isoDateFormatter.date(from: dueDate) else { return true }
        return due <= Date()
    }

    static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        return formatter
    }()
}
