import Foundation

/// CardStore auf Basis von Dropbox (App-Ordner "TanaSR", siehe Scripts/tana-sr/).
///
/// Reviews werden zuerst in eine lokale Datei geschrieben (funktioniert offline,
/// z.B. im Zug), danach best-effort nach Dropbox in reviews-pending.json
/// gemergt. Das Mac-Sync-Skript verarbeitet reviews-pending.json und schreibt
/// den SM-2-Zustand nach cards.json zurueck -- die App aendert cards.json nie
/// selbst, nur ihre eigene Kopie im lokalen Cache (fuer die laufende Session).
actor DropboxCardStore: CardStore {
    private let client: DropboxClient
    private let fileManager = FileManager.default

    private var cardsCacheURL: URL {
        documentsDirectory.appendingPathComponent("cards-cache.json")
    }
    private var localPendingReviewsURL: URL {
        documentsDirectory.appendingPathComponent("local-pending-reviews.json")
    }
    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    init(client: DropboxClient) {
        self.client = client
    }

    func loadCards() async throws -> [Card] {
        do {
            let data = try await client.download(path: "/cards.json")
            try? data.write(to: cardsCacheURL, options: .atomic)
            await flushPendingReviews()
            return try JSONDecoder().decode([Card].self, from: data)
        } catch {
            if let cached = try? Data(contentsOf: cardsCacheURL) {
                return try JSONDecoder().decode([Card].self, from: cached)
            }
            throw error
        }
    }

    func submitReview(_ review: PendingReview, updatedCard: Card) async throws {
        var queued = loadLocalPendingReviews()
        queued.append(review)
        try saveLocalPendingReviews(queued)

        if var cached = try? JSONDecoder().decode([Card].self, from: Data(contentsOf: cardsCacheURL)),
           let index = cached.firstIndex(where: { $0.tanaNodeId == updatedCard.tanaNodeId }) {
            cached[index] = updatedCard
            try? JSONEncoder().encode(cached).write(to: cardsCacheURL, options: .atomic)
        }

        await flushPendingReviews()
    }

    /// Best-effort: lokale Warteschlange nach Dropbox mergen. Schlaegt das fehl
    /// (kein Netz), bleibt die Review in der lokalen Datei fuer den naechsten Versuch.
    func flushPendingReviews() async {
        let queued = loadLocalPendingReviews()
        guard !queued.isEmpty else { return }

        do {
            var remote = try await downloadPendingReviews()
            remote.append(contentsOf: queued)
            let data = try JSONEncoder().encode(remote)
            try await client.upload(path: "/reviews-pending.json", data: data)
            try saveLocalPendingReviews([])
        } catch {
            // Bleibt in der lokalen Warteschlange, naechster loadCards()/submitReview() versucht erneut.
        }
    }

    private func downloadPendingReviews() async throws -> [PendingReview] {
        do {
            let data = try await client.download(path: "/reviews-pending.json")
            return (try? JSONDecoder().decode([PendingReview].self, from: data)) ?? []
        } catch DropboxError.httpError(409, _) {
            return []  // Datei existiert noch nicht -- erster Review ueberhaupt.
        }
    }

    private func loadLocalPendingReviews() -> [PendingReview] {
        guard let data = try? Data(contentsOf: localPendingReviewsURL) else { return [] }
        return (try? JSONDecoder().decode([PendingReview].self, from: data)) ?? []
    }

    private func saveLocalPendingReviews(_ reviews: [PendingReview]) throws {
        let data = try JSONEncoder().encode(reviews)
        try data.write(to: localPendingReviewsURL, options: .atomic)
    }
}
