import Foundation
import SwiftusCredentials
import SwiftusLLM

/// 把异常转成给人看的一句话。
///
/// Swiftus 的异常自带中文原因，`localizedDescription` 只会给出「error 1」这类无信息文本；
/// 模型服务端的报错原文也要带出来，不然用户只能去看控制台。抽出来是为了让联调用例
/// 能直接断言「报错时界面会显示什么」。
enum ErrorText {
    static func reason(_ error: any Error) -> String {
        if let credentials = error as? CredentialsException { return credentials.message }
        if let llm = error as? LlmException {
            let status = llm.statusCode.map { "（HTTP \($0)）" } ?? ""
            return "\(llm.message)\(status)"
        }
        return error.localizedDescription
    }
}
