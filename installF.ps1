# ============================================================================
# Hermes Agent 安装器（Windows 中国大陆镜像版）
# ============================================================================
# Windows（PowerShell）安装脚本。
# 使用 uv 快速安装和管理 Python。
#
# 用法：
#   irm https://res1.hermesagent.org.cn/install.ps1 | iex
#
# 或先下载后带参数执行：
#   .\install.ps1 -NoVenv -SkipSetup
#   .\install.ps1 -WithSystemPackages
#   .\install.ps1 -WithOptionalExtras
#
# ============================================================================

param(
    [switch]$NoVenv,
    [switch]$SkipSetup,
    [switch]$WithSystemPackages,
    [switch]$WithOptionalExtras,
    [string]$Branch = "main",
    [string]$HermesHome = "F:\hermes",
    [string]$InstallDir = "F:\hermes\hermes-agent"
)

$ErrorActionPreference = "Stop"

# ============================================================================
# Configuration
# ============================================================================

$RepoUrlSsh = "git@github.com:NousResearch/hermes-agent.git"
$RepoUrlHttps = "https://github.com/NousResearch/hermes-agent.git"
$RepoUrlCnb = "https://cnb.cool/hermesagent-cn/hermes-agent-cn-mirror.git"
$PythonVersion = "3.11"
$NodeVersion = "24"
$MirrorBaseUrl = if ($env:HERMES_MIRROR_BASE_URL) { $env:HERMES_MIRROR_BASE_URL } else { "https://res1.hermesagent.org.cn" }
$MirrorCacheBustQuery = "?v=2026.05.18-b83f7c1"
$UvInstallerUrl = if ($env:HERMES_UV_INSTALLER_URL) { $env:HERMES_UV_INSTALLER_URL } else { "$MirrorBaseUrl/third-party/uv/install.ps1" }
$UvPythonInstallMirror = if ($env:HERMES_UV_PYTHON_MIRROR) { $env:HERMES_UV_PYTHON_MIRROR } else { "$MirrorBaseUrl/third-party/python-build-standalone/releases/download" }
$PipIndexUrl = if ($env:HERMES_PIP_INDEX_URL) { $env:HERMES_PIP_INDEX_URL } else { "https://pypi.tuna.tsinghua.edu.cn/simple" }
$PipFallbackIndexUrls = @(
    $PipIndexUrl,
    "https://mirrors.aliyun.com/pypi/simple",
    "https://pypi.mirrors.ustc.edu.cn/simple",
    "https://pypi.org/simple"
) | Select-Object -Unique
$DesiredUvInstallDir = "$env:USERPROFILE\.local\bin"
$script:PythonSpecifier = $PythonVersion
$script:UvAvailable = $false
$script:BypassInvalidLocalProxy = $false

# ============================================================================
# Helper functions
# ============================================================================

function Write-Banner {
    Write-Host ""
    Write-Host "──────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
    Write-Host "  ⚕ Hermes Agent 安装器 · 中国大陆镜像" -ForegroundColor Magenta
    Write-Host "──────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
    Write-Host "  由 Hermes Agent 中文社区提供加速" -ForegroundColor Magenta
    Write-Host "  社区官网：https://hermesagent.org.cn" -ForegroundColor Magenta
    Write-Host "  镜像脚本版本：2026.05.18-b83f7c1" -ForegroundColor Magenta
    Write-Host "  最后更新：2026-05-18 09:07:41 CST" -ForegroundColor Magenta
    Write-Host "──────────────────────────────────────────────────────────────────────" -ForegroundColor Magenta
    Write-Host ""
}

function Write-Info {
    param([string]$Message)
    Write-Host "→ $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "✓ $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "⚠ $Message" -ForegroundColor Yellow
}

function Write-Err {
    param([string]$Message)
    Write-Host "✗ $Message" -ForegroundColor Red
}

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkCyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkCyan
}

function Get-ProxyUri {
    param([string]$Value)

    if (-not $Value) {
        return $null
    }

    try {
        return [Uri]$Value
    } catch {
        try {
            return [Uri]("http://" + $Value)
        } catch {
            return $null
        }
    }
}

function Test-ProxyReachable {
    param(
        [string]$HostName,
        [int]$Port
    )

    try {
        $client = New-Object System.Net.Sockets.TcpClient
        $iar = $client.BeginConnect($HostName, $Port, $null, $null)
        $connected = $iar.AsyncWaitHandle.WaitOne(1500, $false)
        if (-not $connected) {
            $client.Close()
            return $false
        }
        $client.EndConnect($iar)
        $client.Close()
        return $true
    } catch {
        return $false
    }
}

function Disable-InvalidLocalProxyIfNeeded {
    $proxyVars = @("http_proxy", "https_proxy", "all_proxy", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY")
    $invalidProxy = $null

    foreach ($varName in $proxyVars) {
        $value = [Environment]::GetEnvironmentVariable($varName)
        $uri = Get-ProxyUri $value
        if (-not $uri) { continue }
        if ($uri.Host -in @("127.0.0.1", "localhost", "::1")) {
            $port = if ($uri.Port -gt 0) { $uri.Port } else { 80 }
            if (-not (Test-ProxyReachable -HostName $uri.Host -Port $port)) {
                $invalidProxy = "$($uri.Host):$port"
                break
            }
        }
    }

    if (-not $invalidProxy) {
        foreach ($gitProxyKey in @("http.proxy", "https.proxy")) {
            try {
                $gitProxy = git config --global --get $gitProxyKey 2>$null
                $uri = Get-ProxyUri $gitProxy
                if (-not $uri) { continue }
                if ($uri.Host -in @("127.0.0.1", "localhost", "::1")) {
                    $port = if ($uri.Port -gt 0) { $uri.Port } else { 80 }
                    if (-not (Test-ProxyReachable -HostName $uri.Host -Port $port)) {
                        $invalidProxy = "$($uri.Host):$port"
                        break
                    }
                }
            } catch { }
        }
    }

    if (-not $invalidProxy) {
        return
    }

    $script:BypassInvalidLocalProxy = $true
    Write-Warn "检测到本机代理 $invalidProxy 当前不可用。"
    Write-Info "本次安装将临时忽略失效代理，避免 Git / pip 下载失败。"

    foreach ($varName in $proxyVars + @("PIP_PROXY")) {
        Remove-Item ("Env:" + $varName) -ErrorAction SilentlyContinue
    }
}

function Invoke-GitCommand {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

    $gitArgs = @("-c", "windows.appendAtomically=false")
    if ($script:BypassInvalidLocalProxy) {
        $gitArgs += @("-c", "http.proxy=", "-c", "https.proxy=")
    }
    $gitArgs += $Args
    & git @gitArgs
}

function Invoke-PipWithFallback {
    param(
        [string]$PythonExe,
        [string[]]$PipArgs
    )

    foreach ($mirror in $PipFallbackIndexUrls) {
        if (-not $mirror) { continue }

        Write-Info "正在尝试 pip 镜像：$mirror"
        $env:PIP_INDEX_URL = $mirror
        try {
            & $PythonExe -m pip @PipArgs
            if ($LASTEXITCODE -eq 0) {
                $script:PipIndexUrl = $mirror
                return $true
            }
        } catch { }

        Write-Warn "当前 pip 镜像失败，准备切换下一个镜像..."
    }

    return $false
}

function Ensure-OriginPointsToMirror {
    try {
        $currentOrigin = git remote get-url origin 2>$null
        if ($LASTEXITCODE -eq 0 -and $currentOrigin) {
            if ($currentOrigin -ne $RepoUrlCnb) {
                git remote set-url origin $RepoUrlCnb 2>$null
            }
        } else {
            git remote add origin $RepoUrlCnb 2>$null
        }
    } catch { }
}

function Get-UsablePythonCommand {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        return $null
    }

    $source = $pythonCmd.Source
    if ($source -match 'WindowsApps\\python(?:3(?:\\.exe)?)?\\.exe$') {
        return $null
    }

    return $pythonCmd
}

