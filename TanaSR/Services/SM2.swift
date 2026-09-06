import Foundation

/// Portierung von sm2() in Scripts/tana-sr/sync_tana_sr.py -- muss exakt
/// dieselben Werte liefern, sonst laufen App und Mac-Skript auseinander.
/// quality 0-5, <3 = Fehlversuch (Reset). Klassisches SM-2.
enum SM2 {
    struct Result {
        let ease: Double
        let intervalDays: Int
        let repetitions: Int
        let dueDate: Date
    }

    static let easyQuality = 5      // "Einfach"
    static let easyStartDays = 14   // Startsprung, siehe unten
    static let easyBonus = 1.3      // Zuschlag auf reife Karten, wie in Anki
    static let maxIntervalDays = 365 // Deckel: was Tobi behalten will, soll jaehrlich auftauchen

    /// Abweichung vom klassischen SM-2, bewusst (Entscheid Tobi 06.09.2026):
    /// dort sind die Intervalle der ersten beiden Stufen fest (1 und 6 Tage).
    /// Bei der Migration bekamen 1120 der 1181 Karten repetitions=1 und landeten
    /// alle auf der 6-Tage-Stufe. "Einfach" springt deshalb auf diesen Stufen
    /// direkt auf easyStartDays und traegt danach den Easy-Bonus.
    static func review(ease: Double, intervalDays: Int, repetitions: Int, quality: Int, now: Date = Date()) -> Result {
        var newInterval: Int
        var newRepetitions: Int

        if quality < 3 {
            newRepetitions = 0
            newInterval = 1
        } else {
            if quality == easyQuality && repetitions <= 1 {
                newInterval = easyStartDays
            } else if repetitions == 0 {
                newInterval = 1
            } else if repetitions == 1 {
                newInterval = 6
            } else {
                let factor = ease * (quality == easyQuality ? easyBonus : 1)
                newInterval = Int((Double(intervalDays) * factor).rounded())
            }
            newRepetitions = repetitions + 1
            newInterval = min(newInterval, maxIntervalDays)
        }

        let qualityDouble = Double(quality)
        var newEase = ease + (0.1 - (5 - qualityDouble) * (0.08 + (5 - qualityDouble) * 0.02))
        newEase = max(1.3, newEase)
        newEase = (newEase * 100).rounded() / 100

        let dueDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: newInterval, to: now) ?? now

        return Result(ease: newEase, intervalDays: newInterval, repetitions: newRepetitions, dueDate: dueDate)
    }
}
