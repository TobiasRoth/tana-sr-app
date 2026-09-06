import Foundation

protocol CardStore {
    func loadCards() async throws -> [Card]
    func submitReview(_ review: PendingReview, updatedCard: Card) async throws
}

/// Fuer Phase-3-Entwicklung/Simulator-Tests, solange die Dropbox-Anbindung noch
/// nicht verdrahtet ist. Haelt Karten nur im Speicher, kein Persistieren.
actor MockCardStore: CardStore {
    private var cards: [Card]

    init(cards: [Card] = MockCardStore.sampleCards) {
        self.cards = cards
    }

    func loadCards() async throws -> [Card] {
        cards
    }

    func submitReview(_ review: PendingReview, updatedCard: Card) async throws {
        if let index = cards.firstIndex(where: { $0.tanaNodeId == updatedCard.tanaNodeId }) {
            cards[index] = updatedCard
        }
    }

    static let sampleCards: [Card] = [
        Card(
            tanaNodeId: "sample-1",
            question: "Was ist ein Verpflichtungskredit (VK)?",
            imageUrl: nil,
            answerMarkdown: "- Parlamentarische Ermächtigung für mehrjährige Ausgabenverpflichtungen bis zu einem Maximalbetrag.",
            dueDate: Card.isoDateFormatter.string(from: Date()),
            easeFactor: 2.5,
            intervalDays: 0,
            repetitions: 0,
            lastReviewedAt: nil
        ),
        Card(
            tanaNodeId: "sample-2",
            question: "Welche Art ist das?",
            imageUrl: "https://firebasestorage.googleapis.com/v0/b/tagr-prod.appspot.com/o/notespace%2Ftobias.roth.4142%40gmail.com%2Fuploads%2F2025-02-11T05%3A02%3A57.817Z-image.png?alt=media&token=b1c8974c-8c66-47ba-b009-ff4c64833d74",
            answerMarkdown: "- Malven-Dickkopffalter - Carcharodus alceae\n- Weisse Adern auf Vorderflügel (innere Hälfte)\n- Hinterrand des Hinterflügels gezähnt",
            dueDate: Card.isoDateFormatter.string(from: Date()),
            easeFactor: 2.5,
            intervalDays: 0,
            repetitions: 1,
            lastReviewedAt: nil
        ),
        Card(
            tanaNodeId: "sample-3",
            question: "Welche Verteilungen sind Spezialfälle der negativen Binomialverteilung?",
            imageUrl: nil,
            answerMarkdown: "- **r=1** → geometrische Verteilung.\n- **r→∞, p→1** → Poisson als Grenzwert.\n- Anwendung: Overdispersed count data",
            dueDate: Card.isoDateFormatter.string(from: Date().addingTimeInterval(-86400)),
            easeFactor: 2.3,
            intervalDays: 12,
            repetitions: 2,
            lastReviewedAt: nil
        ),
    ]
}