function Try-UseSystemPythonCommand {
    param([string]$CommandName)

    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue
    if (-not $cmd) {
        return $false
    }

    $source = $cmd.Source
    if ($source -match 'WindowsApps\\python(?:3)?(?:\\.exe)?$') {
        return $false
    }

    try {
        $ver = & $source --version 2>$null
        if ($LASTEXITCODE -eq 0 -and $ver -match 'Python\\s+(\\d+)\\.(\\d+)\\.(\\d+)') {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 11)) {
                $script:PythonVersion = "$major.$minor"
                $script:PythonSpecifier = $source
                Write-Success "将使用系统 Python：$ver"
                return $true
            }
        }
    } catch { }

    return $false
}

function Test-PythonViaPyLauncher {
    if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
        return $false
    }

    foreach ($fallbackVer in @("-3.13", "-3.12", "-3.11", "-3.10")) {
        try {
            $ver = & py $fallbackVer --version 2>$null
            if ($LASTEXITCODE -eq 0 -and $ver -match "3\.(1[0-9]|[1-9][0-9])") {
                $exePath = & py $fallbackVer -c "import sys; print(sys.executable)" 2>$null
                if ($LASTEXITCODE -eq 0 -and $exePath) {
                    Write-Success "已通过 py 启动器找到 Python：$ver"
                    $script:PythonVersion = $fallbackVer.TrimStart("-")
                    $script:PythonSpecifier = $exePath.Trim()
                    return $true
                }
            }
        } catch { }
    }

    return $false
}

# ============================================================================
# Dependency checks
# ============================================================================

function Install-Uv {
    Write-Info "正在检查 uv 包管理器..."
    
    # Check if uv is already available
    if (Get-Command uv -ErrorAction SilentlyContinue) {
        $version = uv --version
        $script:UvCmd = "uv"
        $script:UvAvailable = $true
        Write-Success "已找到 uv（$version）"
        return $true
    }
    
    # Check common install locations
    $uvPaths = @(
        "$DesiredUvInstallDir\uv.exe",
        "$HOME\.local\bin\uv.exe",
        $(if ($env:XDG_BIN_HOME) { "$env:XDG_BIN_HOME\uv.exe" } else { $null }),
        "$env:USERPROFILE\.local\bin\uv.exe",
        "$env:USERPROFILE\.cargo\bin\uv.exe"
    ) | Where-Object { $_ }
    foreach ($uvPath in $uvPaths) {
        if (Test-Path $uvPath) {
            $script:UvCmd = $uvPath
            $script:UvAvailable = $true
            $version = & $uvPath --version
            Write-Success "已在 $uvPath 找到 uv（$version）"
            return $true
        }
    }
    
    # Install uv
    Write-Info "正在安装 uv（快速 Python 包管理器）..."
    $oldUvInstallDir = $env:UV_INSTALL_DIR
    try {
        $installerUrl = $UvInstallerUrl
        $tmpInstaller = Join-Path $env:TEMP "hermes-uv-install.ps1"
        Write-Info "正在下载 uv 安装脚本：$installerUrl"
        Invoke-WebRequest -Uri $installerUrl -OutFile $tmpInstaller -UseBasicParsing
        $env:UV_INSTALL_DIR = $DesiredUvInstallDir
        powershell -ExecutionPolicy ByPass -File $tmpInstaller
        if ($null -eq $oldUvInstallDir) {
            Remove-Item Env:UV_INSTALL_DIR -ErrorAction SilentlyContinue
        } else {
            $env:UV_INSTALL_DIR = $oldUvInstallDir
        }
        Remove-Item $tmpInstaller -Force -ErrorAction SilentlyContinue
        
        # Find the installed binary
        $uvExe = $null
        foreach ($candidate in $uvPaths) {
            if (Test-Path $candidate) {
                $uvExe = $candidate
                break
            }
        }
        if (-not (Test-Path $uvExe)) {
            # Refresh PATH and try again
            $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
            if (Get-Command uv -ErrorAction SilentlyContinue) {
                $uvExe = (Get-Command uv).Source
            } else {
                $whereUv = & where.exe uv 2>$null | Select-Object -First 1
                if ($LASTEXITCODE -eq 0 -and $whereUv) {
                    $uvExe = $whereUv.Trim()
                }
            }
        }
        
        if (Test-Path $uvExe) {
            $script:UvCmd = $uvExe
            $script:UvAvailable = $true
            $version = & $uvExe --version
            Write-Success "uv 安装完成（$version）"
            return $true
        }
        
        $script:UvAvailable = $false
        Write-Warn "uv 安装完成，但安装器没能立刻定位到 uv.exe"
        Write-Info "这通常是 Windows 当前终端环境变量尚未刷新导致的。"
        Write-Info "如果系统里已有 Python 3.11+，安装器会继续尝试直接使用系统 Python。"
        return $false
    } catch {
        if ($null -eq $oldUvInstallDir) {
            Remove-Item Env:UV_INSTALL_DIR -ErrorAction SilentlyContinue
        } elseif ($oldUvInstallDir) {
            $env:UV_INSTALL_DIR = $oldUvInstallDir
        }
        $script:UvAvailable = $false
        Write-Warn "安装 uv 失败"
        Write-Info "如果系统里已有 Python 3.11+，安装器会继续尝试直接使用系统 Python。"
        return $false
    }
}

