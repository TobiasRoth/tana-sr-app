import AVFoundation
import Foundation

/// Spielt die Audio-Einbettung einer Karte ab (Xeno-Canto-Vogelstimmen).
/// Ein Player pro Karte -- `load` ersetzt eine laufende Wiedergabe komplett.
@MainActor
final class AudioPlayerViewModel: ObservableObject {
    @Published private(set) var isPlaying = false

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?

    func load(url: URL) {
        stop()
        player = AVPlayer(url: url)
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.isPlaying = false
        }
    }

    func play() {
        player?.seek(to: .zero)
        player?.play()
        isPlaying = true
    }

    func stop() {
        player?.pause()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player = nil
        isPlaying = false
    }
}

@MainActor
final class StudySessionViewModel: ObservableObject {
    @Published private(set) var dueCards: [Card] = []
    @Published private(set) var currentIndex: Int = 0
    @Published var isAnswerRevealed: Bool = false
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?

    private let store: CardStore

    init(store: CardStore) {
        self.store = store
    }

    var currentCard: Card? {
        dueCards.indices.contains(currentIndex) ? dueCards[currentIndex] : nil
    }

    var remainingCount: Int {
        max(dueCards.count - currentIndex, 0)
    }

    func loadDueCards() async {
        isLoading = true
        errorMessage = nil
        do {
            let all = try await store.loadCards()
            dueCards = all.filter(\.isDue).sorted { $0.dueDate < $1.dueDate }
            currentIndex = 0
            isAnswerRevealed = false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func revealAnswer() {
        isAnswerRevealed = true
    }

    func grade(_ grade: Grade) async {
        guard let card = currentCard else { return }

        let result = SM2.review(
            ease: card.easeFactor,
            intervalDays: card.intervalDays,
            repetitions: card.repetitions,
            quality: grade.quality
        )

        var updatedCard = card
        updatedCard.easeFactor = result.ease
        updatedCard.intervalDays = result.intervalDays
        updatedCard.repetitions = result.repetitions
        updatedCard.dueDate = Card.isoDateFormatter.string(from: result.dueDate)
        updatedCard.lastReviewedAt = ISO8601DateFormatter().string(from: Date())

        let review = PendingReview(tanaNodeId: card.tanaNodeId, grade: grade)

        do {
            try await store.submitReview(review, updatedCard: updatedCard)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isAnswerRevealed = false
        currentIndex += 1
    }
}
