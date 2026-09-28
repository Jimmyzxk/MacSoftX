#!/bin/bash
set -euo pipefail

# Macsoft X DMG 打包脚本
# 前置：make-app.sh 产出 build/Macsoft X.app 并 ad-hoc 签名

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_NAME="Macsoft X.app"
APP_DIR="${BUILD_DIR}/${APP_NAME}"

echo "==> 检查并构建 ${APP_NAME}..."
bash "${PROJECT_DIR}/Scripts/make-app.sh"

if [ ! -d "${APP_DIR}" ]; then
    echo "错误：未找到 ${APP_DIR}" >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "${APP_DIR}/Contents/Info.plist" 2>/dev/null || echo "0.1.0")"
DMG_NAME="MacsoftX-${VERSION}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"

echo "==> 准备 DMG 临时目录..."
STAGING_DIR="$(mktemp -d "${BUILD_DIR}/dmg-staging-XXXXXX")"
# 保证退出时清理
cleanup() {
    rm -rf "${STAGING_DIR}"
}
trap cleanup EXIT

# 复制 .app
cp -R "${APP_DIR}" "${STAGING_DIR}/"
# 创建指向 /Applications 的符号链接（经典拖拽布局）
ln -s /Applications "${STAGING_DIR}/Applications"

echo "==> 创建 DMG: ${DMG_PATH} (volname: Macsoft X, version: ${VERSION})"
# 幂等：覆盖旧 DMG
rm -f "${DMG_PATH}"
hdiutil create -volname "Macsoft X" -srcfolder "${STAGING_DIR}" -ov -format UDZO "${DMG_PATH}" > /dev/null

DMG_SIZE="$(du -h "${DMG_PATH}" | cut -f1)"
echo "==> DMG 已生成：${DMG_PATH} (${DMG_SIZE})"
echo "==> 完成，可直接分发或挂载验证"

# 清理由 trap 完成
trap - EXIT
rm -rf "${STAGING_DIR}"
