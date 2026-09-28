# 贡献指南

感谢你考虑为 Macsoft X 出力。这个项目定位是**一个面板聚合 Mac 上全部软件更新**——GUI 应用、App Store、终端里的 CLI 包管理器，一处看全、一处更新。

## 环境要求

| 项 | 要求 |
|---|---|
| macOS | 15.0 或更高（[Package.swift](Package.swift) 的部署目标） |
| Xcode | **26 或更高**。工具栏布局使用了 macOS 26 SDK 才引入的 `ToolbarSpacer`，用 Xcode 15/16 编译会报 `cannot find 'ToolbarSpacer' in scope`。CI 在 `macos-26` runner 上构建 |
| Swift | 5.9+ |
| 运行时依赖 | Homebrew（brew）、Node.js（npm）、Ruby（gem）、uv、mas —— **全部可选**，缺哪个就跳过哪个源 |

无需安装任何第三方 SwiftPM 依赖，项目只依赖系统框架。

## 构建与测试

```bash
swift build                              # 调试构建
swift build -Xswiftc -warnings-as-errors # 零警告校验（CI 用）
swift build -c release                   # 发布构建
swift test                               # 132 个单元测试
```

打包成可分发的 `.app`：

```bash
./Scripts/make-app.sh    # 产出 build/Macsoft X.app（ad-hoc 签名）
./Scripts/make-dmg.sh    # 进一步产出可分发的 DMG
```

## 命令行模式

除了 GUI，应用支持几个 CLI 入口，调试和脚本化时很有用：

```bash
.build/debug/upmac --scan          # 全源扫描，输出 JSON
.build/debug/upmac --scan-fast     # 跳过 cask 网络检测的快速扫描
.build/debug/upmac --inventory     # 全部已装软件清单，输出 JSON
```

## 架构约定

新增一个包管理器或应用来源时，**只需实现 `UpdateProvider` 协议**（见 `Sources/upmac/Core/UpdateProvider.swift`）：

```swift
public protocol UpdateProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func isAvailable() async -> Bool
    func fetchOutdated() async throws -> [UpdateItem]
    func update(_ item: UpdateItem) async throws -> UpdateResult
}
```

注册到 `AppState(providers:)` 即可，UI、通知、批量更新、忽略规则全部自动生效。

## 必须遵守的红线

这些是项目不可妥协的安全约束，改动前请务必理解：

1. **删除一律走 `trashItem`，绝不用 `removeItem` 或 `rm`**
   用户的文件必须可恢复。`grep -rn "removeItem" Sources/` 应零命中。

2. **命令执行一律用参数数组，绝不拼 shell 字符串**
   用 `Process.arguments` 传参，不用 `/bin/sh -c`。包名和应用名来自扫描结果，是不可信输入。

3. **删除前必须做路径边界校验**
   见 `UninstallService.validateDeletionSafety`：解析 realpath、拒绝符号链接本身、断言落在该类别的允许父目录白名单内。

4. **状态文件只有一个写入口**
   走 `StateStore.update`（内部持 NSLock，保证读-改-写原子）。不要直接读写 `state.json`。

5. **界面不许说谎**
   未验证的结论不显示（见 [docs/08-design-spec.md](docs/08-design-spec.md) §6.6）。例如：全部来源失败时不能显示"所有软件均为最新版本"；`UpdateResult.autoUpdated == false` 表示交接给应用自更新，不能谎报为已更新。

## 代码风格

- 遵循现有代码的命名与注释密度（中文注释，说明**为什么**而非**做了什么**）
- 设计 token 统一走 `DesignSystem`，不要自造颜色/圆角/间距
- 面向用户的文案用中文，不外泄技术黑话（技术细节放 `debugDescription`）

## 提交 Pull Request

1. 从 `main` 切分支
2. 改动配套加测试，`swift test` 必须全绿
3. `swift build -Xswiftc -warnings-as-errors` 必须零警告
4. PR 描述里说明**改了什么**和**为什么**

CI 会在 macOS 26 runner 上跑：严格构建、发布构建、全量测试，以及 CLI 冒烟验证。

## 许可

贡献即表示你同意你的代码以 [MIT 协议](LICENSE) 发布。
