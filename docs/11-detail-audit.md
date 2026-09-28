# 11 · 优化清单（细节体检报告）

> 2026-09-14 系统体检。来源：代码审查 + 真机实测。分级：P0=必须修，P1=该修，P2=锦上添花。

## 一、代码健康（P1）

| 问题 | 证据 | 处置 |
|------|------|------|
| **死代码 6 文件 ~1800 行** | CockpitInspectorView(573)/UpdateCardView/RingGaugeView/UpdateListView/Theme/MockBrewProvider 零引用 | 删除（保留 MockBrewProvider 供测试则移入 Tests） |
| CockpitView 997 行臃肿 | 单文件承载侧栏+工具栏+内容+详情路由 | 拆分：SidebarView / ContentRouter / Toolbar（P2） |
| ShellRunner 线程模型隐患 | 阻塞协作线程（迭代 1 起记录） | 迭代 6 用 terminationHandler 异步化根治 |

## 二、性能（P0/P1）

| 问题 | 实测 | 处置 |
|------|------|------|
| **首次扫描 60 秒** | 冷启动 Cask 网络请求逐个走 8s 超时；缓存命中后 3.1s | **P0**：Cask 检测移出扫描主路径——扫描先返回本地数据秒出，Cask 检测异步后台补齐（渐进式显示）；或并发提高到 8 并加 3s 超时 |
| 清单扫描 0.65s | 正常 | 保持 |
| 各源命令耗时 brew 0.8s/gem 2.3s/npm 1.5s/uv 0.6s/mas 0.04s | 正常，并发已做 | 保持 |

## 三、功能缺口（迭代 6）✅ 已补齐（2026-09-14）

- ✅ 通知提醒（UNUserNotificationCenter 权限/快照去重/点击打开主窗）
- ✅ 定时自动扫描（默认 6h，设置可配：关闭/1h/6h/12h/每天）
- ✅ 忽略规则（右键三档：跳过本次/稍后7天/永久；侧栏已忽略真实页面+恢复；state.json 持久化+过期自动清理）
- ✅ 开机自启（SMAppService 已有实现，设置页开关）

## 四、交互细节（P1）

| 问题 | 处置 |
|------|------|
| 批量更新不可取消、无总进度 | updateAll 增加当前项显示「正在更新 2/5: Spotify」+ 取消按钮（Task cancellation） |
| 清理页 Smart Delete 缺失 | 迭代 4.5：监听废纸篓，应用被拖入后提示清残留 |
| 详情浮窗无键盘操作 | Esc 关闭（已有）、⌘W 关闭、↑↓ 切换项（P2） |
| 首扫无进度反馈 | 渐进式：各源先到先显示（现在等全部完成才渲染） |

## 五、分发准备（迭代 7 范围）

- 应用图标已接（C2）、品牌完整（Macsoft X）
- **待办**：Developer ID 签名 + 公证（当前 ad-hoc 签名，他人下载会被 Gatekeeper 拦）
- 待办：安装包（DMG 或 zip）、README、License（MIT 已定）
- 已验证：零硬编码本地路径、运行时走标准目录

## 六、待观察

- Telegram 类版本字段怪癖（已有跨度兜底，规则有限）
- caskCache 与 state.json 同文件竞态（P2：拆独立文件）
- 个别 cask 的 artifacts 是 pkg 型（token 护栏已兜底）
