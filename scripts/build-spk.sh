#!/usr/bin/env bash
# =============================================================================
# 构建 Octop 群晖 Synology 安装包 (.spk)
#
# 参考飞牛 FPK 的设计模式：
# - 从 pyproject.toml 读取版本
# - 支持多架构（x86_64 / aarch64）
# - 模板化生成 INFO、向导、配置
# - 可在本地或 GitHub Actions 中运行
#
# 用法：
#   bash scripts/build-spk.sh              # 构建当前架构 SPK
#   bash scripts/build-spk.sh x86_64       # 指定架构
#   bash scripts/build-spk.sh aarch64
#   ARCH=all bash scripts/build-spk.sh     # 双架构都构建
#
# 环境变量：
#   SPK_NAME_PREFIX   输出文件名前缀，默认 "Octop"
#   SPK_ITER          迭代号，如 SPK_ITER=01 生成 ...-01.spk
#   SPK_ARCH          目标架构：x86_64 / aarch64 / all
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"

# 使用仓库内临时目录
TMP="$(mktemp -d "$ROOT/.buildtmp.XXXXXX")"
cleanup() { rm -rf "$TMP" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# 从 pyproject.toml 读取版本（PEP 440，如 1.0.2b8）
VER="$(sed -nE 's/^version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$ROOT/pyproject.toml" | head -1)"
[ -n "$VER" ] || { echo "❌ 无法从 pyproject.toml 解析版本"; exit 1; }
case "$VER" in
  *[[:space:]]*|*[\"\']*) echo "❌ 解析到的版本非法: $VER"; exit 1 ;;
esac

# Synology 版本号只取 x.y.z（忽略 beta 后缀）
# 1.0.2b8 -> 1.0.2，1.0.2 -> 1.0.2
SPK_VER="$(echo "$VER" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+).*/\1/')"
# 打包用完整版本号（去掉引号）
PKG_VER="${SPK_VER}-1"  # Synology 习惯：x.y.z-发布序号

echo "[build-spk] Octop 版本: $VER -> SPK 版本: $PKG_VER"

# 架构处理
ARCH_INPUT="${1:-${SPK_ARCH:-}}"
case "$ARCH_INPUT" in
  x86_64|amd64) ARCH_LIST="x86_64" ;;
  aarch64|arm64) ARCH_LIST="aarch64" ;;
  all|"") ARCH_LIST="x86_64 aarch64" ;;
  *) echo "❌ 未知架构: $ARCH_INPUT (支持: x86_64, aarch64, all)"; exit 1 ;;
esac

# 输出前缀与迭代后缀
PREFIX="${SPK_NAME_PREFIX:-Octop}"
ITER_SUFFIX=""
if [ -n "${SPK_ITER:-}" ]; then
  ITER_SUFFIX="-$SPK_ITER"
fi
echo "[build-spk] 包名前缀: $PREFIX, 迭代后缀: ${ITER_SUFFIX:-<none>}"

mkdir -p "$OUT"

build_arch() {
  local TARGET_ARCH="$1"
  local BUILD_DIR="$TMP/$TARGET_ARCH"

  echo ">>> 构建 $TARGET_ARCH ..."
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"/{scripts,conf,icons,ui}

  # ========== 复制静态文件 ==========
  cp "$ROOT/scripts/preinst" "$BUILD_DIR/scripts/"
  cp "$ROOT/scripts/postinst" "$BUILD_DIR/scripts/"
  cp "$ROOT/scripts/preuninst" "$BUILD_DIR/scripts/"
  cp "$ROOT/scripts/postuninst" "$BUILD_DIR/scripts/"
  cp "$ROOT/scripts/start-stop-status" "$BUILD_DIR/scripts/"
  chmod +x "$BUILD_DIR/scripts/"*

  cp "$ROOT/docker-compose.yml" "$BUILD_DIR/"
  cp "$ROOT/conf/.env.template" "$BUILD_DIR/conf/"
  cp "$ROOT/icons/PACKAGE_ICON.PNG" "$BUILD_DIR/icons/"
  cp "$ROOT/icons/PACKAGE_ICON_256.PNG" "$BUILD_DIR/icons/"
  cp "$ROOT/LICENSE" "$BUILD_DIR/" 2>/dev/null || cp "$ROOT/../LICENSE" "$BUILD_DIR/" 2>/dev/null || true

  # ========== 生成 INFO（核心元数据）==========
  local SYNO_ARCH
  case "$TARGET_ARCH" in
    x86_64) SYNO_ARCH="x86_64" ;;
    aarch64) SYNO_ARCH="aarch64" ;;
  esac

  cat > "$BUILD_DIR/INFO" << EOF
