import Foundation

// Turns loader warnings into a few readable lines for the Insert Model File alert (#206). Loaders warn once per
// primitive with a full NSError description, so a single missing file can produce dozens of screen-high entries.
enum InsertWarnings {
    static let maximumLines = 8

    // One line per distinct message in first-seen order, "N × message" when repeated, at most maximumLines plus a
    // note for the rest.
    static func summary(_ warnings: [String]) -> [String] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for warning in warnings {
            let message = readable(warning)
            if counts[message] == nil {
                order.append(message)
            }
            counts[message, default: 0] += 1
        }
        var lines = order.prefix(maximumLines).map { message in
            let count = counts[message] ?? 1
            return count > 1 ? "\(count) \u{00D7} \(message)" : message
        }
        if order.count > maximumLines {
            lines.append("and \(order.count - maximumLines) more (see the log)")
        }
        return lines
    }

    // Drops the per-primitive "Skipped <name>: " prefix, and keeps only the quoted description of an NSError.
    static func readable(_ warning: String) -> String {
        var message = warning
        if message.hasPrefix("Skipped "), let separator = message.range(of: ": ") {
            message = String(message[separator.upperBound...])
        }
        if message.hasPrefix("Error Domain="), let open = message.firstIndex(of: "\"") {
            let rest = message[message.index(after: open)...]
            if let close = rest.firstIndex(of: "\"") {
                message = String(rest[..<close])
            }
        }
        return message
    }
}
