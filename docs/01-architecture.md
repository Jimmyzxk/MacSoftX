# 01 · 整体架构

## 0. 一句话定位

Mac 菜单栏统一更新管理器：聚合 **GUI 应用（Sparkle/App Store）+ CLI 包管理器（brew/npm/pipx/uv/cargo/gem）** 的过期清单，菜单栏角标提示，**逐项勾选更新**。

竞品坐标：
- MacUpdater：2026-01-01 停更（仅 GUI 应用，已死）
- Version Tracker：闭源付费（€19.90/年，48 源，功能对标但不开源）
- topgrade / mpm：开源 CLI 聚合，无 GUI
- **空白 = 开源 + GUI + 全源聚合 + 选择性更新，本项目占这个位**

## 1. 技术选型

| 项 | 选择 | 理由 |
|----|------|------|
| 语言/UI | Swift 5.9 + SwiftUI（工具链 6.3.3） | 菜单栏+主窗场景最省事；无跨平台刚需 |
| 通知 | `UNUserNotificationCenter` | 系统级通知中心 |
| 开机自启 | `SMAppService`（Login Item） | 现代 API；避开 launchd+外置盘 TCC 坑 |
| 最低系统 | **macOS 15** | 初始定为 26，实测未使用任何 26 专属 API，下调至 15 以覆盖绝大多数活跃 Mac |
| 持久化 | 单个 JSON 文件（Application Support） | 忽略/稍后/历史/设置；无数据库，好备份 |
| 分发 | Developer ID + 公证，**不上 App Store** | 沙盒会杀 shell out，从源头规避 |
| License | **MIT 全仓** | 引擎自研，不抄 GPL 代码（topgrade GPL-3 / mpm GPL-2 / Latest GPL-3） |

开发工具链：**SwiftPM + `swift build` + VS Code**。本机实测完整版 Xcode 已在外置盘 `Xcode.app`（Swift 6.3.3 就绪），无需另装、零内置占用（9/13 修正：原"CLT 3GB 必须内置"的约束不成立）。

## 2. 四层架构

```
┌──────────────────────────────────────────────────┐
│ 表现层  MenuBarExtra 角标 / 桌面主窗 / Settings   │
├──────────────────────────────────────────────────┤
│ 核心层  归一化 · 版本比较 · 忽略规则 · 执行队列    │
├──────────────────────────────────────────────────┤
│ 采集层  UpdateProvider 插件 ×N（每源一个）        │
├──────────────────────────────────────────────────┤
│ 基础层  ShellRunner · 调度 · 通知 · JSON 持久化   │
└──────────────────────────────────────────────────┘
```

层间只通过模型通信，采集层可独立增删（第二批源 = 纯增量加插件）。

### 2.1 Provider 协议

每个 Provider 只做两件事：查过期、执行升级。

```swift
protocol UpdateProvider {
    var id: String { get }              // "brew" / "mas" / "npm" ...
    var displayName: String { get }
    func isAvailable() async -> Bool    // 命令是否存在（决定该源是否启用）
    func fetchOutdated() async -> [UpdateItem]
    func update(_ item: UpdateItem) async throws -> UpdateResult
}
```

### 2.2 数据模型

```swift
struct UpdateItem {
    let providerId: String
    let name: String
    let currentVersion: String
    let latestVersion: String?
    let kind: Kind          // .formula / .cask / .cli / .mas / .app
    let needsSudo: Bool     // 需提权 → 只标注，绝不自动 sudo
    let requiresLogin: Bool // 如 mas 未登录 → 降级只提示
}
```

### 2.3 异常态统一处理（三类）

1. **缺命令** → 该源整体隐藏（`isAvailable()` false）
2. **需 sudo** → 项上标注 + 提供可复制命令，不自动提权
3. **未登录/凭证态缺失** → 降级为只提示

### 2.4 双 Scene 形态（菜单栏 + 桌面主窗）

