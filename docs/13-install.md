# 13 · 安装说明

> 适用于 Macsoft X 0.1.0+，未使用 Apple 付费证书签名属开源项目常见情况，本页说明如何安全安装与卸载。

## 系统要求

- macOS 26.0 及以上
- Intel / Apple Silicon 均支持

## 方式一（推荐）：Homebrew 安装

```bash
# 首次使用需先添加 tap（将 <待定> 替换为实际 GitHub 组织名）
brew tap <待定>/tap

# 安装（ad-hoc 签名需加 --no-quarantine 跳过 Gatekeeper 隔离）
brew install --cask macsoftx --no-quarantine

# 更新
brew upgrade --cask macsoftx
```

> 说明：`--no-quarantine` 仅对本次安装生效，不会关闭系统 Gatekeeper，等价于首次运行时的“右键 → 打开”一次授权。

## 方式二：下载 DMG 手动安装

1. 从 Releases 下载 `MacsoftX-<version>.dmg`
2. 双击打开 DMG，将 `Macsoft X.app` 拖入 `Applications` 快捷方式
3. **首次打开会有一次系统拦截（实测流程，照做只需一次）**：
   - 双击应用后，弹出对话框：**「未打开"Macsoft X"——Apple 无法验证"Macsoft X"是否包含可能危害 Mac 安全或泄漏隐私的恶意软件」**
   - ⚠️ 点击「**完成**」（**不要点「移到废纸篓」**）
   - 打开 **系统设置 → 隐私与安全性** → 下滑到「安全性」区域 → 会看到「已阻止使用"Macsoft X"，因为来自身份不明的开发者」→ 点击「**仍要打开**」→ 输入指纹/密码确认
   - 再打开一次应用，此后永久正常
4. 备选（终端一行命令，效果相同且更省事）：
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Macsoft X.app"
   ```
   执行后再双击应用即可，不会出现任何拦截。

## 为什么需要这一步

Macsoft X 当前使用 ad-hoc 签名（`codesign -s -`），未使用 Apple Developer ID 付费证书签名，因此首次在他人机器上会被 Gatekeeper 拦截为“已阻止”。这是开源项目常见情况，不代表不安全。

安全性说明：

- 源码公开可审计（MIT 协议）
- 本地扫描/更新均在用户机器上通过系统命令执行，无网络上传用户数据
- 后续若购得证书，将自动切换为 Developer ID 签名并公证，用户无感知升级

## 卸载

- 应用内：`清理` 页 → 选择 `Macsoft X` → 移入废纸篓
- Homebrew 安装的：

```bash
brew uninstall --cask macsoftx
```

- 手动安装的：直接将 `/Applications/Macsoft X.app` 移入废纸篓

`~/Library/Application Support/upmac/state.json` 等用户数据可按需手动删除。

## 常见问题

**Q：通知权限如何开启？**
A：首次发现可更新项时系统会弹出通知授权请求；若误点拒绝，可在 设置 → 通知 → Macsoft X 中重新开启，或点击应用设置页的“前往系统设置”。

**Q：扫描不到外置盘 /Volumes 上的应用？**
A：需授予“完全磁盘访问权限”或在设置 → 扫描范围中添加对应 `/Volumes/*/Applications` 目录，并确保磁盘可写且非只读 DMG。

**Q：安装后提示“已损坏”？**
A：通常为隔离属性导致，执行 `xattr -dr com.apple.quarantine "/Applications/Macsoft X.app"` 后重试，或改用 `brew install --no-quarantine` 重装。

**Q：如何反馈问题？**
A：[GitHub Issues](https://github.com/<ORG>/macsoftx/issues) 提交日志与系统版本，或本地运行 `.build/debug/upmac --scan` 贴出 JSON（脱敏后）。
