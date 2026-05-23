# Hermes Windows Installer

这个仓库提供一个适合 Windows 10/11 的 Hermes Agent + Hermes Web UI 一键安装脚本。

脚本会把运行环境尽量安装到同一个目录，默认是：

```text
C:\hermes
```

安装内容包括：

- Node.js 24 portable
- uv portable
- Python 3.11 portable，位于 `C:\hermes\uv-python`，不写入用户目录的 `python3.11.exe`
- Portable Git
- ripgrep
- ffmpeg
- Hermes Agent
- hermes-web-ui
- 快速启动、停止、升级、打包、迁移脚本

## 快速安装

在 PowerShell 里运行下面几行，把最新版 `install-hermes.ps1` 下载到当前用户桌面并启动安装：

```powershell
$dst = "$([Environment]::GetFolderPath('Desktop'))\install-hermes.ps1"
iwr -UseBasicParsing -Uri "https://ghfast.top/https://raw.githubusercontent.com/soapmancn/hermes-windows-installer/main/install-hermes.ps1" -OutFile $dst
powershell -NoProfile -ExecutionPolicy Bypass -File $dst
```

如果脚本已经在桌面，也可以直接运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$([Environment]::GetFolderPath('Desktop'))\install-hermes.ps1"
```

指定 GitHub 代理：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$([Environment]::GetFolderPath('Desktop'))\install-hermes.ps1" -GithubProxy "https://gh.llkk.cc/"
```

不使用 GitHub 代理：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$([Environment]::GetFolderPath('Desktop'))\install-hermes.ps1" -GithubProxy ""
```

## 国内默认源

脚本默认使用：

```text
Node.js: https://npmmirror.com/mirrors/node
npm:     https://registry.npmmirror.com
PyPI:    https://pypi.tuna.tsinghua.edu.cn/simple
GitHub:  https://ghfast.top/
```

默认 GitHub 代理不仅用于下载依赖，也会 patch 官方 Hermes Agent 安装器里的 `git clone` 和 ZIP archive 地址，避免官方脚本内部再次直连 GitHub。

可以按需替换：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$([Environment]::GetFolderPath('Desktop'))\install-hermes.ps1" `
  -GithubProxy "https://gh.llkk.cc/" `
  -NodeMirror "https://npmmirror.com/mirrors/node" `
  -NpmRegistry "https://registry.npmmirror.com" `
  -PypiIndex "https://pypi.tuna.tsinghua.edu.cn/simple"
```

## 使用 Windows Terminal

如果旧 PowerShell 窗口无法正常显示标点或特殊字符，可以让脚本自动使用你下载好的 Windows Terminal。

假设 Windows Terminal 解压在桌面：

```text
桌面\WindowsTerminal\wt.exe
```

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$([Environment]::GetFolderPath('Desktop'))\install-hermes.ps1" `
  -UseWindowsTerminal `
  -WindowsTerminal "$([Environment]::GetFolderPath('Desktop'))\WindowsTerminal"
```

安装日志会写入：

```text
C:\hermes\logs\install.log
```

## 配置 Hermes

安装完成后运行：

```powershell
C:\hermes\hermes.cmd setup
```

按提示配置模型和 API Key。

## 启动和停止

启动：

```powershell
C:\hermes\hermes-run.bat
```

脚本会先停止旧的 gateway 和 Web UI，再重新启动，并自动打开带 token 的 Web UI 页面。

停止：

```powershell
C:\hermes\hermes-stop.bat
```

默认地址：

```text
Hermes gateway: http://127.0.0.1:8642
Hermes Web UI : http://127.0.0.1:8648
```

## 升级

普通升级：

```powershell
C:\hermes\hermes-upgrade.bat
```

升级后自动重启：

```powershell
C:\hermes\hermes-upgrade.bat -Restart
```

升级前备份 Hermes 配置：

```powershell
C:\hermes\hermes-upgrade.bat -Backup -Restart
```

## 打包

把 `C:\hermes` 打包成当前用户桌面的 `hermes.zip`：

```powershell
powershell -ExecutionPolicy Bypass -File C:\hermes\hermes-pack.ps1
```

如果要指定其他输出位置，选择当前用户有写入权限的目录：

```powershell
powershell -ExecutionPolicy Bypass -File C:\hermes\hermes-pack.ps1 -ZipPath "$env:USERPROFILE\Desktop\hermes.zip"
```

打包默认使用 `Fastest` 压缩级别。`C:\hermes` 包含 Python、Node、Portable Git、venv、node_modules 等大量文件，打包会比较慢；如果更在意速度而不是压缩包大小，可以改用不压缩：

```powershell
powershell -ExecutionPolicy Bypass -File C:\hermes\hermes-pack.ps1 -CompressionLevel NoCompression
```

注意：压缩包可能包含 `.env`、token、API Key、登录态等敏感信息，不要发给不可信的人。

## 迁移到其他盘符

例如把压缩包解压到新电脑的 `D:\hermes`：

```powershell
New-Item -ItemType Directory -Force D:\hermes | Out-Null
Expand-Archive -Path "$env:USERPROFILE\Desktop\hermes.zip" -DestinationPath D:\hermes -Force
powershell -ExecutionPolicy Bypass -File D:\hermes\hermes-relocate.ps1 -Root D:\hermes -OldRoot C:\hermes
D:\hermes\hermes-run.bat
```

建议迁移路径保持类似 `X:\hermes`，这样路径长度和 `C:\hermes` 一致，Python venv 的可执行入口更容易被原位修复。

## 检查 Python 是否在便携目录

安装时应该看到类似：

```text
Installed Python 3.11.x
Portable Python ready: C:\hermes\uv-python\cpython-3.11.x-windows-x86_64-none\python.exe
```

脚本使用 `uv python install --no-bin`，所以不会尝试覆盖 `%USERPROFILE%\.local\bin\python3.11.exe`。如果你看到 `Executable already exists ... python3.11.exe`，说明运行的是旧脚本，按“快速安装”的命令重新下载最新版后再运行。

安装后也可以检查：

```powershell
Get-Content C:\hermes\hermes-agent\venv\pyvenv.cfg
```

其中 `home =` 应该指向：

```text
C:\hermes\uv-python\...
```

## 常见问题

如果下载失败，可以换 GitHub 代理并重新运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$([Environment]::GetFolderPath('Desktop'))\install-hermes.ps1" -GithubProxy "https://gh.llkk.cc/"
```

如果日志里出现 `Host key verification failed`，这是官方安装器先尝试 SSH clone 导致的，通常可以忽略；最新版脚本会把后续 HTTPS clone 和 ZIP 下载改走 `-GithubProxy`。

如果安装中断，可以重新运行安装命令。脚本会复用已下载和已安装的组件，并重建 Hermes venv。

如果 Web UI 没有自动登录，检查 token 文件：

```text
C:\hermes\hermes-web-ui-home\.token
```

然后重新启动：

```powershell
C:\hermes\hermes-stop.bat
C:\hermes\hermes-run.bat
```
