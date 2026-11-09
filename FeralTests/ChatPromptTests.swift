import Foundation
import Testing

@testable import Feral

@Suite("对话 prompt", .serialized)
struct ChatPromptTests {
    @Test("system 带角色设定与当天日期")
    func systemCarriesRoleAndDate() {
        let system = ChatPrompt.system()

        #expect(system.contains("你是 Feral 的对话助手"))
        #expect(system.contains("今天是 \(DateFormat.fullText(Date()))。"))
    }

    @Test("system 里不再有任何训练文档")
    func systemHasNoTrainingDocuments() {
        let system = ChatPrompt.system()

        #expect(system.contains("训练计划") == false)
        #expect(system.contains("WOD") == false)
        #expect(system.contains("深蹲") == false)
        #expect(system.contains("三份文档") == false)
    }

    @Test("运行时没装好就直接说清楚，不假装发出去了")
    @MainActor
    func chatStoreWithoutRuntime() async throws {
        let store = ChatStore(modelContext: TestStore.context, runtime: RuntimeStore())
        await store.send("在吗")

        #expect(store.messages.count == 1, "只落了用户那句")
        #expect(store.failure?.contains("API Key") == true)
    }
}