package="Octop"
version="${PKG_VER}${ITER_SUFFIX}"
arch="${SYNO_ARCH}"
maintainer="DingXiaoWu0512"
description="腾讯开源的自托管多智能体 AI 助手平台 — Web 控制台、CLI、IM 渠道、定时任务，数据全部本地存储。"
description_cht="騰訊開源的自託管多智能體 AI 助手平台 — Web 控制台、CLI、IM 渠道、定時任務，資料全部本地儲存。"
description_enu="Tencent's self-hosted multi-agent AI assistant platform — Web console, CLI, IM channels, scheduled tasks, all data stored locally."
startable="yes"
displayname="Octop"
beta="no"
silent_install="no"
silent_upgrade="no"
silent_uninstall="no"
install_dep_packages="docker"
install_reboot="no"
install_unattended="no"
thirdparty="yes"
os_min_ver="7.0-40000"
conf_dir="/var/packages/Octop/target/conf"
adminport="8088"
adminurl="/"
fw_port="8088"
helpurl="https://github.com/TencentCloud/Octop"
report_url=""
supporturl="https://github.com/TencentCloud/Octop/issues"
changelog="基于 Octop ${VER} 打包，支持 Docker 部署"
builddate="$(date +%Y-%m-%d)"
EOF

  # ========== 生成向导配置文件（WIZARD_UIFILES + wizard_variables）==========
  # Synology DSM 7 使用 JSON 格式的向导定义
  cat > "$BUILD_DIR/conf/WIZARD_UIFILES" << 'EOF'
install_uifile.json
EOF

  cat > "$BUILD_DIR/conf/install_uifile.json" << 'EOF'
{
  "title": "Octop 安装向导",
  "description": "配置 Octop 管理员账号、端口、数据库及 API Key",
  "steps": [
    {
      "name": "basic",
      "title": "基础设置",
      "items": [
        {
          "key": "wizard_port",
          "type": "textfield",
          "label": "Web 端口",
          "default": "8088",
          "validation": {"type": "integer", "min": 1024, "max": 65535},
          "description": "Octop Web 控制台访问端口"
        },
        {
          "key": "wizard_admin_user",
          "type": "textfield",
          "label": "管理员用户名",
          "default": "admin",
          "description": "初始管理员账号（安装后不可改）"
        },
        {
          "key": "wizard_admin_pass",
          "type": "password",
          "label": "管理员密码",
          "default": "",
          "validation": {"type": "string", "minLength": 0, "maxLength": 64},
          "description": "留空则首次打开网页走设置向导；填写则自动创建管理员（需≥8位含字母数字）"
        },
        {
          "key": "wizard_admin_pass_confirm",
          "type": "password",
          "label": "确认密码",
          "default": "",
          "validation": {"type": "string", "minLength": 0, "maxLength": 64}
        }
      ]
    },
    {
      "name": "advanced",
      "title": "高级设置",
      "items": [
        {
          "key": "wizard_db_type",
          "type": "combobox",
          "label": "数据库类型",
          "default": "sqlite",
          "items": ["sqlite", "postgresql"],
          "description": "SQLite（单文件，零配置）或 PostgreSQL（需单独部署）"
        },
        {
          "key": "wizard_openai_key",
          "type": "password",
          "label": "OpenAI API Key",
          "default": "",
          "description": "可选，安装后在 Web 界面配置亦可"
        },
        {
          "key": "wizard_dashscope_key",
          "type": "password",
          "label": "DashScope API Key",
          "default": "",
          "description": "可选，安装后在 Web 界面配置亦可"
        }
      ]
    }
  ]
}
EOF

  # wizard_variables 供脚本读取（键名对应 install_uifile.json 的 key）
  cat > "$BUILD_DIR/conf/wizard_variables" << 'EOF'
wizard_port
wizard_admin_user
wizard_admin_pass
wizard_admin_pass_confirm
wizard_db_type
wizard_openai_key
wizard_dashscope_key
EOF

  # ========== 打包 ==========
  local SPK_NAME="${PREFIX}-${PKG_VER}${ITER_SUFFIX}-${SYNO_ARCH}.spk"
  echo "[build-spk] 打包: $SPK_NAME"
  cd "$BUILD_DIR"
  tar -cf - . | gzip -c > "$OUT/$SPK_NAME"
  cd - >/dev/null

  echo "[build-spk] 产物: $OUT/$SPK_NAME ($(stat -c%s "$OUT/$SPK_NAME") bytes)"
  echo "[build-spk] 内容列表:"
  tar -tzf "$OUT/$SPK_NAME" | sort | sed 's/^/  /'
}

# 执行构建
for arch in $ARCH_LIST; do
  build_arch "$arch"
done

echo "✅ 全部完成，产物在 $OUT/:"
ls -lh "$OUT"/*.spk 2>/dev/null