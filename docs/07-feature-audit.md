# 07 · 功能审计与「清理」模块设计（AppCleaner 派对标）

> 触发：用户复核功能列表完整性 + 指定研究 AppCleaner 类软件设计。
> 对标对象：AppCleaner（FreeMacSoft，免费闭源）、Pearcleaner（alienator88，fair-code 源码可见）、CleanMyMac X、Version Tracker。

## 1. 功能完整度审计（截至迭代 2 收官）

### 已上线
- 扫描更新：brew（formula+cask）+ mas，逐项/全部更新，搜索/过滤/排序，右键菜单，错误横幅
- 全部软件清单：/Applications 扫描 + 8 源交叉标记（受管/游离），真图标，Finder 揭示
- 菜单栏玻璃气泡；--scan / --inventory 验收通道；主线程规约架构

### 规划中未上线
- 迭代 3：CLI 全家桶过期更新（npm/pipx/uv/cargo/gem）
- 迭代 4：**Sparkle GUI 应用更新扫描**（⚠️ 产品核心承诺的最大缺口——目前普通 App 的更新检测还没有）
- 迭代 5：通知 + 忽略规则 + 定时扫描（MVP 口径）
- 迭代 6：开机自启；迭代 7：签名/公证/分发

### 对标缺口（成熟产品有、我们没有）
| 能力 | 对标来源 | 级别 | 说明 |
|------|----------|------|------|
| 残留清扫/干净卸载 | AppCleaner/Pearcleaner | **P1** | 本文档 §2 专项设计；与"规整"诉求直接对应 |
| Smart Delete（垃圾桶监听） | AppCleaner/Pearcleaner Sentinel | P1.5 | 清理模块的体验灵魂，拖进废纸篓自动提示清扫残留 |
| 安全维度（CVE + 签名/公证校验展示） | Version Tracker | P1 | 安全更新标红、签名缺失警示 |
| 导出清单（Brewfile/CSV） | Applite/UniGetUI | P1 | 迁移/备份场景，实现成本低 |
| 自定义扫描目录 | 用户需求 | P1 | **用于覆盖非标准安装位置的应用（如装在自定义目录或外置卷）** |
| 自动更新模式（白名单静默更） | MacUpdater/UniGetUI | P2 | 危险与便利并存，默认关闭 |
| AI 更新风险评估/变更日志摘要 | 无竞品 | **P2 差异化** | 无人在做；可接本地 LLM 网关 |
| 更新历史与趋势 | CleanMyMac | P2 | |
| 卸载后大小统计 | Nektony | P3 | 性能成本高 |

## 2. 「清理」模块设计（AppCleaner 派精髓 × upmac 结构）

### 2.1 三个入口（动线）

1. **清单页右键**「清理此应用…」→ 进入清理流（受管/游离项都可）
2. **侧栏「清理」页**：拖放靶区（玻璃大靶，AppCleaner 经典交互）+ 残留清扫按钮
3. **Smart Delete**（可选开关）：后台监听废纸篓，检测到 .app 入桶 → 通知提示"发现残留 N 个文件，是否清扫"

### 2.2 清理流（三步，全部双确认）

```
选应用 → 扫描散落文件（按目录分组勾选列表：复选框+路径+大小）
       → 汇总确认条：「已选 86 项 · 1.2 GB · 应用本体将移入废纸篓」[取消][移除]
```

- 扫描规则库（自研，每应用生成候选路径集）：`~/Library/Preferences/<bundleid>.plist`、`~/Library/Application Support/<name>`、`~/Library/Caches/<bundleid>`、`Saved Application State`、`LaunchAgents/LaunchDaemons` 中引用该路径的 plist、`Containers/Group Containers`（沙盒应用）、日志与 CrashReporter 目录
- **安全红线**：删除一律移入废纸篓（可恢复），绝不 rm -rf；bundle 本体与其签名/公证校验通过才允许；系统/苹果自家应用禁扫；删除前列出全部路径供人工复核；二次确认必须展示总大小与文件数
- 受管项走正规渠道：cask → `brew uninstall --cask`（其自带卸载脚本优先），formula → `brew uninstall`；npm/pipx 等同理——**包管理器管的走包管理器**，只有"游离应用"走文件级清扫

### 2.3 残留清扫（孤儿文件，Pearcleaner 式）

- 扫描规则库中的路径命中、但对应应用已不存在的文件 → 列表（路径+大小+最后修改时间）→ 勾选 → 移入废纸篓
- 结果分组展示 + "全选安全项"快捷（低风险类如 Caches 默认勾选，Preferences 默认不勾）

### 2.4 UI 要点（Liquid Glass 版 AppCleaner）

- 拖放靶区：中央大圆角玻璃靶 + 虚线描边，拖入时环脉动；无拖放时显示「清理」页统计（可清扫残留 N 项 · 约 X GB）
- 文件清单：行式 checkbox 列表，等宽字体路径 + 右对齐大小；分组折叠（Library 各子目录）
- 完成动效：移除后勾选动画 + "已腾出 X GB" 庆祝态（CleanMyMac 的任务感）
- reduceMotion 降级

## 3. License 红线

Pearcleaner 是 **fair-code（源码可见但非 OSI 开源）**，AppCleaner 闭源——**只借鉴交互与规则思路（路径模式属事实知识），一律不抄代码**。upmac 清理引擎自研，保持 MIT 干净。

## 4. UI 演进三阶段（回应"UI 还有很大进化空间"）

| 阶段 | 内容 | 触达 |
|------|------|------|
| v3.5 打磨 | 行内元数据丰富（安装日期/大小按需懒加载）、扫描进度按源可视化、骨架屏、图标补全（清单页 grid 视图） | 密度与质感 |
| v4 效率 | ⌘K 命令面板（全局动作：更新 X/扫描/切页/清理 Y）、全键盘导航、Brewfile 导出 | Raycast 化 |
| v5 智能 | AI 更新风险徽章（变更日志摘要 + breaking change 提示，可接本地 LLM 网关）、CVE 联动标红、新鲜度趋势 sparkline | 差异化护城河 |

## 5. 迭代重排建议

原路线：3 CLI 全家桶 → 4 Sparkle 扫描 → 5 通知+忽略+定时 MVP → 6 自启 → 7 打磨。

建议两种排法（用户二选一）：
- **A（产品完整优先，推荐）**：3 Sparkle 扫描（补核心承诺）→ 4 清理模块（本文档）→ 5 CLI 全家桶 → 6 通知+忽略+定时+自启 → 7 打磨发布
- **B（规整优先）**：3 清理模块 → 4 Sparkle 扫描 → 后同 A

MVP 口径相应顺延：能看能更能清能提示 = 迭代 5 后。