function Test-Python {
    Write-Info "正在检查 Python $PythonVersion..."

    if (Try-UseSystemPythonCommand "python") {
        return $true
    }
    if (Try-UseSystemPythonCommand "python3") {
        return $true
    }
    if (Test-PythonViaPyLauncher) {
        return $true
    }
    
    # Let uv find or install Python when available
    if ($script:UvCmd) {
        try {
            $pythonPath = & $UvCmd python find $PythonVersion 2>$null
            if ($pythonPath) {
                $ver = & $pythonPath --version 2>$null
                Write-Success "已找到 Python：$ver"
                $script:PythonSpecifier = $pythonPath.Trim()
                return $true
            }
        } catch { }
    }
    
    # Python not found — use uv to install it (no admin needed!)
    if ($script:UvCmd) {
        Write-Info "未找到 Python $PythonVersion，正在通过 uv 安装..."
        Write-Info "首次安装通常需要下载约 20~30MB，请耐心等待，不要关闭当前窗口。"
        $oldNativePref = $null
        $oldMirror = $null
        try {
            $oldNativePref = $global:PSNativeCommandUseErrorActionPreference
            $global:PSNativeCommandUseErrorActionPreference = $false
            $oldMirror = $env:UV_PYTHON_INSTALL_MIRROR
            $env:UV_PYTHON_INSTALL_MIRROR = $UvPythonInstallMirror
            & $UvCmd python install $PythonVersion
            $uvExitCode = $LASTEXITCODE
            if ($null -eq $oldMirror) {
                Remove-Item Env:UV_PYTHON_INSTALL_MIRROR -ErrorAction SilentlyContinue
            } else {
                $env:UV_PYTHON_INSTALL_MIRROR = $oldMirror
            }
            $global:PSNativeCommandUseErrorActionPreference = $oldNativePref

            if ($uvExitCode -eq 0) {
                $pythonPath = & $UvCmd python find $PythonVersion 2>$null
                if ($pythonPath) {
                    $ver = & $pythonPath --version 2>$null
                    Write-Success "Python 安装完成：$ver"
                    $script:PythonSpecifier = $pythonPath.Trim()
                    return $true
                }
            } else {
                Write-Warn "uv 没能成功安装 Python。"
            }
        } catch {
            if ($null -ne $oldMirror) {
                $env:UV_PYTHON_INSTALL_MIRROR = $oldMirror
            } else {
                Remove-Item Env:UV_PYTHON_INSTALL_MIRROR -ErrorAction SilentlyContinue
            }
            if ($null -ne $oldNativePref) {
                $global:PSNativeCommandUseErrorActionPreference = $oldNativePref
            }
            Write-Warn "通过 uv 安装 Python 时出现异常：$_"
        }
    }

    # Fallback: check if ANY Python 3.10+ is already available on the system
    Write-Info "正在尝试寻找任意已有的 Python 3.10+ ..."
    foreach ($fallbackVer in @("3.12", "3.13", "3.10")) {
        try {
            $pythonPath = & $UvCmd python find $fallbackVer 2>$null
            if ($pythonPath) {
                $ver = & $pythonPath --version 2>$null
                Write-Success "找到可用备用版本：$ver"
                $script:PythonVersion = $fallbackVer
                return $true
            }
        } catch { }
    }

    # Fallback: try system python
    if (Get-Command python -ErrorAction SilentlyContinue) {
        Write-Warn "检测到 Windows 的 Python 应用执行别名（Microsoft Store 占位符）正在拦截 python 命令。"
        Write-Info "这不是你的操作问题，是 Windows 的默认行为。"
        Write-Info "如果你后续仍安装失败，请到 [设置 > 应用 > 高级设置 > 应用执行别名] 里关闭 python.exe / python3.exe。"
    }
    
    Write-Err "安装 Python $PythonVersion 失败"
    Write-Info "下一步请按下面步骤操作："
    Write-Info "  第 1 步：打开清华大学镜像站 https://mirrors.tuna.tsinghua.edu.cn/python/"
    Write-Info "  第 2 步：下载 Python 3.11 或更高版本的 Windows 安装包（通常是 amd64.exe）"
    Write-Info "  第 3 步：安装时勾选 Add Python to PATH"
    Write-Info "  第 4 步：安装完成后，关闭当前 PowerShell，重新打开后再执行本安装命令"
    Write-Info "如果你之前见过 Microsoft Store 的 Python 提示，建议顺手到 [设置 > 应用 > 高级设置 > 应用执行别名] 里关闭 python.exe / python3.exe。"
    return $false
}

function Test-Git {
    Write-Info "正在检查 Git..."
    
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $version = git --version
        Write-Success "已找到 Git（$version）"
        return $true
    }
    
    Write-Err "未找到 Git"
    Write-Info "请先安装 Git："
    Write-Info "  https://git-scm.com/download/win"
    return $false
}

function Test-Node {
    Write-Info "正在检查 Node.js（浏览器工具需要）..."

    if (Get-Command node -ErrorAction SilentlyContinue) {
        $version = node --version
        Write-Success "已找到 Node.js（$version）"
        $script:HasNode = $true
        return $true
    }

    # Check our own managed install from a previous run
    $managedNode = "$HermesHome\node\node.exe"
    if (Test-Path $managedNode) {
        $version = & $managedNode --version
        $env:Path = "$HermesHome\node;$env:Path"
        Write-Success "已找到 Node.js（$version，Hermes 托管版）"
        $script:HasNode = $true
        return $true
    }

    Write-Info "未找到 Node.js —— 正在安装 Node.js $NodeVersion LTS..."

    # Try winget first (cleanest on modern Windows)
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Info "正在通过 winget 安装..."
        try {
            winget install OpenJS.NodeJS.LTS --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            # Refresh PATH
            $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
            if (Get-Command node -ErrorAction SilentlyContinue) {
                $version = node --version
                Write-Success "Node.js 已通过 winget 安装完成（$version）"
                $script:HasNode = $true
                return $true
            }
        } catch { }
    }

    # Fallback: download binary zip to ~/.hermes/node/
    Write-Info "正在下载 Node.js $NodeVersion 二进制包..."
    try {
        $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
        $indexUrl = "https://nodejs.org/dist/latest-v${NodeVersion}.x/"
        $indexPage = Invoke-WebRequest -Uri $indexUrl -UseBasicParsing
        $zipName = ($indexPage.Content | Select-String -Pattern "node-v${NodeVersion}\.\d+\.\d+-win-${arch}\.zip" -AllMatches).Matches[0].Value

        if ($zipName) {
            $downloadUrl = "${indexUrl}${zipName}"
            $tmpZip = "$env:TEMP\$zipName"
            $tmpDir = "$env:TEMP\hermes-node-extract"

            Invoke-WebRequest -Uri $downloadUrl -OutFile $tmpZip -UseBasicParsing
            if (Test-Path $tmpDir) { Remove-Item -Recurse -Force $tmpDir }
            Expand-Archive -Path $tmpZip -DestinationPath $tmpDir -Force

            $extractedDir = Get-ChildItem $tmpDir -Directory | Select-Object -First 1
            if ($extractedDir) {
                if (Test-Path "$HermesHome\node") { Remove-Item -Recurse -Force "$HermesHome\node" }
                Move-Item $extractedDir.FullName "$HermesHome\node"
                $env:Path = "$HermesHome\node;$env:Path"

                $version = & "$HermesHome\node\node.exe" --version
                Write-Success "Node.js 已安装到 ~/.hermes/node/（$version）"
                $script:HasNode = $true

                Remove-Item -Force $tmpZip -ErrorAction SilentlyContinue
                Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
                return $true
            }
        }
    } catch {
        Write-Warn "下载失败：$_"
    }

    Write-Warn "无法自动安装 Node.js"
    Write-Info "如需手动安装，请访问：https://nodejs.org/en/download/"
    $script:HasNode = $false
    return $true
}

