# Octop Synology SPK 构建系统

参考飞牛 FPK 设计模式，为群晖 DSM 7+ 制作的 Octop `.spk` 安装包构建工具。

## 目录结构

```
octop-spk-v2/
├── scripts/
│   ├── build-spk.sh          # 主构建脚本（参考 build-fpk.sh）
│   ├── preinst               # 安装前检查
│   ├── postinst              # 安装后配置
│   ├── preuninst             # 卸载前清理
│   ├── postuninst            # 卸载后清理
│   └── start-stop-status     # DSM 套件中心生命周期
├── docker-compose.yml        # Octop Docker 编排（拉取官方镜像）
├── conf/
│   ├── .env.template         # 环境变量模板
│   ├── install_uifile.json   # DSM 7 安装向导 UI 定义
│   ├── WIZARD_UIFILES        # 向导文件清单
│   └── wizard_variables      # 向导变量列表
├── icons/
│   ├── PACKAGE_ICON.PNG      # 72x72
│   └── PACKAGE_ICON_256.PNG  # 256x256
├── LICENSE                   # MIT
├── pyproject.toml            # 版本号来源（从上游同步）
├── actions/
│   └── spk-build.yml         # GitHub Actions 自动构建
└── dist/                     # 产物输出目录
```

## 本地构建

```bash
# 构建当前架构 SPK
bash scripts/build-spk.sh

# 指定架构
bash scripts/build-spk.sh x86_64
bash scripts/build-spk.sh aarch64

# 双架构都构建
ARCH=all bash scripts/build-spk.sh

# 带迭代号
SPK_ITER=01 bash scripts/build-spk.sh
```

产物输出到 `dist/`：
- `Octop-1.0.3-1-x86_64.spk`
- `Octop-1.0.3-1-aarch64.spk`

## 安装向导参数

安装时会依次询问：

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `wizard_port` | integer | 8088 | Web 端口 (1024-65535) |
| `wizard_admin_user` | string | admin | 管理员用户名 |
| `wizard_admin_pass` | password | (空) | 留空则首次打开走设置向导；填写则自动建号（≥8位含字母数字） |
| `wizard_admin_pass_confirm` | password | (空) | 确认密码 |
| `wizard_db_type` | combobox | sqlite | sqlite / postgresql |
| `wizard_openai_key` | password | (空) | OpenAI API Key |
| `wizard_dashscope_key` | password | (空) | DashScope API Key |

## GitHub Actions 自动构建

将 `.github/workflows/spk-build.yml` 复制到上游仓库：

```yaml
# 触发方式：
# 1. 手动触发：Actions → Build Synology SPK → Run workflow
# 2. 发布 Release 时自动构建并挂载到 Release Assets
```

## 版本号规则

- 来源：`pyproject.toml` 的 `version`（PEP 440，如 `1.0.3b7`）
- SPK 版本：取前三段 `x.y.z` + 发布序号（如 `1.0.3-1`）
- 迭代号：可选 `SPK_ITER` 追加（如 `1.0.3-1-01`）

## 与飞牛 FPK 对比

| 特性 | FPK (fnpack) | SPK (本工具) |
|------|--------------|--------------|
| 打包工具 | 官方 fnpack CLI | 手工 tar + 标准目录 |
| 结构 | 双层 gzip tar (app.tgz) | 单层 gzip tar |
| 生命周期 | cmd/ 目录脚本 | preinst/postinst/start-stop-status |
| 向导 | wizard/ 目录模板 | install_uifile.json (DSM 7) |
| 架构 | platform=x86/arm/all + cmd/fpk-arch | INFO arch 字段 |
| 版本映射 | 编码 beta (1.0.2b8→1.0.208) | 直接用 x.y.z |

## 升级 Octop 版本

1. 同步上游 `pyproject.toml`：
   ```bash
   gh api repos/TencentCloud/Octop/contents/pyproject.toml --jq '.content' | base64 -d > pyproject.toml
   ```
2. 同步 docker-compose.yml：
   ```bash
   gh api repos/TencentCloud/Octop/contents/deploy/docker/docker-compose.yml --jq '.content' | base64 -d > docker-compose.yml
   ```
3. 重新构建：
   ```bash
   bash scripts/build-spk.sh
   ```

## 推送到你的 Fork 仓库

```bash
cd /home/dwc1377/octop-spk-v2
git init
git add .
git commit -m "Add Synology SPK build system (ref: FPK design)"
git remote add origin https://github.com/DingXiaoWu0512/Octop.git
git push -u origin main:synology-spk
# 然后在 GitHub 创建 PR 合并到你的 fork 的 synology-spk 分支
```