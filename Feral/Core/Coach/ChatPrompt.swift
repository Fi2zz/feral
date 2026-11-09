import Foundation

/// 对话助手的 system prompt。
enum ChatPrompt {
    /// 角色设定。
    static let role = """
    你是 Feral 的对话助手，用简体中文回答。先给结论，再按需补充细节；\
    不确定就直接说不确定，不要编造。
    """

    /// 发给模型的完整 system prompt。当天日期常驻，给模型一个真实的时间锚点。
    static func system(today: Date = Date()) -> String {
        let dateLine = "今天是 \(DateFormat.fullText(today))。"
        return [role, dateLine].joined(separator: "\n\n")
    }
}
