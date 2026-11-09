import Foundation
import Testing

@testable import Feral

/// 联调用的假服务探针与现场还原工具：端口能连上就算起着。
enum MockKimiServer {
    static let host = "127.0.0.1"
    static let port: UInt16 = 8099
    static var baseUrl: String { "http://\(host):\(port)/v1" }

    /// 用例会往钥匙串里塞一把假 Key。调用方拿这个动作用 defer 收尾还原：
    /// 测试宿主的钥匙串就是模拟器里 App 的钥匙串，留一把 sk-mock 会让 App
    /// 拿着假 Key 去撞真接口，还显示「已就绪」。
    static func stashKey() -> () -> Void {
        let previous = try? KeychainStore.read(
            service: CoachProvider.kimi.keychainService,
            account: CoachProvider.kimi.credentialKey
        )
        return {
            if let previous, !previous.isEmpty {
                try? CoachKeyStore.save(previous, provider: .kimi)
            } else {
                try? CoachKeyStore.clear(provider: .kimi)
            }
        }
    }

    /// 装配按 `.standard` 里选的提供商走；联调固定钉在 kimi，跑完还原，
    /// 免得在模拟器里切过 DeepSeek 之后用例去撞真端点。
    static func pinKimiProvider() -> () -> Void {
        let previous = UserDefaults.standard.string(forKey: CoachProviderStore.defaultsKey)
        CoachProviderStore.save(.kimi)
        return {
            if let previous {
                UserDefaults.standard.set(previous, forKey: CoachProviderStore.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: CoachProviderStore.defaultsKey)
            }
        }
    }

    /// 直接做一次 TCP 连接，不走 URLSession——这个值在读测试 trait 时求值，
    /// 不能挂起、也不该等太久。
    static var reachable: Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        inet_pton(AF_INET, host, &address.sin_addr)

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                connect(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
