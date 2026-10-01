# 安装、更新与数据 / Installation and data

## 系统要求 / Requirements

首个 Beta 安装包仅支持 Apple Silicon（M 系列）与 macOS 14+。Intel、Windows 不在本次验收范围内。应用无需账号；AI 功能需要自行配置兼容服务，离线记录不需要 API。

The Beta binary targets Apple Silicon and macOS 14+. No app account is required; AI requires your own compatible provider.

## 安装与首次打开 / Install

从本仓库 Releases 下载 ZIP 和同名 .sha256。终端切换到下载目录后运行：

```bash
shasum -a 256 -c LingGanGu-0.2.3-beta-macos-arm64.zip.sha256
```

应显示 OK。解压后拖动「灵感菇.app」至应用程序文件夹，再打开。校验值用于检查完整性，不能取代可信发布来源或开发者签名。

当前包只做 ad-hoc 签名，没有 Developer ID、没有 Apple 公证。若提示未验证开发者，请核实来源后按 [Apple 官方说明](https://support.apple.com/102445) 在“系统设置 → 隐私与安全 → 仍要打开”允许该应用。企业管理策略可能禁止此操作。
如果提示恶意软件或文件损坏，请停止，不要禁用系统防护，也不要运行来源不明的修复脚本。

Verify the hash, unzip, move the app to Applications, then launch. This build is ad-hoc signed and not notarized. Follow Apple's per-app Open Anyway instructions only if you trust the source; never disable global protections or ignore malware warnings.

## 日常使用 / Use

- 菜单栏蘑菇图标：显示组件、工作台、AI 设置、退出。
- `⌘⇧Space`：快速记录；首次数据库为空。
- AI 设置：Base URL、模型 ID、Key → 保存 → 测试连接。密钥不要发到 Issues。
- 灵感五状态可自由切换，不要求逐级完成；AI 不自动改变状态。
- 原始灵感、报告和对话记录本地持久化；实际请求可能产生服务商费用。

Use the menu-bar icon and Command-Shift-Space. Configure the API only if needed; never share the key in an Issue. Closing a window is not quitting the app.

## 更新 / Update

1. 确认所有记录保存成功，尤其是出现“重新保存回复”时先处理完成。
2. 从菜单栏真正退出应用，备份数据。
3. 用新版 app 替换旧版，再启动。只替换 app 不会主动删除数据库。
4. 检查版本、记录数量、历史及 API 设置。临时签名更新后可能再次请求钥匙串授权。

Quit, back up data, replace only the app, then check data/settings. Ad-hoc updates may require authorization again. Automatic updates are not included.

## 数据、备份和恢复 / Backup and restore

数据库目录：`~/Library/Application Support/LingGanGu/`。在 Finder 的“前往文件夹”输入此路径。
密钥在当前用户的系统钥匙串，不在该目录；跨电脑迁移可能需要重新配置 Key。

备份：完全退出应用，再复制整个 LingGanGu 数据目录到你选择的安全位置。一起保留可能存在的 SQLite WAL/SHM 与迁移备份文件，不要在应用写入时单独复制数据库。
恢复：完全退出应用，先把现有数据目录另存为备份，然后将原备份目录放回原位置。优先使用生成备份时的相同应用版本，不将新数据库降级给旧版本。重新打开并检查数量与历史。

Quit before copying the complete data directory. Keep the current directory as a recovery copy before restoring. Use a compatible app version; do not downgrade a newer database. The app does not implement one-click JSON import. Markdown/JSON exports are portable records, not a guaranteed one-click restore procedure.

Beta 数据库没有额外应用级加密。保护 macOS 登录账户，妥善管理磁盘加密与备份；共用一个系统账户等同共用应用配置。

## 卸载 / Uninstall

退出后把 app 移到废纸篓即可，默认保留本地记录和钥匙串密钥。若要彻底清理，先导出/备份，在 AI 设置中删除 Key，再退出并单独移走上述数据目录。此操作会丢失本地记录，勿误删其他目录。

Trash the app after quitting. Data and key remain unless explicitly removed. Back up/export first; delete the Key through AI settings and remove only the app's data directory if you intend to erase your records.