function Install-SystemPackages {
    $script:HasRipgrep = $false
    $script:HasFfmpeg = $false
    $needRipgrep = $false
    $needFfmpeg = $false

    Write-Info "正在检查 ripgrep（快速文件搜索）..."
    if (Get-Command rg -ErrorAction SilentlyContinue) {
        $version = rg --version | Select-Object -First 1
        Write-Success "已找到 $version"
        $script:HasRipgrep = $true
    } else {
        $needRipgrep = $true
    }

    Write-Info "正在检查 ffmpeg（TTS 语音消息需要）..."
    if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
        Write-Success "已找到 ffmpeg"
        $script:HasFfmpeg = $true
    } else {
        $needFfmpeg = $true
    }

    if (-not $needRipgrep -and -not $needFfmpeg) { return }

    if (-not $WithSystemPackages) {
        Write-Warn "为提高安装速度，Windows 镜像安装器默认不自动安装 ripgrep / ffmpeg。"
        Write-Info "Hermes 核心功能不受影响；如需更快文件搜索或 TTS，可稍后手动安装。"
        if ($needRipgrep) {
            Write-Info "  可安装 ripgrep：winget install BurntSushi.ripgrep.MSVC"
        }
        if ($needFfmpeg) {
            Write-Info "  可安装 ffmpeg：winget install Gyan.FFmpeg"
        }
        return
    }

    # Build description and package lists for each package manager
    $descParts = @()
    $wingetPkgs = @()
    $chocoPkgs = @()
    $scoopPkgs = @()

    if ($needRipgrep) {
        $descParts += "ripgrep（更快的文件搜索）"
        $wingetPkgs += "BurntSushi.ripgrep.MSVC"
        $chocoPkgs += "ripgrep"
        $scoopPkgs += "ripgrep"
    }
    if ($needFfmpeg) {
        $descParts += "ffmpeg（TTS 语音消息）"
        $wingetPkgs += "Gyan.FFmpeg"
        $chocoPkgs += "ffmpeg"
        $scoopPkgs += "ffmpeg"
    }

    $description = $descParts -join " + "
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    $hasChoco = Get-Command choco -ErrorAction SilentlyContinue
    $hasScoop = Get-Command scoop -ErrorAction SilentlyContinue

    # Try winget first (most common on modern Windows)
    if ($hasWinget) {
        Write-Info "正在通过 winget 安装 $description ..."
        foreach ($pkg in $wingetPkgs) {
            try {
                winget install $pkg --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            } catch { }
        }
        # Refresh PATH and recheck
        $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" + [Environment]::GetEnvironmentVariable("Path", "Machine")
        if ($needRipgrep -and (Get-Command rg -ErrorAction SilentlyContinue)) {
            Write-Success "ripgrep 安装完成"
            $script:HasRipgrep = $true
            $needRipgrep = $false
        }
        if ($needFfmpeg -and (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
            Write-Success "ffmpeg 安装完成"
            $script:HasFfmpeg = $true
            $needFfmpeg = $false
        }
        if (-not $needRipgrep -and -not $needFfmpeg) { return }
    }

    # Fallback: choco
    if ($hasChoco -and ($needRipgrep -or $needFfmpeg)) {
        Write-Info "正在尝试 Chocolatey..."
        foreach ($pkg in $chocoPkgs) {
            try { choco install $pkg -y 2>&1 | Out-Null } catch { }
        }
        if ($needRipgrep -and (Get-Command rg -ErrorAction SilentlyContinue)) {
            Write-Success "已通过 chocolatey 安装 ripgrep"
            $script:HasRipgrep = $true
            $needRipgrep = $false
        }
        if ($needFfmpeg -and (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
            Write-Success "已通过 chocolatey 安装 ffmpeg"
            $script:HasFfmpeg = $true
            $needFfmpeg = $false
        }
    }

    # Fallback: scoop
    if ($hasScoop -and ($needRipgrep -or $needFfmpeg)) {
        Write-Info "正在尝试 Scoop..."
        foreach ($pkg in $scoopPkgs) {
            try { scoop install $pkg 2>&1 | Out-Null } catch { }
        }
        if ($needRipgrep -and (Get-Command rg -ErrorAction SilentlyContinue)) {
            Write-Success "已通过 scoop 安装 ripgrep"
            $script:HasRipgrep = $true
            $needRipgrep = $false
        }
        if ($needFfmpeg -and (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
            Write-Success "已通过 scoop 安装 ffmpeg"
            $script:HasFfmpeg = $true
            $needFfmpeg = $false
        }
    }

    # Show manual instructions for anything still missing
    if ($needRipgrep) {
        Write-Warn "未安装 ripgrep（文件搜索将回退到 findstr）"
        Write-Info "  winget install BurntSushi.ripgrep.MSVC"
    }
    if ($needFfmpeg) {
        Write-Warn "未安装 ffmpeg（TTS 语音消息能力会受限）"
        Write-Info "  winget install Gyan.FFmpeg"
    }
}

# ============================================================================
# Installation
# ============================================================================

function Install-Repository {
    Write-Info "正在安装到 $InstallDir ..."
    
    if (Test-Path $InstallDir) {
        if (Test-Path "$InstallDir\.git") {
            Write-Info "检测到已有安装，正在更新..."
            Push-Location $InstallDir
            Ensure-OriginPointsToMirror
            Invoke-GitCommand fetch origin
            Invoke-GitCommand checkout $Branch
            Invoke-GitCommand pull origin $Branch
            Pop-Location
        } else {
            Write-Err "目录已存在，但不是 Git 仓库：$InstallDir"
            Write-Info "请删除该目录，或通过 -InstallDir 指定其他安装位置"
            throw "Directory exists but is not a git repository: $InstallDir"
        }
    } else {
        $cloneSuccess = $false
        $hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
        $mirrorZipUrls = @("$MirrorBaseUrl/hermes-agent-$Branch.zip$MirrorCacheBustQuery")
        if ($Branch -ne "main") {
            $mirrorZipUrls += "$MirrorBaseUrl/hermes-agent-main.zip$MirrorCacheBustQuery"
        }

        # 1) 优先使用 CNB.cool 镜像仓库
        if (-not $cloneSuccess) {
            Write-Info "正在尝试通过 CNB.cool 镜像克隆..."
            if ($hasGit) {
                Write-Info "正在为 Windows 兼容性配置 Git..."
                $env:GIT_CONFIG_COUNT = "1"
                $env:GIT_CONFIG_KEY_0 = "windows.appendAtomically"
                $env:GIT_CONFIG_VALUE_0 = "false"
                git config --global windows.appendAtomically false 2>$null
                try {
                    Invoke-GitCommand clone --branch $Branch $RepoUrlCnb $InstallDir
                    if ($LASTEXITCODE -eq 0) { $cloneSuccess = $true }
                } catch { }
            } else {
                Write-Warn "当前系统未安装 Git，跳过 CNB.cool 克隆。"
                Write-Info "  请前往 https://git-scm.com/install/windows 下载安装 Git，安装完成后重新打开终端再试一次。"
            }
        }

        # 2) 再尝试国内镜像源码包
        if (-not $cloneSuccess) {
            if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue }
            Write-Info "CNB.cool 不可用，正在回退到国内镜像源码包..."
            foreach ($zipUrl in $mirrorZipUrls) {
                try {
                    Write-Info "正在下载源码包：$zipUrl"
                    $zipPath = Join-Path $env:TEMP "hermes-agent-$Branch.zip"
                    $extractPath = Join-Path $env:TEMP "hermes-agent-extract"
                    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
                    if (Test-Path $extractPath) { Remove-Item -Recurse -Force $extractPath }
                    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

                    $extractedDir = Get-ChildItem $extractPath -Directory | Select-Object -First 1
                    if ($extractedDir) {
                        New-Item -ItemType Directory -Force -Path (Split-Path $InstallDir) -ErrorAction SilentlyContinue | Out-Null
                        Move-Item $extractedDir.FullName $InstallDir -Force

                        Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
                        Remove-Item -Recurse -Force $extractPath -ErrorAction SilentlyContinue
                        Write-Success "已通过国内镜像下载并解压源码包"
                        $cloneSuccess = $true

                        # Git 初始化仅为 best-effort：即使系统没装 Git 也不影响本次安装
                        if ($hasGit) {
                            Push-Location $InstallDir
                            try {
                                $hasWorkingGit = $false
                                if (Test-Path "$InstallDir\.git") {
                                    git rev-parse HEAD 2>$null | Out-Null
                                    if ($LASTEXITCODE -eq 0) { $hasWorkingGit = $true }
                                }

                                if ($hasWorkingGit) {
                                    Invoke-GitCommand config windows.appendAtomically false 2>$null
                                    Write-Success "源码包自带 Git 元数据，后续可直接执行 hermes update"
                                } else {
                                    Invoke-GitCommand init 2>$null | Out-Null
                                    Invoke-GitCommand config windows.appendAtomically false 2>$null
                                    git remote add origin $RepoUrlCnb 2>$null
                                    Write-Success "已初始化本地 Git 仓库，后续可继续执行更新"
                                }
                            } catch {
                                Write-Warn "Git 元数据初始化失败；后续 hermes update 可能不可用"
                            }
                            Pop-Location
                        } else {
                            Write-Warn "当前系统未安装 Git，本次使用源码包安装；如需后续执行 hermes update，请先安装 Git"
                            Write-Info "  请前往 https://git-scm.com/install/windows 下载安装 Git，安装完成后重新打开终端再试一次。"
                        }

                        break
                    }
                } catch { }
            }
        }

        # 3) 最后回退到 GitHub
        if (-not $cloneSuccess) {
            if ($hasGit) {
                if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue }
                Write-Info "国内镜像源码包不可用，正在回退到 GitHub SSH..."
                try {
                    $env:GIT_SSH_COMMAND = "ssh -o BatchMode=yes -o ConnectTimeout=5"
                    Invoke-GitCommand clone --branch $Branch $RepoUrlSsh $InstallDir
                    if ($LASTEXITCODE -eq 0) { $cloneSuccess = $true }
                } catch { }
                $env:GIT_SSH_COMMAND = $null
            }

            if (-not $cloneSuccess) {
                if ($hasGit) {
                    if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue }
                    Write-Info "GitHub SSH 失败，正在尝试 GitHub HTTPS..."
                    try {
                        Invoke-GitCommand clone --branch $Branch $RepoUrlHttps $InstallDir
                        if ($LASTEXITCODE -eq 0) { $cloneSuccess = $true }
                    } catch { }
                }
            }

            if (-not $cloneSuccess) {
                if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue }
                Write-Warn "GitHub 仓库克隆失败 —— 正在回退为 GitHub ZIP 源码包..."
                try {
                    $zipUrl = "https://github.com/NousResearch/hermes-agent/archive/refs/heads/$Branch.zip"
                    $zipPath = "$env:TEMP\hermes-agent-$Branch.zip"
                    $extractPath = "$env:TEMP\hermes-agent-extract"

                    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
                    if (Test-Path $extractPath) { Remove-Item -Recurse -Force $extractPath }
                    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

                    # GitHub ZIPs extract to repo-branch/ subdirectory
                    $extractedDir = Get-ChildItem $extractPath -Directory | Select-Object -First 1
                    if ($extractedDir) {
                        New-Item -ItemType Directory -Force -Path (Split-Path $InstallDir) -ErrorAction SilentlyContinue | Out-Null
                        Move-Item $extractedDir.FullName $InstallDir -Force
                        Write-Success "已下载并解压 GitHub ZIP 源码包"
                        $cloneSuccess = $true

                        if ($hasGit) {
                            Push-Location $InstallDir
                            try {
                                Invoke-GitCommand init 2>$null
                                Invoke-GitCommand config windows.appendAtomically false 2>$null
                                git remote add origin $RepoUrlCnb 2>$null
                                Write-Success "已初始化 Git 仓库，后续可继续更新"
                            } catch {
                                Write-Warn "Git 元数据初始化失败；后续 hermes update 可能不可用"
                            }
                            Pop-Location
                        } else {
                            Write-Warn "当前系统未安装 Git，本次使用源码包安装；如需后续执行 hermes update，请先安装 Git"
                            Write-Info "  请前往 https://git-scm.com/install/windows 下载安装 Git，安装完成后重新打开终端再试一次。"
                        }
                    }

                    Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
                    Remove-Item -Recurse -Force $extractPath -ErrorAction SilentlyContinue
                } catch {
                    Write-Err "GitHub ZIP 下载也失败了：$_"
                }
            }
        }

        if (-not $cloneSuccess) {
            throw "Failed to download repository (tried git clone SSH, HTTPS, and ZIP)"
        }
    }
    
    # Set per-repo config (harmless if it fails)
    if ($hasGit) {
        Push-Location $InstallDir
        Invoke-GitCommand config windows.appendAtomically false 2>$null
    } else {
        Push-Location $InstallDir
    }

    # Ensure submodules are initialized and updated only when explicitly requested
    if ($hasGit) {
        if ($WithOptionalExtras) {
            Write-Info "已启用 -WithOptionalExtras，正在初始化子模块..."
            try {
                Invoke-GitCommand submodule update --init --recursive 2>$null
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "子模块初始化失败（可选终端 / RL 工具可能需要后续手动安装）"
                } else {
                    Write-Success "子模块已就绪"
                }
            } catch {
                Write-Warn "子模块初始化失败（可选终端 / RL 工具可能需要后续手动安装）"
            }
        } else {
            Write-Info "为提高 Windows 直装成功率，默认跳过可选子模块初始化。"
            Write-Info "如需 RL / 其他扩展组件，可稍后在仓库目录中手动执行："
            Write-Info "  git submodule update --init --recursive"
        }
    }
    Pop-Location
    
    Write-Success "代码仓库已就绪"
}

