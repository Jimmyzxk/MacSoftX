#!/bin/bash
set -euo pipefail

# 项目根目录与构建路径
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
APP_DIR="${BUILD_DIR}/Macsoft X.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
SOURCE_BIN="${PROJECT_DIR}/.build/release/upmac"

echo "==> 组装 Macsoft X.app..."

# 1. 建立 bundle 目录结构
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 2. 拷贝可执行文件
if [ ! -f "${SOURCE_BIN}" ]; then
    echo "错误：未找到构建产物 ${SOURCE_BIN}，请先执行 swift build -c release" >&2
    exit 1
fi

cp "${SOURCE_BIN}" "${MACOS_DIR}/upmac"
chmod +x "${MACOS_DIR}/upmac"

# 3. 拷贝应用图标（Macsoft X logo，design/concepts/concept-c2 定稿）与菜单栏模板图标
if [ -f "${PROJECT_DIR}/Assets/AppIcon.icns" ]; then
    cp "${PROJECT_DIR}/Assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi
if [ -f "${PROJECT_DIR}/design/concepts/menuicon-template@1x.png" ]; then
    cp "${PROJECT_DIR}/design/concepts/menuicon-template@1x.png" "${RESOURCES_DIR}/"
    cp "${PROJECT_DIR}/design/concepts/menuicon-template@2x.png" "${RESOURCES_DIR}/"
fi

# 4. 写入 Info.plist 纯文本（支持 RELEASE_VERSION 环境变量覆盖版本号）
APP_VERSION="${RELEASE_VERSION:-1.0.0}"
cat > "${CONTENTS_DIR}/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleName</key>
    <string>Macsoft X</string>
    <key>CFBundleDisplayName</key>
    <string>Macsoft X</string>
    <key>CFBundleExecutable</key>
    <string>upmac</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.jimmyzxk.macsoftx</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "==> 执行 ad-hoc 签名..."
codesign --force --deep -s - "${APP_DIR}"

echo "==> Macsoft X.app 组装并签名完成：${APP_DIR}"
