# 12 · 分发方案（无证书版）

> 2026-09-14。用户暂无 Apple Developer 账号（$99/年），需在本条件下完成分发。

## 现状取证

| 项 | 实测结果 |
|---|---|
| 本机签名证书 | **0 identities**（`security find-identity -v -p codesigning` 验证） |
| 当前签名方式 | ad-hoc（`codesign -s -`，打包脚本已做） |
| Gatekeeper 判定 | `spctl --assess` → **rejected**（他人下载双击会被拦） |
| Homebrew bypass 机制 | `--no-quarantine` / `HOMEBREW_CASK_OPTS`（源码 env_config.rb 实锤） |

## 方案 A：自建 Homebrew Tap（推荐，立即可做）

**用户侧体验**：
```bash
brew tap <用户名>/tap
brew install --cask macsoftx
```
**关键点**：cask 定义中不能声明 quarantine 行为（那是用户侧 flag），但 tap 文档可指导用户用 `--no-quarantine`；或者更简单的做法——**分发 DMG + 文档说明右键打开**。

**实施清单**：
1. GitHub 仓库（公开，MIT）——代码已在本地 git，需推送到 GitHub
2. 建 `homebrew-tap` 仓库，写 `Casks/macsoftx.rb`：
   - url 指向 Release 的 DMG/zip
   - sha256 校验
   - `app "Macsoft X.app"`
   - 版本号自动从 release tag 读取
3. 发布流程脚本：`Scripts/release.sh <version>`——构建 → 打包 DMG → 计算 sha256 → 更新 cask 文件 → 建 GitHub Release
4. README 补充安装说明（含首次打开被拦时的右键打开指引）

**代价**：用户首次可能需要 `--no-quarantine` 或右键打开（一次性的）；但对技术用户完全可接受。
**收益**：零成本、可自动化、专业感（开源工具标配）。

## 方案 B：签名延期（等有证书时升级）

将来购得 Developer ID（$99/年）后：
1. 对 .app 签名：`codesign --deep --force --options runtime --sign "Developer ID Application: <Name> (<TeamID>)"`（需要 entitlements 硬运行时）
2. 公证：`xcrun notarytool submit <dmg> --apple-id <id> --team-id <tid> --password <app-specific-pw>` + `stapler staple`
3. 打包脚本增加 `--sign` 分支，无证书时保持 ad-hoc
**这一步不影响方案 A 的实施**——两条路可共存，未来无缝升级。

## 方案 C：暂不做的选项

- 自签名证书（不被信任，等于没签）
- 免费 Apple ID 开发证书（只限本机调试，分发无意义）
- 关闭 Gatekeeper 全局（不可取，破坏用户系统安全）

## 实施顺序（本轮）

1. **先做 DMG 打包能力**（不依赖 GitHub）：`Scripts/make-dmg.sh` 生成带背景/应用文件夹快捷方式的 DMG——这是任何分发方式都需要的基础
2. **写安装说明**（README 分发区块 + docs/13-install.md）：含 dmgs 双击被拦时的指引（右键→打开 / 系统设置→隐私与安全性→仍要打开）
3. **GitHub 发布**：需用户提供账号（或先本地跑通流程，等账号就绪一键推）
4. **cask 模板**：写好 `macsoftx.rb` 模板与 release 脚本，等仓库就绪即可用

**分发渠道**：GitHub 公开仓库（MIT），或 DMG 本地分发。