function Install-Venv {
    if ($NoVenv) {
        Write-Info "跳过虚拟环境创建（-NoVenv）"
        return
    }
    
    Write-Info "正在使用 Python $PythonVersion 创建虚拟环境..."
    
    Push-Location $InstallDir
    
    if (Test-Path "venv") {
        Write-Info "检测到虚拟环境已存在，正在重新创建..."
        Remove-Item -Recurse -Force "venv"
    }
    
    if ($script:PythonSpecifier -and (Test-Path $script:PythonSpecifier)) {
        & $script:PythonSpecifier -m venv venv
        if ($LASTEXITCODE -eq 0) {
            Pop-Location
            Write-Success "虚拟环境已就绪（Python $PythonVersion）"
            return
        }
        Write-Warn "系统 Python 创建虚拟环境失败，正在尝试使用 uv 方式兜底..."
    }

    if (-not $script:UvCmd) {
        Pop-Location
        throw "无法创建虚拟环境：系统 Python 创建失败，且 uv 不可用。"
    }

    # uv-created virtualenvs do not include pip unless explicitly seeded.
    # The next installation step immediately invokes `python -m pip`, so we
    # must request a seeded environment here.
    & $UvCmd venv venv --python $script:PythonSpecifier --seed
    
    Pop-Location
    
    Write-Success "虚拟环境已就绪（Python $PythonVersion）"
}

