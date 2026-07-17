# Codex Gold Reasoning Patch v1.0.4

- 修复部分 Windows PowerShell 5.1 环境复制 Codex 深层文件时出现的 `DirectoryNotFoundException`。
- 使用更短的临时构建目录，避免传统 `MAX_PATH` 限制。
- 底层流复制支持 Windows 扩展路径，可从中文或带空格的补丁目录启动。
- 兼容 Codex 包内可枚举但目标已不存在的嵌套目录项，不再中断回退复制。

- Starts the local theme dashboard automatically at user login.
- Starts the dashboard immediately when the patch runtime is installed or refreshed.
- Uses an idempotent localhost-only dashboard service on `http://127.0.0.1:8002`.
- Stops only the verified managed dashboard process during a complete official-package restore.
- Fixes dashboard status detection to check port `8002`.

发布日期：2026-07-16

## 功能

- 增加登录自动恢复：检测到 Store 更新覆盖后，兼容性验证通过才重新打补丁。
- 完整恢复官方包时自动移除登录启动入口。
- 改为轻量补丁器发布，不再分发约 700 MB 的完整 Codex MSIX。
- 提供 `install-small-patch.cmd`，基于本机 Codex 临时构建、事务安装并自动清理。
- 内置约 97 KB 的 vendor 构建器，不依赖接收者预装 patch skill。
- 按推理档位映射不同主题，支持 `minimal` 到 `ultra`。
- 提供 `http://127.0.0.1:8002` 本地配置面板。
- 支持预设主题、自定义配色、材质、背景、边框和文字颜色。
- Codex 运行时约每 1.5 秒读取配置，无需重启。
- 用户提问和 Agent 回复统一使用主题文字颜色，保留代码高亮。
- 提供安全停用、恢复配置和官方 MSIX 原位恢复脚本。
- 提供顶层 `uninstall-patch.cmd`：双击停用主题，拖入官方 MSIX 可完整移除补丁。

## 安全设计

- 不调用 `Remove-AppxPackage`。
- 不直接修改已安装的 `WindowsApps` 文件。
- 使用签名 MSIX 和 AppX 事务原位升级。
- 主题运行时位于 preload，配置文件通过固定 IPC 通道读取。
- IPC 不接受任意文件路径，配置大小限制为 1 MB。
- 保留已验证的回退包和 `-RetainFilesOnFailure` 安装策略。

## 验证环境

- 源 Codex 包版本：`26.707.12708.0`
- 小补丁目标版本：`26.707.12708.1`
- 包状态：`Developer / Ok`
- Windows x64
- PowerShell 5.1+

## 校验

下载后使用 `SHA256SUMS.txt` 核对 MSIX 和源码归档哈希。
