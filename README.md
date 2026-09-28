# Macsoft X

一个面板，看全 Mac 上的所有软件更新。

![macOS](https://img.shields.io/badge/macOS-15%2B-000000?style=flat&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat&logo=swift&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green?style=flat)
[![CI](https://github.com/Jimmyzxk/MacSoftX/actions/workflows/ci.yml/badge.svg)](https://github.com/Jimmyzxk/MacSoftX/actions/workflows/ci.yml)

## 问题

Mac 上的软件来自四个渠道，各管各的：

| 渠道 | 怎么更新 |
|---|---|
| 手动拖进 `/Applications` 的应用 | 打开应用，在菜单里点「检查更新」 |
| App Store 应用 | 只能靠 App Store |
| Homebrew 装的 | `brew upgrade` |
| 命令行工具（npm / gem / uv） | 各自的升级命令 |

每个工具都只认自己装过的东西。所以「我这台机器上还有哪些软件该更新」，得挨个去问一遍。

最麻烦的是第一类。手动拖进来的应用没有统一的更新机制，只能一个个打开、点菜单、等它自己检查，或者干脆忘了。而这些往往正是你天天在用的软件。

## 做法

Macsoft X 把这些渠道收进同一个菜单栏面板，并且**真的把更新执行掉**：

- 扫描时同时问四个渠道，谁有更新一目了然
- 手动安装的应用，从 Homebrew 的 cask 定义里查到最新版本号做比对。发现过期后执行 `brew install --cask --force` 直接更新到最新版，不用你自己去官网下载
- 更新完由 Homebrew 接管后续管理，之后就能走 `brew upgrade` 了

只有两种情况会退回手动：cask 里找不到这个应用的定义（打开下载页），或者它自带更新器（启动应用让它自己检查）。这两种情况面板都会明确标出来，不会假装已经更新。

## 能力

| 能力 | 说明 |
|------|------|
| Homebrew | formula 与 cask 更新 |
| npm | 全局包更新 |
| RubyGems | 更新，系统自带 gem 自动剔除 |
| uv | tool 升级 |
| Mac App Store | 经 `mas` 检测与更新（未安装可在应用内一键装） |
| Sparkle 应用 | 解析 appcast 检测更新 |
| 手动安装的应用 | 经 Cask API 比对版本，用 `brew install --cask --force` 直接更新 |
| 软件清单 | 全盘扫描，标注每项的来源与是否被包管理器托管 |
| 干净卸载 | 托管的走包管理器卸载，游离的移入废纸篓 |
| 残留清理 | 扫描已卸载软件遗留的配置、缓存、日志、容器 |
| 通知 | 仅在新出现可更新项时提醒，不重复轰炸 |
| 定时扫描 | 可配置间隔，后台自动执行 |
| 忽略规则 | 按来源和名称永久或临时忽略 |
| 开机自启 | `SMAppService` |

国内网络下，npm 与 RubyGems 的只读扫描会自动使用国内镜像（不改动你的 `~/.npmrc` 和 gem sources），实测把 gem 扫描从 97 秒降到 28 秒。

## 界面

菜单栏常驻一个循环徽记图标，旁边是待更新数字徽标，点开是玻璃质感气泡面板。

主窗左侧是任务导航（待更新 / 全部软件 / 手动安装 / 清理 / 已忽略），顶部工具栏提供搜索、排序和手动扫描，右侧可展开独立详情浮窗。

设计规范见 [docs/08-design-spec.md](docs/08-design-spec.md)，含文案规则与组件 token。

## 安装

### 下载安装包

从 [Releases](https://github.com/Jimmyzxk/MacSoftX/releases/latest) 下载 `MacsoftX-1.0.0.dmg`，打开后把 Macsoft X 拖进「应用程序」。

应用未做 Apple 公证（需 99 美元/年的开发者账号），首次打开会被 Gatekeeper 拦下。在「系统设置 → 隐私与安全性」里点「仍要打开」，或执行：

```bash
xattr -d com.apple.quarantine /Applications/Macsoft\ X.app
```

需要 macOS 15 或更高。

### 从源码构建

```bash
git clone https://github.com/Jimmyzxk/MacSoftX.git
cd MacSoftX
swift build -c release
./Scripts/make-app.sh
```

产物在 `build/Macsoft X.app`。需要 macOS 15+ 和 Xcode 15+，项目零第三方依赖，只用系统框架。

### 可选依赖

以下工具全部可选，缺少哪个就自动跳过对应来源，不影响其他功能：

| 工具 | 用途 | 安装 |
|---|---|---|
| Homebrew | formula 与 cask 源 | 官网安装 |
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
