import Foundation

enum SortOrder: String, CaseIterable, Identifiable, Sendable {
    case az
    case za
    case newest
    case oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .az:     return "A–Z"
        case .za:     return "Z–A"
        case .newest: return "Newest first"
        case .oldest: return "Oldest first"
        }
    }
}

struct FilterSet: Equatable {
    var requireDate: Bool = false
    var requireNote: Bool = false

    var isActive: Bool { requireDate || requireNote }
    var activeCount: Int { (requireDate ? 1 : 0) + (requireNote ? 1 : 0) }
}

enum ListTools {
    static func filter(_ people: [Person], by set: FilterSet, hasNote: (Person) -> Bool) -> [Person] {
        guard set.isActive else { return people }
        return people.filter { p in
            if set.requireDate && p.date == nil { return false }
            if set.requireNote && !hasNote(p)   { return false }
            return true
        }
    }

    /// Case-insensitive match on handle or display name. Ignores a leading "@".
    static func search(_ people: [Person], query: String) -> [Person] {
        var q = query.trimmingCharacters(in: .whitespaces).lowercased()
        while q.hasPrefix("@") { q.removeFirst() }
        guard !q.isEmpty else { return people }
        return people.filter {
            $0.id.contains(q) || ($0.displayName?.lowercased().contains(q) ?? false)
        }
    }

    /// "Newest first" uses the export's dates when present, otherwise the file's own order
    /// (official exports list the most recent relationship first).
    static func sort(_ people: [Person], by order: SortOrder) -> [Person] {
        switch order {
        case .az:
            return people.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
        case .za:
            return people.sorted { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedDescending }
        case .newest:
            let hasDates = people.contains { $0.date != nil }
            if hasDates {
                return people.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            }
            return people.sorted { $0.order < $1.order }
        case .oldest:
            let hasDates = people.contains { $0.date != nil }
            if hasDates {
                return people.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
            }
            return people.sorted { $0.order > $1.order }
        }
    }

    /// True if the list carries any ordering signal for "Newest first".
    static func hasKnownOrder(_ people: [Person]) -> Bool {
        people.contains { $0.date != nil } || people.count > 1
    }
}

/// Builds TXT and CSV text for user-initiated exports. The Share Sheet decides where
/// the file goes — the user is saving their own file; the app keeps nothing.
enum ExportBuilder {
    enum Format: String, CaseIterable, Identifiable, Sendable {
        case txt
        case csv
        var id: String { rawValue }
        var title: String { rawValue.uppercased() }
    }

    static func text(for people: [Person], platform: Platform, format: Format) -> String {
        switch format {
        case .txt:
            return people.map(\.username).joined(separator: "\n") + "\n"
        case .csv:
            let iso = ISO8601DateFormatter()
            var lines = ["username,display_name,date,profile_url"]
            for p in people {
                let url = platform.profileURL(for: p)?.absoluteString ?? ""
                let date = p.date.map { iso.string(from: $0) } ?? ""
                lines.append([p.username, p.displayName ?? "", date, url].map(csvEscape).joined(separator: ","))
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }

    static func fileName(platform: Platform, view: String, format: Format) -> String {
        let slug = view.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return "SocialTea-\(platform.name)-\(slug).\(format.rawValue)"
    }

    static func csvEscape(_ value: String) -> String {
        var v = value
        // Neutralize spreadsheet formula injection.
        if let first = v.first, "=+-@".contains(first) { v = "'" + v }
        if v.contains(",") || v.contains("\"") || v.contains("\n") {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }
}
