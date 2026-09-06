import Foundation

/// Werte muessen exakt zu SM2_GRADES in Scripts/tana-sr/sync_tana_sr.py passen --
/// das Mac-Skript verarbeitet dieselben String-Werte aus reviews-pending.json.
enum Grade: String, CaseIterable, Codable {
    case again
    case hard
    case good
    case easy

    var label: String {
        switch self {
        case .again: return "Nochmal"
        case .hard: return "Schwer"
        case .good: return "Gut"
        case .easy: return "Einfach"
        }
    }

    /// SM-2-Qualitaet 0-5, siehe SM2_GRADES in sync_tana_sr.py.
    var quality: Int {
        switch self {
        case .again: return 1
        case .hard: return 3
        case .good: return 4
        case .easy: return 5
        }
    }
}