- **MenuBarExtra**：常驻角标（过期数）、Top 5 过期项轻量菜单、"打开主窗口"入口、退出
- **WindowGroup 主窗**：完整操作台——分组列表、勾选更新、按源开关、忽略规则管理、历史记录；设置走标准 `Settings` scene
- **无 Dock 图标**（Info.plist `LSUIElement=true`），保持 MacUpdater 式轻量感
- **已知坑**：accessory 模式下主窗抢不到焦点，打开时需 `NSApp.activate(ignoringOtherApps:)`（已知解法，骨架期就带上）
- 引擎层对"有几个窗口"完全无感，纯表现层加法

## 3. 更新源清单

### 第一批（MVP 范围）

| Provider | 探测命令 | 升级命令 | 备注 |
|----------|----------|----------|------|
| Homebrew formula | `brew outdated --json=v2` | `brew upgrade <name>` | JSON 一次拿全 |
| Homebrew cask | 同上（json v2 含 casks 段） | `brew upgrade --cask <name>` | 同一 Provider 两种 kind |
| Mac App Store | `mas outdated` | `mas upgrade <id>` | 未登录降级只提示 |
| npm 全局 | `npm outdated -g --json` | `npm install -g <name>@latest` | 装法不同可能需 sudo → 标注 |
| pipx | `pipx list --json` + PyPI 比对 | `pipx upgrade <name>` | |
| uv tool | `uv tool list` | `uv tool upgrade <name>` | |
| Cargo | `cargo install-update -l` | `cargo install-update <name>` | 依赖 cargo-update crate |
| RubyGems | `gem outdated` | `gem update <name>` | |
| Sparkle GUI 应用 | 扫 /Applications 读 Info.plist `SUFeedURL` → 拉 appcast XML 比版本 | MVP：一键唤起应用自更新；cask 装的走 cask 代更 | 最难的一块，见迭代 3 |

### 第二批（v1.0 后纯增量）

pnpm、Yarn、Bun、Deno、Go binaries、MacPorts、VS Code extensions、Docker 镜像、`softwareupdate -l`（系统更新，只提示）。

## 4. Sparkle 扫描专项（迭代 3 核心难点）

- 扫描范围：`/Applications` + `~/Applications`
- 判定：Info.plist 含 `SUFeedURL` → 读 `CFBundleShortVersionString`
- 拉取 appcast XML（Sparkle 命名空间），取 enclosure 的版本
- 版本比较：**复刻 `SUStandardVersionComparator` 语义**（1.2.10 vs 1.2.9 的自然序、beta/alpha 后缀处理），全项目唯一版本比较入口，禁止各 Provider 自带比较逻辑
- 容错：appcast 拉取失败/超时/格式异常 → 该应用标"未知"，不阻塞其他项
- MVP 边界：**提示 + 一键唤起**（`NSWorkspace.open` 让应用自更新）；只有 cask 装的应用才代更

## 5. 外置盘策略

| 项 | 位置 | 说明 |
|----|------|------|
| 项目本体 | `<项目目录>` | 含 SwiftPM `.build` |
| Xcode（完整版） | 外置 `Xcode.app` | 已就位（9/13 实测 swift 6.3.3），零内置占用 |
| npm/pip 缓存 | `<缓存目录>`（已有体系） | 沿用软链+env var |
| Rust 备用工具链（若试 Tauri 对照） | `RUSTUP_HOME`/`CARGO_HOME` 指外置 | 可选 |
| **成品 app（发布版）** | 内置 `/Applications` | 常驻+自启可靠性 |
| 成品 app（开发版） | 外置盘，手动启动 | 绕开 TCC |

**已知坑（BOSSHunter 前科）**：launchd 派生外置盘进程会被 TCC 拦（Operation not permitted，macOS 把外置卷当可移动卷）。对策：发布版放内置；自启走 `SMAppService` Login Item 而非 launchd。

## 6. 持久化设计

`~/Library/Application Support/upmac/state.json`：

```json
{
  "ignored": [{ "providerId": "brew", "name": "llvm", "scope": "forever" }],
  "snoozed": [{ "providerId": "npm", "name": "corepack", "until": "2026-09-20" }],
  "history": [{ "ts": "...", "items": [...], "result": "ok" }],
  "settings": { "scanIntervalMinutes": 360, "launchAtLogin": true }
}
```

无数据库；文件可备份、可手工编辑、可整文件删除重置。