function Install-Dependencies {
    Write-Info "正在安装依赖..."
    
    Push-Location $InstallDir
    
    $venvPython = "$InstallDir\venv\Scripts\python.exe"
    if (-not (Test-Path $venvPython)) {
        Pop-Location
        throw "未找到虚拟环境中的 Python：$venvPython"
    }

    Write-Info "当前首选 pip 镜像源：$PipIndexUrl"
    Write-Info "正在升级 pip / setuptools / wheel ..."
    if (-not (Invoke-PipWithFallback -PythonExe $venvPython -PipArgs @("install", "--upgrade", "pip", "setuptools", "wheel"))) {
        Pop-Location
        throw "升级 pip / setuptools / wheel 失败"
    }

    if ($WithOptionalExtras) {
        Write-Info "已启用 -WithOptionalExtras，正在安装扩展依赖（时间可能较长）..."
        if (-not (Invoke-PipWithFallback -PythonExe $venvPython -PipArgs @("install", "-e", ".[all]"))) {
            Write-Warn "扩展依赖安装失败，正在回退到核心依赖安装..."
            if (-not (Invoke-PipWithFallback -PythonExe $venvPython -PipArgs @("install", "-e", "."))) {
                Pop-Location
                throw "安装核心依赖也失败"
            }
        }
        Write-Success "扩展依赖安装完成"
    } else {
        Write-Info "为提高 Windows 直装速度与成功率，默认只安装 Hermes 核心依赖。"
        Write-Info "浏览器、RL 训练等体积较大 / 不常用扩展默认跳过；后续如有需要可再单独补装。"
        if (-not (Invoke-PipWithFallback -PythonExe $venvPython -PipArgs @("install", "-e", "."))) {
            Pop-Location
            throw "安装核心依赖失败"
        }
    }
    
    Write-Success "主包安装完成"
    
    # Install optional submodules only when explicitly requested
    if ($WithOptionalExtras) {
        Write-Info "正在安装 tinker-atropos（RL 训练后端）..."
        if (Test-Path "tinker-atropos\pyproject.toml") {
            try {
                if (Invoke-PipWithFallback -PythonExe $venvPython -PipArgs @("install", "-e", ".\\tinker-atropos")) {
                    Write-Success "tinker-atropos 安装完成"
                } else {
                    Write-Warn "tinker-atropos 安装失败（RL 工具可能不可用）"
                }
            } catch {
                Write-Warn "tinker-atropos 安装失败（RL 工具可能不可用）"
            }
        } else {
            Write-Warn "未找到 tinker-atropos（可执行：git submodule update --init）"
        }
    } else {
        Write-Info "如需安装完整扩展依赖，可稍后在仓库目录中执行："
        Write-Info '  .\venv\Scripts\python.exe -m pip install -e ".[all]"'
    }
    
    Pop-Location
    
    Write-Success "依赖安装完成"
}

function Set-PathVariable {
    Write-Info "正在设置 hermes 命令..."
    
    if ($NoVenv) {
        $hermesBin = "$InstallDir"
    } else {
        $hermesBin = "$InstallDir\venv\Scripts"
    }
    
    # Add the venv Scripts dir to user PATH so hermes is globally available
    # On Windows, the hermes.exe in venv\Scripts\ has the venv Python baked in
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    
    if ($currentPath -notlike "*$hermesBin*") {
        [Environment]::SetEnvironmentVariable(
            "Path",
            "$hermesBin;$currentPath",
            "User"
        )
        Write-Success "已加入用户 PATH：$hermesBin"
    } else {
        Write-Info "PATH 已配置，无需重复写入"
    }
    
    # Set HERMES_HOME so the Python code finds config/data in the right place.
    # Only needed on Windows where we install to %LOCALAPPDATA%\hermes instead
    # of the Unix default ~/.hermes
    $currentHermesHome = [Environment]::GetEnvironmentVariable("HERMES_HOME", "User")
    if (-not $currentHermesHome -or $currentHermesHome -ne $HermesHome) {
        [Environment]::SetEnvironmentVariable("HERMES_HOME", $HermesHome, "User")
        Write-Success "已设置 HERMES_HOME=$HermesHome"
    }
    $env:HERMES_HOME = $HermesHome
    
    # Update current session
    $env:Path = "$hermesBin;$env:Path"
    
    Write-Success "hermes 命令已就绪"
}

