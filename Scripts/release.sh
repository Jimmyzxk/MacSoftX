#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CASK_TEMPLATE="${PROJECT_DIR}/packaging/macsoftx.rb"

usage() {
    echo "用法: bash Scripts/release.sh <版本号>  (例如: 1.0.0)" >&2
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

VERSION="$1"

# 校验版本号格式（简单）
if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
    echo "错误：版本号格式不合法，应为 x.y.z" >&2
    exit 1
fi

echo "==> 校验 git 工作区是否干净..."
# 忽略构建产物（build/ 与 .build/）避免 DMG/二进制干扰发布校验
if ! git diff-index --quiet HEAD -- ':(exclude)build' ':(exclude).build' 2>/dev/null; then
    echo "错误：工作区有未提交改动，请先提交或 stash" >&2
    git status --porcelain -- ':(exclude)build' ':(exclude).build' >&2 || true
    exit 1
fi
if [ -n "$(git status --porcelain -- ':(exclude)build' ':(exclude).build' 2>/dev/null || true)" ]; then
    echo "错误：工作区有未跟踪文件或未提交改动" >&2
    git status --porcelain -- ':(exclude)build' ':(exclude).build' >&2
    exit 1
fi

echo "==> 版本号: ${VERSION}"

echo "==> 构建 release..."
swift build -c release

echo "==> 打包 .app 与 DMG（版本 ${VERSION}）..."
export RELEASE_VERSION="${VERSION}"
bash "${PROJECT_DIR}/Scripts/make-app.sh"
bash "${PROJECT_DIR}/Scripts/make-dmg.sh"

DMG_PATH="${PROJECT_DIR}/build/MacsoftX-${VERSION}.dmg"
if [ ! -f "${DMG_PATH}" ]; then
    echo "错误：未找到 DMG ${DMG_PATH}" >&2
    exit 1
fi

echo "==> 计算 SHA256..."
SHA256="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
echo "    SHA256: ${SHA256}"

if [ ! -f "${CASK_TEMPLATE}" ]; then
    echo "错误：未找到 cask 模板 ${CASK_TEMPLATE}" >&2
    exit 1
fi

echo "==> 更新 cask 模板: ${CASK_TEMPLATE}"
# 使用备份后缀兼容 macOS sed
sed -i '' "s/{{VERSION}}/${VERSION}/g" "${CASK_TEMPLATE}" 2>/dev/null || sed -i "s/{{VERSION}}/${VERSION}/g" "${CASK_TEMPLATE}"
sed -i '' "s/{{SHA256}}/${SHA256}/g" "${CASK_TEMPLATE}" 2>/dev/null || sed -i "s/{{SHA256}}/${SHA256}/g" "${CASK_TEMPLATE}"

echo ""
echo "==> 本地构建与模板更新完成"
echo "    DMG: ${DMG_PATH}"
echo "    SHA256: ${SHA256}"
echo "    Cask: ${CASK_TEMPLATE}"
echo ""
echo "==> 后续需手动执行（需 GitHub 账号与 tap 仓库）："
echo "    1. git tag v${VERSION} && git push origin v${VERSION}"
echo "    2. gh release create v${VERSION} \"${DMG_PATH}\" --title \"v${VERSION}\" --notes \"Macsoft X ${VERSION}\""
echo "       # 或手动在 GitHub 创建 Release 并上传 DMG"
echo "    3. 将更新后的 ${CASK_TEMPLATE} 提交到 homebrew-tap 仓库："
echo "       git -C <tap-repo> add Casks/macsoftx.rb && git -C <tap-repo> commit -m \"macsoftx ${VERSION}\" && git -C <tap-repo> push"
echo "    4. 验证：brew tap <ORG>/tap && brew install --cask macsoftx --no-quarantine"
echo ""
echo "    TODO: 将 <ORG> 替换为实际 GitHub 组织名，URL 中的 <ORG>/macsoftx 亦需同步替换"
echo "==> 完成"
