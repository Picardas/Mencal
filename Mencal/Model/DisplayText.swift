import Foundation

/// Makes untrusted text (event titles and locations, calendar and account
/// names from shared or subscribed feeds) safe to show on one line.
nonisolated enum DisplayText {
    /// Enough for any real title; a hostile feed can carry megabytes.
    static let maxEventTextLength = 200

    /// One line of `text`:
    /// - control and line-break characters become spaces, and runs of spaces
    ///   collapse, so a title can't spread over several lines;
    /// - bidirectional overrides and isolates (U+202A–202E, U+2066–2069) and
    ///   invisible spacers are dropped, so text can't be reordered or padded
    ///   with nothing; the marks real text needs (U+200C/200D joiners,
    ///   U+200E/200F direction marks) are kept;
    /// - leading spaces are skipped, then the result is capped at `limit`
    ///   Unicode scalars (not characters: one character can stack thousands
    ///   of combining marks), with "…" when something was cut.
    static func line(_ text: String, limit: Int = maxEventTextLength, marksCut: Bool = true) -> String {
        var scalars = String.UnicodeScalarView()
        var pendingSpace = false
        var isCut = false
        for scalar in text.unicodeScalars {
            if isSpace(scalar) {
                pendingSpace = !scalars.isEmpty
                continue
            }
            if isDropped(scalar) { continue }
            let needed = pendingSpace ? 2 : 1
            guard scalars.count + needed <= limit else {
                isCut = true
                break
            }
            if pendingSpace { scalars.append(" ") }
            scalars.append(scalar)
            pendingSpace = false
        }
        return isCut && marksCut ? String(scalars) + "…" : String(scalars)
    }

    /// Whether `text` shows anything: not only spaces, invisible characters
    /// or blank-looking fillers.
    static func isVisible(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            !isSpace($0) && $0.properties.generalCategory != .format && !isBlankFiller($0)
        }
    }

    private static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .lineSeparator, .paragraphSeparator, .spaceSeparator: true
        default: scalar.properties.isWhitespace
        }
    }

    /// Invisible formatting characters, except the ones real text needs.
    private static func isDropped(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x200C, 0x200D, 0x200E, 0x200F: false
        default: scalar.properties.generalCategory == .format
        }
    }

    /// Letters that draw as nothing (Hangul and Braille blanks).
    private static func isBlankFiller(_ scalar: Unicode.Scalar) -> Bool {
        [0x115F, 0x1160, 0x2800, 0x3164, 0xFFA0].contains(scalar.value)
    }
}