function Copy-ConfigTemplates {
    Write-Info "正在设置配置文件..."
    
    # Create ~/.hermes directory structure
    New-Item -ItemType Directory -Force -Path "$HermesHome\cron" | Out-Null
    New-Item -ItemType Directory -Force -Path "$HermesHome\sessions" | Out-Null
    New-Item -ItemType Directory -Force -Path "$HermesHome\logs" | Out-Null
    New-Item -ItemType Directory -Force -Path "$HermesHome\pairing" | Out-Null
    New-Item -ItemType Directory -Force -Path "$HermesHome\hooks" | Out-Null
    New-Item -ItemType Directory -Force -Path "$HermesHome\image_cache" | Out-Null
    New-Item -ItemType Directory -Force -Path "$HermesHome\audio_cache" | Out-Null
    New-Item -ItemType Directory -Force -Path "$HermesHome\memories" | Out-Null
    New-Item -ItemType Directory -Force -Path "$HermesHome\skills" | Out-Null
    New-Item -ItemType Directory -Force -Path "$HermesHome\whatsapp\session" | Out-Null
    
    # Create .env
    $envPath = "$HermesHome\.env"
    if (-not (Test-Path $envPath)) {
        $examplePath = "$InstallDir\.env.example"
        if (Test-Path $examplePath) {
            Copy-Item $examplePath $envPath
            Write-Success "已根据模板创建 ~/.hermes/.env"
        } else {
            New-Item -ItemType File -Force -Path $envPath | Out-Null
            Write-Success "已创建 ~/.hermes/.env"
        }
    } else {
        Write-Info "~/.hermes/.env 已存在，保留现有内容"
    }
    
    # Create config.yaml
    $configPath = "$HermesHome\config.yaml"
    if (-not (Test-Path $configPath)) {
        $examplePath = "$InstallDir\cli-config.yaml.example"
        if (Test-Path $examplePath) {
            Copy-Item $examplePath $configPath
            Write-Success "已根据模板创建 ~/.hermes/config.yaml"
        }
    } else {
        Write-Info "~/.hermes/config.yaml 已存在，保留现有内容"
    }
    
    # Create SOUL.md if it doesn't exist (global persona file)
    $soulPath = "$HermesHome\SOUL.md"
    if (-not (Test-Path $soulPath)) {
        @"
# Hermes Agent Persona

<!-- 
This file defines the agent's personality and tone.
The agent will embody whatever you write here.
Edit this to customize how Hermes communicates with you.

Examples:
  - "You are a warm, playful assistant who uses kaomoji occasionally."
  - "You are a concise technical expert. No fluff, just facts."
  - "You speak like a friendly coworker who happens to know everything."

This file is loaded fresh each message -- no restart needed.
Delete the contents (or this file) to use the default personality.
-->
"@ | Set-Content -Path $soulPath -Encoding UTF8
        Write-Success "已创建 ~/.hermes/SOUL.md（可自行编辑个性设定）"
    }
    
    Write-Success "配置目录已就绪：~/.hermes/"
    
    # Seed bundled skills into ~/.hermes/skills/ (manifest-based, one-time per skill)
    Write-Info "正在同步内置技能到 ~/.hermes/skills/ ..."
    $pythonExe = "$InstallDir\venv\Scripts\python.exe"
    if (Test-Path $pythonExe) {
        try {
            & $pythonExe "$InstallDir\tools\skills_sync.py" 2>$null
            Write-Success "技能已同步到 ~/.hermes/skills/"
        } catch {
            # Fallback: simple directory copy
            $bundledSkills = "$InstallDir\skills"
            $userSkills = "$HermesHome\skills"
            if ((Test-Path $bundledSkills) -and -not (Get-ChildItem $userSkills -Exclude '.bundled_manifest' -ErrorAction SilentlyContinue)) {
                Copy-Item -Path "$bundledSkills\*" -Destination $userSkills -Recurse -Force -ErrorAction SilentlyContinue
                Write-Success "技能已复制到 ~/.hermes/skills/"
            }
        }
    }
}

function Install-NodeDeps {
    if (-not $HasNode) {
        Write-Info "跳过 Node.js 依赖安装（当前未安装 Node.js）"
        return
    }

    if (-not $WithOptionalExtras) {
        Write-Warn "为提高 Windows 直装速度，默认跳过浏览器工具与 WhatsApp 桥接的 Node.js 依赖。"
        Write-Info "Hermes 核心功能不受影响；如需补装，请稍后在仓库目录中执行："
        Write-Info "  npm install"
        Write-Info "  cd scripts\\whatsapp-bridge && npm install"
        return
    }
    
    Push-Location $InstallDir
    
    if (Test-Path "package.json") {
        Write-Info "正在安装 Node.js 依赖（浏览器工具）..."
        try {
            npm install --silent 2>&1 | Out-Null
            Write-Success "Node.js 依赖安装完成"
        } catch {
            Write-Warn "npm install 失败（浏览器工具可能不可用）"
        }
    }
    
    # Install WhatsApp bridge dependencies
    $bridgeDir = "$InstallDir\scripts\whatsapp-bridge"
    if (Test-Path "$bridgeDir\package.json") {
        Write-Info "正在安装 WhatsApp 桥接依赖..."
        Push-Location $bridgeDir
        try {
            npm install --silent 2>&1 | Out-Null
            Write-Success "WhatsApp 桥接依赖安装完成"
        } catch {
            Write-Warn "WhatsApp 桥接 npm install 失败（WhatsApp 可能不可用）"
        }
        Pop-Location
    }
    
    Pop-Location
}

function Patch-HermesSetupLaunchBehavior {
    $setupPy = "$InstallDir\hermes_cli\setup.py"
    if (-not (Test-Path $setupPy)) {
        return
    }

    $content = Get-Content $setupPy -Raw -Encoding UTF8
    if ($content -match 'HERMES_SKIP_AUTO_LAUNCH_CHAT') {
        return
    }

    $old = @"
def _offer_launch_chat():
    """Prompt the user to jump straight into chat after setup."""
    print()
"@

    $new = @"
def _offer_launch_chat():
    """Prompt the user to jump straight into chat after setup."""
    if os.environ.get("HERMES_SKIP_AUTO_LAUNCH_CHAT") == "1":
        print_info("Skipping automatic Hermes chat launch in mirror installer. Run 'hermes' in a fresh terminal when ready.")
        return

    print()
"@

    $updated = $content.Replace($old, $new)
    if ($updated -ne $content) {
        Set-Content -Path $setupPy -Value $updated -Encoding UTF8
        Write-Success "已修补 Hermes 配置向导：镜像安装时跳过自动启动聊天"
    }
}

function Invoke-SetupWizard {
    if ($SkipSetup) {
        Write-Info "跳过配置向导（-SkipSetup）"
        return
    }
    
    Write-Host ""
    Write-Success "Hermes Agent 核心安装已经完成，接下来进入配置 Hermes Agent 环节。"
    Write-Info "Hermes Agent 中文社区：https://hermesagent.org.cn"
    Write-Info "下一步的教程（胎教级别）：https://hermesagent.org.cn/docs/getting-started/setup-wizard"
    Write-Host ""
    Write-Info "正在启动配置向导..."
    Write-Host ""
    
    Push-Location $InstallDir
    
    $oldSkipAutoLaunch = $env:HERMES_SKIP_AUTO_LAUNCH_CHAT
    $env:HERMES_SKIP_AUTO_LAUNCH_CHAT = "1"
    try {
        # Run hermes setup using the venv Python directly (no activation needed)
        if (-not $NoVenv) {
            & ".\venv\Scripts\python.exe" -m hermes_cli.main setup
        } else {
            python -m hermes_cli.main setup
        }
    } finally {
        if ($null -eq $oldSkipAutoLaunch) {
            Remove-Item Env:HERMES_SKIP_AUTO_LAUNCH_CHAT -ErrorAction SilentlyContinue
        } else {
            $env:HERMES_SKIP_AUTO_LAUNCH_CHAT = $oldSkipAutoLaunch
        }
    }
    
    Pop-Location
}

