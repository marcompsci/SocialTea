import Foundation

/// Which list a file is being imported as. Used to pick the right section of
/// combined exports (e.g. TikTok's single `user_data.json` holds both lists).
enum ListRole: String, Sendable {
    case followers
    case following
}

enum ImportError: LocalizedError, Equatable {
    case unreadable
    case empty
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .unreadable: return "That file couldn't be read. Try exporting it again."
        case .empty: return "No usernames were found in that file."
        case .invalidJSON: return "That JSON file isn't in a format SocialTea understands."
        }
    }
}

/// Parses follower/following lists from official platform exports and simple files.
///
/// Supported:
/// - JSON: Instagram `followers_1.json` / `following.json` (old and new layouts),
///   TikTok `user_data.json`, Facebook `friends.json`, arrays of strings, arrays of objects.
/// - CSV: detects a username column by header name, otherwise uses the first column.
/// - TXT: one username per line, plus TikTok's "Username: x" text export.
///
/// Pure and synchronous: no file system, no network, no persistence.
enum ImportParser {

    // MARK: Entry point

    static func parse(data: Data, fileName: String, role: ListRole) throws -> [Person] {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ImportError.unreadable
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.empty }

        let people: [Person]
        if ext == "json" || trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            people = try parseJSON(data: data, role: role)
        } else if ext == "csv" || looksLikeCSV(trimmed) {
            people = parseCSV(trimmed)
        } else {
            people = parseTXT(trimmed)
        }
        let unique = dedupe(people)
        guard !unique.isEmpty else { throw ImportError.empty }
        return unique
    }

    /// Merges several files for the same list (e.g. `followers_1.json` + `followers_2.json`).
    static func merge(_ lists: [[Person]]) -> [Person] {
        var order = 0
        var result: [Person] = []
        var seen = Set<String>()
        for list in lists {
            for p in list where !seen.contains(p.id) {
                seen.insert(p.id)
                result.append(Person(username: p.username, displayName: p.displayName, date: p.date, order: order))
                order += 1
            }
        }
        return result
    }

    // MARK: Username cleanup

    /// Turns "@Name", "https://www.instagram.com/_u/name/", "tiktok.com/@name?x=1" into "Name"/"name".
    static func cleanUsername(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'\u{FEFF}"))
        guard !s.isEmpty else { return nil }

        let lower = s.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.contains(".com/") {
            var path = s
            if let range = path.range(of: ".com/", options: .caseInsensitive) {
                path = String(path[range.upperBound...])
            }
            if let q = path.firstIndex(where: { $0 == "?" || $0 == "#" }) { path = String(path[..<q]) }
            let parts = path.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "_u" }
            guard let last = parts.last else { return nil }
            s = last
        }
        while s.hasPrefix("@") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, s.count <= 100 else { return nil }
        return s
    }

    // MARK: TXT

    static func parseTXT(_ text: String) -> [Person] {
        var people: [Person] = []
        var pendingDate: Date?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("date:") {
                pendingDate = parseDate(String(line.dropFirst(5)))
                continue
            }
            var value = line
            if lower.hasPrefix("username:") {
                value = String(line.dropFirst("username:".count))
            } else if lower.hasPrefix("user name:") {
                value = String(line.dropFirst("user name:".count))
            }
            if let name = cleanUsername(value) {
                people.append(Person(username: name, date: pendingDate, order: people.count))
            }
            pendingDate = nil
        }
        return people
    }

    // MARK: CSV

    private static let usernameHeaders = ["username", "user name", "user_name", "handle", "account",
                                          "user", "screen name", "screen_name", "value", "profile",
                                          "profile url", "url", "link", "name", "full name"]
    private static let dateHeaders = ["date", "timestamp", "followed at", "time", "created"]

    static func looksLikeCSV(_ text: String) -> Bool {
        guard let first = text.components(separatedBy: .newlines).first else { return false }
        return first.contains(",")
    }

    static func parseCSV(_ text: String) -> [Person] {
        let rows = csvRows(text)
        guard let header = rows.first else { return [] }
        let normalized = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        var nameColumn: Int?
        for candidate in usernameHeaders {
            if let idx = normalized.firstIndex(of: candidate) { nameColumn = idx; break }
        }
        let displayColumn = normalized.firstIndex(where: { $0 == "full name" || $0 == "display name" || $0 == "name" })
        let dateColumn = normalized.firstIndex(where: { dateHeaders.contains($0) })

        let hasHeader = nameColumn != nil
        let column = nameColumn ?? 0
        let body = hasHeader ? Array(rows.dropFirst()) : rows

        var people: [Person] = []
        for row in body where column < row.count {
            guard let name = cleanUsername(row[column]) else { continue }
            var display: String?
            if let d = displayColumn, d != column, d < row.count {
                let v = row[d].trimmingCharacters(in: .whitespaces)
                display = v.isEmpty ? nil : v
            }
            var date: Date?
            if let dc = dateColumn, dc < row.count { date = parseDate(row[dc]) }
            people.append(Person(username: name, displayName: display, date: date, order: people.count))
        }
        return people
    }

    /// Minimal RFC 4180 reader: quoted fields, escaped quotes, commas and newlines inside quotes.
    static func csvRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = Array(text).makeIterator()
        var pending: Character? = nil

        func nextChar() -> Character? {
            if let p = pending { pending = nil; return p }
            return iterator.next()
        }

        while let c = nextChar() {
            if inQuotes {
                if c == "\"" {
                    if let n = nextChar() {
                        if n == "\"" { field.append("\"") } else { inQuotes = false; pending = n }
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r\n", "\r":
                    row.append(field); field = ""
                    if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) { rows.append(row) }
                    row = []
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) { rows.append(row) }
        }
        return rows
    }

    // MARK: JSON

    private static let followerKeys = ["followers", "relationships_followers", "follower list", "follower",
                                       "fanslist", "fans list", "fans", "friends_v2", "friends", "followers_v2"]
    private static let followingKeys = ["relationships_following", "following list", "following",
                                        "following_v2", "followinglist"]

    static func parseJSON(data: Data, role: ListRole) throws -> [Person] {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw ImportError.invalidJSON
        }
        let keys = role == .followers ? followerKeys : followingKeys
        let scoped = findSection(in: root, keys: keys) ?? root
        var people: [Person] = []
        collect(from: scoped, into: &people)
        return people
    }

    /// Breadth-first search for the first dictionary key that names the requested list.
    static func findSection(in root: Any, keys: [String]) -> Any? {
        var queue: [Any] = [root]
        while !queue.isEmpty {
            let node = queue.removeFirst()
            if let dict = node as? [String: Any] {
                let normalizedPairs = dict.map { (key: $0.key.lowercased().trimmingCharacters(in: .whitespaces), value: $0.value) }
                for wanted in keys {
                    if let match = normalizedPairs.first(where: { $0.key == wanted }),
                       match.value is [Any] || match.value is [String: Any] {
                        return match.value
                    }
                }
                queue.append(contentsOf: dict.values)
            } else if let array = node as? [Any] {
                // Only peek into containers, not long lists of entries.
                queue.append(contentsOf: array.prefix(4).filter { $0 is [String: Any] && !isEntry($0) })
            }
        }
        return nil
    }

    private static let handleKeys = ["username", "user_name", "UserName", "userName", "handle", "screen_name", "value"]
    private static let nameKeys = ["name", "full_name", "fullName", "display_name", "displayName"]

    private static func isEntry(_ node: Any) -> Bool {
        guard let dict = node as? [String: Any] else { return false }
        if dict["string_list_data"] != nil { return true }
        return handleKeys.contains { dict[$0] is String } || nameKeys.contains { dict[$0] is String }
    }

    static func collect(from node: Any, into people: inout [Person]) {
        if let string = node as? String {
            if let name = cleanUsername(string) { people.append(Person(username: name, order: people.count)) }
            return
        }
        if let array = node as? [Any] {
            for item in array { collect(from: item, into: &people) }
            return
        }
        guard let dict = node as? [String: Any] else { return }

        // Instagram: { "title": "...", "string_list_data": [{ "href", "value", "timestamp" }] }
        if let list = dict["string_list_data"] as? [[String: Any]] {
            let title = (dict["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            if list.isEmpty, let t = title, let name = cleanUsername(t) {
                people.append(Person(username: name, order: people.count))
            }
            for item in list {
                let raw = (item["value"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? title
                    ?? (item["href"] as? String)
                guard let r = raw, let name = cleanUsername(r) else { continue }
                people.append(Person(username: name, date: dateValue(item["timestamp"]), order: people.count))
            }
            return
        }

        let handle = handleKeys.lazy.compactMap { dict[$0] as? String }.first(where: { !$0.isEmpty })
        let display = nameKeys.lazy.compactMap { dict[$0] as? String }.first(where: { !$0.isEmpty })
        let href = (dict["href"] as? String) ?? (dict["url"] as? String) ?? (dict["link"] as? String)
        let date = dateValue(dict["timestamp"] ?? dict["Date"] ?? dict["date"])

        if let h = handle ?? href, let name = cleanUsername(h) {
            people.append(Person(username: name, displayName: display, date: date, order: people.count))
            return
        }
        if let d = display, let name = cleanUsername(d) {
            // Facebook friends export: names only.
            people.append(Person(username: name, displayName: d, date: date, order: people.count))
            return
        }
        for value in dict.values { collect(from: value, into: &people) }
    }

    // MARK: Dates

    static func dateValue(_ any: Any?) -> Date? {
        if let n = any as? NSNumber {
            let v = n.doubleValue
            guard v > 0 else { return nil }
            return Date(timeIntervalSince1970: v > 10_000_000_000 ? v / 1000 : v)
        }
        if let s = any as? String { return parseDate(s) }
        return nil
    }

    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if let v = Double(s), v > 0 { return Date(timeIntervalSince1970: v > 10_000_000_000 ? v / 1000 : v) }
        for f in dateFormatters {
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    private static let dateFormatters: [DateFormatter] = {
        ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd", "MM/dd/yyyy"].map { format in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = format
            return f
        }
    }()

    // MARK: Dedupe

    static func dedupe(_ people: [Person]) -> [Person] {
        var seen = Set<String>()
        var out: [Person] = []
        for p in people where !seen.contains(p.id) {
            seen.insert(p.id)
            out.append(Person(username: p.username, displayName: p.displayName, date: p.date, order: out.count))
        }
        return out
    }
}
