# 至尊 Codex 皮肤面板

当前版本：`v1.0.4`

用于为 Windows 版 Codex Desktop 的不同推理档位设置独立主题。支持中英双语面板、内置金属预设、自定义配色、材质、背景、边框和文字颜色。

## 平台支持

- Windows 10/11 x64
- Microsoft Store 版 Codex Desktop
- 当前版本暂不支持 macOS 和 Linux

## 安装前准备

请确认已安装：

- Codex Desktop，且可以正常启动
- PowerShell 5.1 或更高版本
- Python 3
- Node.js 和 `npx`
- 至少 6 GB 临时磁盘空间

安装前建议退出 Codex Desktop。

## 安装

1. 解压发布包。
2. 双击 `install-small-patch.cmd`。
3. 出现 Windows 管理员确认时选择允许。
4. 等待窗口显示安装成功。
5. Codex 启动后，在推理档位之间切换并检查主题效果。

安装包不包含 Codex 本体。安装过程完成后会自动清理临时构建文件。

补丁包可以放在任意本地目录运行，包括带中文或空格的路径；不需要移动到固定目录。

重复运行安装器是安全的。已经安装当前补丁时，安装器会显示 `already patched`。

## 打开配置面板

安装后访问：

[http://127.0.0.1:8002](http://127.0.0.1:8002)

面板只允许本机访问。安装器会立即启动面板，并注册为 Windows 登录后自动启动。

点击面板右上角的 `English` 或 `中文` 可切换语言，刷新页面后仍会保留选择。

如果面板没有启动，在补丁目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\dashboard-service.ps1" -Action Start
```

检查面板状态：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\dashboard-service.ps1" -Action Status
```

停止面板：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\dashboard-service.ps1" -Action Stop
```

## 配置主题

配置面板提供以下操作：

- 为 `minimal`、`low`、`medium`、`high`、`xhigh`、`max` 和 `ultra` 分别选择主题
- 选择“保持原样”关闭某个档位的装扮
- 使用内置镀金、镜银、赤铜和碳纤维预设
- 复制预设后创建自己的配色
- 自定义主题名称、材质、背景、表面、强调色、边框和文字颜色
- 调整纹理强度和光泽角度
- 删除不再使用的自定义配色

面板显示保存成功后，等待约 2 秒即可在 Codex 中看到更新，一般不需要重启 Codex。

用户配置保存在：

```text
%USERPROFILE%\.codex\reasoning-theme\theme-settings.json
```

## Codex 更新后

Microsoft Store 更新可能覆盖补丁。补丁会在下次 Windows 登录时检查 Codex 版本，并在兼容性检查通过后自动重新应用。

自动恢复日志位于：

```text
%LOCALAPPDATA%\CodexThemePatch\auto-repatch.log
```

如果更新后主题没有恢复：

1. 重新登录 Windows。
2. 等待自动恢复完成。
3. 再次启动 Codex。
4. 如仍未恢复，重新运行 `install-small-patch.cmd`。

## 查看状态

在补丁目录执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\status.ps1"
```

正常状态应包括：

- Codex 包状态为 `Ok`
- 补丁版签名类型为 `Developer`
- `DashboardListening` 为 `True`

## 暂时关闭所有主题

双击：

```text
uninstall-patch.cmd
```

默认操作只关闭全部主题并保留 Codex、补丁和配置备份。

恢复最近一次主题配置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\uninstall-patch.ps1" -RestoreThemeConfig -AllowConfigRestore
```

## 完整卸载

完整恢复需要准备官方 Codex MSIX 文件，然后将该 MSIX 文件拖放到 `uninstall-patch.cmd` 上。

也可以执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\uninstall-patch.ps1" -OfficialMsixPath "<官方 MSIX 路径>" -AllowPackageRestore -Launch
```

完成后会恢复官方 Codex 包，并移除补丁的自动启动入口。Codex 用户数据和主题配置备份会保留。

## 常见问题

### 面板无法访问

检查 Python 3 是否可用：

```powershell
py -3 --version
```

然后重新启动面板服务，并查看日志：

```text
%LOCALAPPDATA%\CodexThemePatch\dashboard.stderr.log
```

### 端口 8002 被占用

查看占用进程：

```powershell
Get-NetTCPConnection -LocalPort 8002 -State Listen
```

关闭占用该端口的程序后，再启动面板。

### 配置已保存但样式没有变化

1. 确认当前 Codex 推理档位与面板中配置的档位一致。
2. 等待约 2 秒。
3. 切换到其他档位后再切换回来。
4. 检查 `theme-settings.json` 是否存在且为有效 JSON。

### 安装兼容性检查失败

不要继续强制安装。保留安装窗口中的错误信息，等待补丁支持当前 Codex 版本后再安装。

## 文件校验

发布包附带 `SHA256SUMS.txt`。校验 ZIP：

```powershell
Get-FileHash -Algorithm SHA256 ".\codex-gold-reasoning-patch-*.zip"
```

输出值应与 `SHA256SUMS.txt` 中对应文件一致。
