import Foundation
import SwiftData

/// 全部模型与容器工厂。目前只有对话消息一张表。
enum FeralSchema {
    static let models: [any PersistentModel.Type] = [
        KimiChatMessage.self,
        ChatAttachment.self,
    ]

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
