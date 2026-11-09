import SwiftData
import SwiftUI

@main
struct FeralApp: App {
    @State private var runtime = RuntimeStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(runtime)
        }
        .modelContainer(FeralContainer.shared)
    }
}

/// 存储容器。建不出来就没法跑，失败即崩，不做降级。
enum FeralContainer {
    static let shared: ModelContainer = {
        do {
            return try FeralSchema.makeContainer()
        } catch {
            fatalError("ModelContainer 装配失败：\(error)")
        }
    }()
}
