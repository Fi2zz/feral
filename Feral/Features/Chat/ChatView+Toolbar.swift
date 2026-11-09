import SwiftUI

/// 对话页工具栏：新会话 / 历史会话 / API Key 设置。Swift 的 private 只到文件边界，
/// 移到扩展文件后被访问的成员（store、isShowingHistory、isShowingSettings、startNewConversation）降为 internal。
extension ChatView {
    /// 开新会话：干净的一屏，旧的进历史列表。
    var newConversationButton: some View {
        Button {
            startNewConversation()
        } label: {
            Image(systemName: "square.and.pencil")
        }
        .disabled(store == nil)
    }

    var historyButton: some View {
        Button {
            isShowingHistory = true
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .disabled(store == nil)
    }

    var keyButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "key")
        }
    }
}
