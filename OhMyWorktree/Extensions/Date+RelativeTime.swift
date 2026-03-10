import Foundation

extension Date {
    var relativeTimeString: String {
        let seconds = Int(-timeIntervalSinceNow)
        guard seconds >= 0 else { return "just now" }
        if seconds < 60 { return "just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 30 { return "\(days)d ago" }
        let months = days / 30
        if months < 12 { return "\(months)mo ago" }
        return "\(days / 365)y ago"
    }
}
