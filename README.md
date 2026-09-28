# Macsoft X

> 一个面板，看全你 Mac 上的所有软件更新。

Mac 菜单栏软件管理器：把 **GUI 应用、App Store 应用、终端里的 CLI 包管理器** 聚到同一个面板，逐项或一键更新，并附带软件清单、干净卸载与残留清理。

![macOS](https://img.shields.io/badge/macOS-15%2B-000000?style=flat&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat&logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=flat)
[![CI](https://github.com/Jimmyzxk/MacSoftX/actions/workflows/ci.yml/badge.svg)](https://github.com/Jimmyzxk/MacSoftX/actions/workflows/ci.yml)

## 为什么做它

Mac 的软件散落在三个互不相通的地方：

- **手动拖进 `/Applications` 的应用**——没有统一入口，过期了只有打开应用才知道
- **App Store 应用**——`mas` 能管，但要单独装命令行工具
- **终端里的包管理器**（npm / gem / uv / brew）——完全在另一个世界，窗口最小化就忘了

现有的工具只覆盖其中一块。**Macsoft X 的价值在于：把它们聚合起来，并且能真的执行更新。**

## 能力

| 能力 | 说明 |
|------|------|
| Homebrew | formula 与 cask 更新 |
| npm | 全局包更新 |
| RubyGems | 更新，系统自带 gem 自动剔除 |
| uv | tool 升级 |
| Mac App Store | 经 `mas` 检测与更新（未安装可在应用内一键装） |
| Sparkle 应用 | 解析 appcast 检测更新 |
| **手动安装的应用** | 用 Cask API 查版本，用 `brew install --cask --force` **直接更新**（不跳转到下载页） |
| 软件清单 | 全盘扫描，标注每项的来源与是否被包管理器托管 |
| 干净卸载 | 托管的走包管理器卸载，游离的移入废纸篓 |
| 残留清理 | 扫描已卸载软件遗留的配置、缓存、日志、容器 |
| 通知 | 仅在**出现新**可更新项时提醒，不重复轰炸 |
| 定时扫描 | 可配置间隔，后台自动执行 |
| 忽略规则 | 按来源+名称永久或临时忽略 |
| 开机自启 | `SMAppService` |

国内网络环境下，npm 与 RubyGems 的**只读扫描会自动使用国内镜像**（不修改你的 `~/.npmrc` 与 gem sources），实测可把 gem 扫描从 97 秒降到 28 秒。

## 界面

- **菜单栏**——循环徽记图标 + 待更新数字徽标，点开是玻璃质感气泡面板
- **主窗**——侧栏任务导航（待更新 / 全部软件 / 手动安装 / 清理 / 已忽略）+ 工具栏（搜索、排序、扫描）+ 行式列表 + 独立详情浮窗

设计规范见 [docs/08-design-spec.md](docs/08-design-spec.md)，含文案规则与组件 token。

## 安装

### 自行构建

```bash
git clone https://github.com/Jimmyzxk/MacSoftX.git
cd MacSoftX
swift build -c release
./Scripts/make-app.sh
```

产物在 `build/Macsoft X.app`，拖入「应用程序」即可。

**要求**：macOS 15+、Xcode 15+。项目**零第三方 SwiftPM 依赖**，只使用系统框架。

未配置 Apple Developer ID，产物为 ad-hoc 签名。首次打开若被 Gatekeeper 拦截，在「系统设置 - 隐私与安全性」中点「仍要打开」，或：

```bash
xattr -d com.apple.quarantine /Applications/Macsoft\ X.app
```

### 可选依赖

以下工具**全部可选**，缺少哪个就自动跳过对应来源，不影响其他功能：

| 工具 | 用途 | 安装 |
|---|---|---|
| Homebrew | formula/cask 源 | 官网安装 |
| `mas` | App Store 源 | 应用内一键安装，或 `brew install mas` |
| Node.js | npm 源 | 官网安装 |
| Ruby | gem 源 | 系统自带 |
| `uv` | uv tool 源 | 官网安装 |

## 命令行

除 GUI 外提供 JSON 输出，便于脚本化与排查：

```bash
.build/debug/upmac --scan          # 全源扫描
.build/debug/upmac --scan-fast     # 跳过 cask 网络检测的快速扫描
.build/debug/upmac --inventory     # 全部已装软件清单
```

## 架构

```
采集层  9 个 Provider（brew / mas / npm / gem / uv / apps(Sparkle+Cask API)）
核心层  归一化 · 版本比较 · 执行队列 · 状态持久化
表现层  菜单栏气泡 + 主窗 + 设置
基础层  ShellRunner · 通知 · 定时扫描
```

新增一个包管理器只需实现 `UpdateProvider` 协议（见 [CONTRIBUTING.md](CONTRIBUTING.md)），UI 与批量更新自动生效。

### 安全约束

- 删除**一律移入废纸篓**，绝不 `rm`（全仓零 `removeItem`）
- 命令执行**一律用参数数组**，绝不拼 shell 字符串
- 删除前做 **realpath 边界校验**，拒绝符号链接、拒绝越界路径
- 状态文件**单一写入口加锁**，避免并发丢失
- 零遥测、零外部依赖、隐私数据不出本机（仅向 Homebrew 公共 API 请求应用版本号）

## 开发

```bash
swift build -Xswiftc -warnings-as-errors   # 零警告构建
swift test                                 # 132 项单元测试
```

## 文档

| 文档 | 内容 |
|------|------|
| [docs/01-architecture.md](docs/01-architecture.md) | 架构与 Provider 协议 |
| [docs/08-design-spec.md](docs/08-design-spec.md) | 设计规范（强制契约） |
| [docs/13-install.md](docs/13-install.md) | 安装与分发 |
| [docs/14-audit-20260924.md](docs/14-audit-20260924.md) | 代码审计报告 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 贡献指南与安全红线 |

## 许可

[MIT](LICENSE)