function Start-GatewayIfConfigured {
    $envPath = "$HermesHome\.env"
    if (-not (Test-Path $envPath)) { return }

    $hasMessaging = $false
    $content = Get-Content $envPath -ErrorAction SilentlyContinue
    foreach ($var in @("TELEGRAM_BOT_TOKEN", "DISCORD_BOT_TOKEN", "SLACK_BOT_TOKEN", "SLACK_APP_TOKEN", "WHATSAPP_ENABLED")) {
        $match = $content | Where-Object { $_ -match "^${var}=.+" -and $_ -notmatch "your-token-here" }
        if ($match) { $hasMessaging = $true; break }
    }

    if (-not $hasMessaging) { return }

    $hermesCmd = "$InstallDir\venv\Scripts\hermes.exe"
    if (-not (Test-Path $hermesCmd)) {
        $hermesCmd = "hermes"
    }

    # If WhatsApp is enabled but not yet paired, run foreground for QR scan
    $whatsappEnabled = $content | Where-Object { $_ -match "^WHATSAPP_ENABLED=true" }
    $whatsappSession = "$HermesHome\whatsapp\session\creds.json"
    if ($whatsappEnabled -and -not (Test-Path $whatsappSession)) {
        Write-Host ""
        Write-Info "已启用 WhatsApp，但当前还未完成配对。"
        Write-Info "正在运行 hermes whatsapp，准备通过二维码配对..."
        Write-Host ""
        $response = Read-Host "现在立即配对 WhatsApp 吗？[Y/n]"
        if ($response -eq "" -or $response -match "^[Yy]") {
            try {
                & $hermesCmd whatsapp
            } catch {
                # Expected after pairing completes
            }
        }
    }

    Write-Host ""
    Write-Info "检测到消息平台 Token！"
    Write-Info "网关负责消息平台接入和 cron 定时任务执行。"
    Write-Host ""
    $response = Read-Host "现在立即启动网关吗？[Y/n]"

    if ($response -eq "" -or $response -match "^[Yy]") {
        Write-Info "正在后台启动网关..."
        try {
            $logFile = "$HermesHome\logs\gateway.log"
            Start-Process -FilePath $hermesCmd -ArgumentList "gateway" `
                -RedirectStandardOutput $logFile `
                -RedirectStandardError "$HermesHome\logs\gateway-error.log" `
                -WindowStyle Hidden
            Write-Success "网关已启动！你的机器人现在已经上线。"
            Write-Info "日志位置：$logFile"
            Write-Info "如需停止：请在任务管理器中结束网关进程"
        } catch {
            Write-Warn "网关启动失败。请手动运行：hermes gateway"
        }
    } else {
        Write-Info "已跳过。你可以稍后手动运行：hermes gateway"
    }
}

function Write-Completion {
    Write-Host ""
    Write-Host "┌─────────────────────────────────────────────────────────┐" -ForegroundColor Green
    Write-Host "│                    ✓ 安装完成！                         │" -ForegroundColor Green
    Write-Host "└─────────────────────────────────────────────────────────┘" -ForegroundColor Green
    Write-Host ""
    
    # Show file locations
    Write-Host "📁 你的文件：" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   配置：      " -NoNewline -ForegroundColor Yellow
    Write-Host "$HermesHome\config.yaml"
    Write-Host "   密钥：      " -NoNewline -ForegroundColor Yellow
    Write-Host "$HermesHome\.env"
    Write-Host "   数据：      " -NoNewline -ForegroundColor Yellow
    Write-Host "$HermesHome\cron\, sessions\, logs\"
    Write-Host "   代码：      " -NoNewline -ForegroundColor Yellow
    Write-Host "$HermesHome\hermes-agent\"
    Write-Host ""
    
    Write-Host "─────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "🚀 常用命令：" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   hermes              " -NoNewline -ForegroundColor Green
    Write-Host "开始聊天"
    Write-Host "   hermes setup        " -NoNewline -ForegroundColor Green
    Write-Host "配置 API Key 和设置"
    Write-Host "   hermes config       " -NoNewline -ForegroundColor Green
    Write-Host "查看 / 编辑配置"
    Write-Host "   hermes config edit  " -NoNewline -ForegroundColor Green
    Write-Host "在编辑器中打开配置"
    Write-Host "   hermes gateway      " -NoNewline -ForegroundColor Green
    Write-Host "启动消息网关（Telegram、Discord 等）"
    Write-Host "   hermes update       " -NoNewline -ForegroundColor Green
    Write-Host "更新到最新版本"
    Write-Host ""
    
    Write-Host "─────────────────────────────────────────────────────────" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "⚡ 请重启终端，让 PATH 变更生效" -ForegroundColor Yellow
    Write-Host ""
    
    if (-not $HasNode) {
        Write-Host "提示：Node.js 无法自动安装。" -ForegroundColor Yellow
        Write-Host "浏览器工具需要 Node.js。请手动安装：" -ForegroundColor Yellow
        Write-Host "  https://nodejs.org/en/download/" -ForegroundColor Yellow
        Write-Host ""
    }
    
    if (-not $HasRipgrep) {
        Write-Host "提示：未安装 ripgrep（rg）。如需更快的文件搜索，请安装：" -ForegroundColor Yellow
        Write-Host "  winget install BurntSushi.ripgrep.MSVC" -ForegroundColor Yellow
        Write-Host ""
    }
}

# ============================================================================
# Main
# ============================================================================

function Main {
    Write-Banner
    Disable-InvalidLocalProxyIfNeeded
    
    Write-Step "第 1 步 / 7：准备 Python 安装工具"
    if (-not (Install-Uv)) { throw "uv installation failed — cannot continue" }

    Write-Step "第 2 步 / 7：准备 Python 运行环境"
    if (-not (Test-Python)) { throw "Python $PythonVersion not available — cannot continue" }

    Write-Step "第 3 步 / 7：检查基础运行环境"
    [void](Test-Node)              # Auto-installs if missing
    [void](Install-SystemPackages)  # optional ripgrep + ffmpeg
    
    Write-Step "第 4 步 / 7：获取 Hermes 代码"
    Install-Repository
    Patch-HermesSetupLaunchBehavior

    Write-Step "第 5 步 / 7：创建独立运行环境"
    Install-Venv

    Write-Step "第 6 步 / 7：安装 Hermes 核心依赖"
    Install-Dependencies

    Write-Step "第 7 步 / 7：写入命令与配置文件"
    Install-NodeDeps
    Set-PathVariable
    Copy-ConfigTemplates
    Invoke-SetupWizard
    Start-GatewayIfConfigured
    
    Write-Completion
}

# Wrap in try/catch so errors don't kill the terminal when run via:
#   irm https://...install.ps1 | iex
# (exit/throw inside iex kills the entire PowerShell session)
try {
    Main
} catch {
    Write-Host ""
    Write-Err "安装失败：$_"
    Write-Host ""
    Write-Info "如果错误原因不明显，可以先下载脚本到本地后再执行："
    Write-Host "  Invoke-WebRequest -Uri 'https://res1.hermesagent.org.cn/install.ps1' -OutFile install.ps1" -ForegroundColor Yellow
    Write-Host "  .\install.ps1" -ForegroundColor Yellow
    Write-Host ""
}
