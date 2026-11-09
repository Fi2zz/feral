# Feral

一个纯对话的 iOS App。SwiftUI + SwiftData + CloudKit 私有库同步，
对话模型（Kimi / DeepSeek / OpenCode Go 可选）经 [Swiftus](https://github.com/Fi2zz/swiftus) 的
OpenAI 兼容 wire 层调用。

当前只有对话一个功能：多会话、流式输出、Markdown 渲染、停止生成、Key 存钥匙串。

## 快速开始

```bash
make help          # 全部目标
make test          # 模拟器上跑全部用例
make run           # 编译 → 装到已连接的手机 → 启动
```

也可以手动来：`make generate` 后 `open Feral.xcodeproj`。`make generate` 在工程无变化时跳过重新生成
（`project.yml` 或源码文件清单变了才会重跑），免得重生成冲掉 Xcode 里的状态。
`.xcodeproj` 是生成物，不入库；改工程配置只改 `project.yml` 后重新生成。
签名团队在首次生成时写进 `project.local.yml`（本机专属、不入库），重新生成也丢不了签名。

## 装到手机上

`make run` 自动挑第一台在线的 iPhone、推断签名团队、编译安装并启动。

- **签名团队**默认取「最近一张描述文件所属的团队」，也就是 Xcode 当前登录账号真正能签的那个；
  取不到再退到钥匙串里的 `Apple Development` 证书。想写死或换账号：把 `local.mk.example` 复制成
  `local.mk` 改 `DEVELOPMENT_TEAM`，或 `make run DEVELOPMENT_TEAM=XXXXXXXXXX`。
  报 `No Account for Team` 就是这个团队没在 Xcode → Settings → Accounts 里登录。
- **设备**默认第一台在线 iPhone，也可 `make run DEVICE=<UDID>`；`make device-list` 看有哪些。
- 手机要解锁并信任这台 Mac。

其余目标：`make install`（只装不启动）、`make run-console`（顺带把 App 的 stdout 打到终端）、
`make build`（只编模拟器包）、`make clean`。

## 选提供商、填 API Key

打开 App，点右上角的钥匙图标：先选提供商（Kimi / DeepSeek / OpenCode Go），
再在这家自己的 Key 区块里粘贴 `sk-…` 点保存。各家的 Key 分别存钥匙串（Kimi 是
service `com.fi2zz.feral.moonshot`、account `KIMI_API_KEY`；DeepSeek 是
`com.fi2zz.feral.deepseek`；OpenCode Go 是 `com.fi2zz.feral.opencode-go`），不落文件、不进仓库；
保存后运行时立刻重新装配，状态行应该从「装配失败：缺少凭据」变成「已就绪」。同一页也能清除已保存的 Key。

对话只读：不传 tools，模型没有写数据的手段。发不出去时输入框上方会红字说明原因，不静默失败。

界面四件事：
- **流式**：走 Swiftus 的 `chatStream`，正文增量边收边显示，K3 的思考增量显示成「思考中…」。
  生成中发送键变成停止键，停下来的部分照实留下并标「（已停止）」。
- **markdown**：`MarkdownParser` 先把回复切成段落/标题/列表/代码块，行内格式（粗体、行内代码、
  链接）交给系统 `AttributedString(markdown:)`——`Text` 不渲染列表和代码块，所以块级得自己切。
- **输入条**：一颗胶囊，空的时候两侧干净，有内容才浮出发送键。
- **会话管理**：右上角开新会话（干净的一屏，模型的上下文从零开始），左上角翻历史会话
  （按最近活动倒序，标题取该段第一条提问，可左滑删除）。点一条就切过去接着聊，带着那一段的
  历史。开新会话是为了别让每轮请求都拖着越来越长的历史。

### 模型

同一页下面可以点选模型，每家提供商各自记住自己的选择。Kimi 的两个：

| 模型 | 上下文 | 说明 |
|---|---|---|
| `kimi-k3` | 1M token | 默认。旗舰，适合长文与复杂问题 |
| `kimi-k2.6` | 256K token | 通用备选，更省 |

DeepSeek 预设 `deepseek-flash`（V4.1 Flash，快且省，支持思考模式）。预设失效就按服务端返回的报错提示，改
`Feral/Core/Runtime/CoachProvider.swift` 一处即可。

OpenCode Go 走订阅制网关 `https://opencode.ai/zen/go/v1`，只列了走 Chat Completions 的模型
（GPT / Claude / Gemini / Grok 走 Responses 或 Messages 协议，当前 wire 层不支持）：

| 模型 | 说明 | reasoning_effort |
|---|---|---|
| `deepseek-v4.1-flash` | 默认，快且省 | 支持 |
| `kimi-k3.1-pro` | 旗舰，长上下文 | 支持 |
| `glm-5.3` | 通用 | 支持 |
| `qwen3.8-max` | 长上下文备选 | 不发 |
| `minimax-m3` | 性价比 | 不发 |
| `mimo-v2.6-flash` | 极低成本 | 不发 |

换模型会立刻重新装配。联调时可以 `KIMI_MODEL=kimi-k2.6` 临时顶掉（只对 Kimi 生效），
设置页会显示被顶掉的状态。

推理档位：K3、DeepSeek 与 OpenCode Go 上认这个参数的模型都支持请求顶层 `reasoning_effort`
（`low` / `high` / `max`，Kimi 官方默认 `max`），这里**默认发 `high`**——日常对话满档推理收益有限
却要等更久。DeepSeek 另外带思考模式开关 `thinking: {"type": "enabled"}`，思维链增量
（`reasoning_content`）复用 K3 的流式渲染链路（正文未到时，打字指示区先显示思考摘要）。
**只给认这些字段的模型发**：K2.6、Qwen、MiniMax、MiMo 一个多余字段都不带。
设置页的「模型」区块可以改档位（认 effort 的模型共用这一档，下一条消息就生效，不用重启）；
联调时 `KIMI_REASONING_EFFORT=low` 仍能顶掉（只对 Kimi 生效），认不出的值退回默认。

## 联调 LLM（不打真服务端）

`tools/mock-kimi/mock_kimi.py` 是 OpenAI 兼容的假服务，零依赖。**它必须回 SSE**：
Swiftus 的 `chat()` 连非流式调用也走流式端点（请求体 `stream` 恒为 true），回普通 JSON
会被当成 0 个增量、得到空回答。

模拟器（两个终端）：

```bash
make mock      # 终端 A：起服务，每个请求的 system/user 全文打到终端
make run-mock  # 终端 B：编译、装机、启动，并把端点指到本机服务
```

真机（手机连不到 127.0.0.1，要走局域网）：

```bash
make mock-lan  # 终端 A：绑 0.0.0.0，并把该填的地址打出来
make run-mock-device MOCK_URL=http://192.168.x.x:8099/v1   # 终端 B
```

其余：`make test-llm` 起服务并跑联调用例；`make mock-fail` 固定返回 401 验错误提示；
`make lan-ip` 打印 Mac 的局域网地址。真机第一次跑要允许「本地网络」权限弹窗。

App 侧靠环境变量改端点，默认值不动：`KIMI_BASE_URL` / `KIMI_MODEL`，**这条通道只对 Kimi
生效**（选了 DeepSeek 时环境变量不顶任何东西，免得 mock 串到真服务）。设置页会显示
当前端点，被改过还会挂一条橙色提示，免得以为在跟真服务端说话。端点被指到本机时，
钥匙串里没有 Key 会补一把占位 Key（假服务不校验 Key），干净模拟器也能直接跑。

假服务的回话会把收到的东西回述一遍——system 字数、历史几条、最后一句是什么——所以它同时是
一份「发出去的到底是什么」的现场证据。

## 目录结构

```
Feral/
├── App/            应用入口
├── Core/
│   ├── Models/     SwiftData 模型与容器工厂（KimiChatMessage）
│   ├── Coach/      system prompt、会话分组与当前会话记录
│   ├── Markdown/   Markdown 分块解析
│   ├── Runtime/    Swiftus 上下文树 + 钥匙串凭据：FeralRuntime / RuntimeStore
│   └── Support/    日期格式化
├── Features/Chat/  对话界面：消息流、输入条、设置、历史会话
└── Resources/      Assets.xcassets、Info.plist（由 xcodegen 生成）
FeralTests/         swift-testing 用例
tools/mock-kimi/    LLM 联调用的假服务（Python 标准库，无依赖）
docs/               Swiftus 接入文档
```

## 已经定下来的决策

| 项 | 取值 | 原因 |
|---|---|---|
| 部署目标 | iOS 17.0 | SwiftData 的地板是 17，比 Swiftus 自己声明的 16 高 |
| Swift 语言模式 | 5（`SWIFT_STRICT_CONCURRENCY: minimal`） | SwiftData + `@ContextTreeActor` 在 6 模式下会淹没在并发检查里 |
| Swiftus 引用方式 | 按需产品 `SwiftusCore` `SwiftusFoundation` `SwiftusCredentials` `SwiftusLLM` | 伞产品会连带 Yams/CYaml 第三方依赖，并把 `SwiftusTasks.Task` re-export 出来遮蔽 `_Concurrency.Task` |
| 凭据来源 | 钥匙串（`KeychainCredentials` 实现 Swiftus 的 `Credentials`） | Key 明文不落文件；注入点只有 `FeralRuntime.bootstrap` 一处 |
| 运行时隔离 | `FeralRuntime`（`@ContextTreeActor`）持有上下文树，`RuntimeStore`（MainActor）只回写状态 | `Context` 及其成员都在框架的 global actor 上，视图层不能直接碰（见 docs/ios-接入指南.md 坑 ②） |
| 包管理 | XcodeGen + SPM over SSH | 见下 |
| 日期文案 | 统一走 `DateFormat`（zh_CN） | 系统是英文区域，`Date.formatted` 会渲染出「Aug 31」「Monday」 |

## 测试注意

`FeralTests/TestStore.swift` 整个测试进程只建一个 `ModelContainer`，用例之间清数据而不重建容器。
原因是实测（Xcode 26.5 / iOS 26.5 模拟器）：同一进程内每新建一个容器就往里写数据，SwiftData 会以
`EXC_BREAKPOINT` 崩掉，XCTest 报成「Restarting after unexpected exit, crash, or test timeout」。
新写用例请复用 `TestStore`，不要自己 `ModelContainer(...)`。

## 网络备注

本机 `https://github.com` 不通、SSH 通，所以 `project.yml` 里 Swiftus 走
`ssh://git@github.com/Fi2zz/swiftus.git`（tag `v0.1.6`，含间接依赖 Yams）。
已在本机 git 全局配了一条重写，让 SPM 克隆 https 源时也走 SSH：

```bash
git config --global url."ssh://git@github.com/".insteadOf "https://github.com/"
```

换到能直连 https 的网络时，删掉这条配置、把 `project.yml` 的 URL 改回 `https://` 即可。
