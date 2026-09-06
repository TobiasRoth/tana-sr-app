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

    static func review(ease: Double, intervalDays: Int, repetitions: Int, quality: Int, now: Date = Date()) -> Result {
        var newInterval: Int
        var newRepetitions: Int

        if quality < 3 {
            newRepetitions = 0
            newInterval = 1
        } else {
            if repetitions == 0 {
                newInterval = 1
            } else if repetitions == 1 {
                newInterval = 6
            } else {
                newInterval = Int((Double(intervalDays) * ease).rounded())
            }
            newRepetitions = repetitions + 1
        }

        let qualityDouble = Double(quality)
        var newEase = ease + (0.1 - (5 - qualityDouble) * (0.08 + (5 - qualityDouble) * 0.02))
        newEase = max(1.3, newEase)
        newEase = (newEase * 100).rounded() / 100

        let dueDate = Calendar(identifier: .gregorian).date(byAdding: .day, value: newInterval, to: now) ?? now

        return Result(ease: newEase, intervalDays: newInterval, repetitions: newRepetitions, dueDate: dueDate)
    }
}
