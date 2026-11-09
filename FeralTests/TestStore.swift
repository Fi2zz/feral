import Foundation
import SwiftData

@testable import Feral

/// 整个测试进程共用一个 `ModelContainer`。
///
/// 不用 `isStoredInMemoryOnly`：在这台工具链（Xcode 26.5 / iOS 26.5 模拟器）上，
/// 同一进程内每新建一个容器就往里写数据，SwiftData 会以 `EXC_BREAKPOINT` 崩掉；
/// 只建一次、之后只清数据而不重建容器，就没有这个问题。路径带 UUID，
/// 保证每个测试进程从空库开始，也不碰模拟器里 App 自己的库。
@MainActor
enum TestStore {
    static let container: ModelContainer = {
        let schema = Schema(FeralSchema.models)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "feral-tests-\(UUID().uuidString).store")
        let configuration = ModelConfiguration(schema: schema, url: url)
        return forceTry { try ModelContainer(for: schema, configurations: configuration) }
    }()

    static var context: ModelContext { container.mainContext }

    /// 清空消息，让下一个用例从空库开始。
    static func freshContext() throws -> ModelContext {
        try reset()
        return context
    }

    /// 清空全部模型。删不掉的类型直接抛错，不留半个库给后面的用例。
    /// 用逐条 delete 而不是 `delete(model:)`：批量删除会绕过级联，撞上附件关系的约束。
    static func reset() throws {
        let context = context
        for message in try context.fetch(FetchDescriptor<KimiChatMessage>()) {
            context.delete(message)
        }
        for attachment in try context.fetch(FetchDescriptor<ChatAttachment>()) {
            context.delete(attachment)
        }
        try context.save()
    }

    private static func forceTry<T>(_ expression: () throws -> T) -> T {
        do {
            return try expression()
        } catch {
            fatalError("测试容器创建失败：\(error)")
        }
    }
}
