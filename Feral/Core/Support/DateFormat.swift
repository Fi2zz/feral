import Foundation

/// 日期文案。App 全中文，但系统是英文区域，`Date.formatted` 会渲染出
/// 「Aug 31」「Monday」这类英文，所以自己按 `zh_CN` 格式化，不依赖设备语言。
enum DateFormat {
    private static let locale = Locale(identifier: "zh_CN")

    private static let monthDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let full: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter
    }()

    private static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    /// 「9月29日」
    static func monthDayText(_ date: Date) -> String { monthDay.string(from: date) }
    /// 「星期一」
    static func weekdayText(_ date: Date) -> String { weekday.string(from: date) }
    /// 「2026年9月29日 星期二」
    static func fullText(_ date: Date) -> String { full.string(from: date) }
    /// 「2026年9月」
    static func monthTitleText(_ date: Date) -> String { monthTitle.string(from: date) }
    /// 「9/29」
    static func shortText(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)/\(parts.day ?? 0)"
    }
}
