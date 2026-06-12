import Foundation

extension Date {
    /// Section title for day-grouped lists: Today / Yesterday / "Friday 6 June".
    var dayGroupTitle: String {
        if Calendar.current.isDateInToday(self) {
            return String(localized: "Today")
        }
        if Calendar.current.isDateInYesterday(self) {
            return String(localized: "Yesterday")
        }
        return formatted(.dateTime.weekday(.wide).day().month())
    }
}
