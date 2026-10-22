import AppKit

/// Optional sound cues, using sounds that ship with macOS (/System/Library/Sounds).
enum Sounds {
    enum Cue {
        case itemAdded, claudeNeedsYou, claudeFinished

        var soundName: NSSound.Name {
            switch self {
            case .itemAdded: return "Pop"
            case .claudeNeedsYou: return "Glass"
            case .claudeFinished: return "Hero"
            }
        }
    }

    static func play(_ cue: Cue) {
        // A fresh copy each time, so quick repeats don't cut each other off.
        (NSSound(named: cue.soundName)?.copy() as? NSSound)?.play()
    }
}
