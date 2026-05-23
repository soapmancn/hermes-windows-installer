#requires -version 5.1
param(
  [string]$Root = "C:\hermes",
  [int]$NodeMajor = 24,
  [string]$HermesBranch = "main",
  [string]$WebUiVersion = "latest",

  # Mainland-friendly defaults. If a GitHub proxy is unavailable in your network,
  # change only -GithubProxy, for example:
  #   -GithubProxy "https://gh-proxy.com/"
  #   -GithubProxy "https://gh.llkk.cc/"
  #   -GithubProxy "https://ghfast.top/"
  # Use empty string to disable GitHub proxy fallback.
  [string]$NodeMirror = "https://npmmirror.com/mirrors/node",
  [string]$NpmRegistry = "https://registry.npmmirror.com",
  [string]$PypiIndex = "https://pypi.tuna.tsinghua.edu.cn/simple",
  [string]$GithubProxy = "https://ghfast.top/",
  [string]$UvVersion = "0.11.16",
  [switch]$UseWindowsTerminal,
  [string]$WindowsTerminal = "",
  [switch]$NoWindowsTerminalRelaunch
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Warn($m) { Write-Host "WARN: $m" -ForegroundColor Yellow }
function New-Dir($p) { New-Item -ItemType Directory -Force -Path $p | Out-Null }
function Norm([string]$p) {
  if (-not $p) { return "" }
  return $p.Trim().TrimEnd("\").ToLowerInvariant()
}

function Join-Url([string]$Base, [string]$Path) {
  if (-not $Base) { return $Path }
  return $Base.TrimEnd("/") + "/" + $Path.TrimStart("/")
}

function Use-GithubProxy([string]$Url) {
  if ([string]::IsNullOrWhiteSpace($GithubProxy)) { return $Url }
  return $GithubProxy.TrimEnd("/") + "/" + $Url
}

function Download([string[]]$Uris, [string]$Out) {
  $lastError = $null
  foreach ($uri in $Uris) {
    if ([string]::IsNullOrWhiteSpace($uri)) { continue }
    try {
      Info "Downloading $uri"
      Invoke-WebRequest -Uri $uri -OutFile $Out -UseBasicParsing -TimeoutSec 120
      if ((Test-Path $Out) -and ((Get-Item $Out).Length -gt 0)) { return }
    } catch {
      $lastError = $_
      Warn "Download failed, trying next source: $uri"
    }
  }
  throw "All download sources failed. Last error: $lastError"
}

function Add-UserPathEntries([string[]]$Entries) {
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $items = @()
  if ($userPath) { $items = $userPath -split ";" | Where-Object { $_ } }
  foreach ($entry in $Entries) {
    if (-not ($items | Where-Object { (Norm $_) -eq (Norm $entry) })) {
      $items += $entry
    }
  }
  [Environment]::SetEnvironmentVariable("Path", ($items -join ";"), "User")
}

function Quote-CmdArg([string]$Value) {
  if ($null -eq $Value) { return '""' }
  return '"' + ($Value -replace '"', '\"') + '"'
}

function Quote-PsString([string]$Value) {
  if ($null -eq $Value) { return "''" }
  return "'" + ($Value -replace "'", "''") + "'"
}

function Resolve-WindowsTerminal([string]$RequestedPath, [string]$InstallRoot) {
  $candidates = @()
  if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) { $candidates += $RequestedPath }
  if ($PSScriptRoot) {
    $candidates += (Join-Path $PSScriptRoot "wt.exe")
    $candidates += (Join-Path $PSScriptRoot "WindowsTerminal\wt.exe")
    $candidates += (Join-Path $PSScriptRoot "WindowsTerminal\WindowsTerminal.exe")
  }
  $candidates += (Join-Path $InstallRoot "WindowsTerminal\wt.exe")
  $candidates += (Join-Path $InstallRoot "WindowsTerminal\WindowsTerminal.exe")
  $candidates += (Join-Path $InstallRoot "wt.exe")
  $candidates += (Join-Path $InstallRoot "WindowsTerminal.exe")

  foreach ($candidate in $candidates) {
    if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
    try {
      $full = [IO.Path]::GetFullPath($candidate)
      if (Test-Path $full -PathType Leaf) { return $full }
      if (Test-Path $full -PathType Container) {
        foreach ($exe in @("wt.exe", "WindowsTerminal.exe")) {
          $child = Join-Path $full $exe
          if (Test-Path $child -PathType Leaf) { return $child }
        }
      }
    } catch {}
  }

  foreach ($name in @("wt.exe", "WindowsTerminal.exe")) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path $cmd.Source)) { return $cmd.Source }
  }

  return $null
}

function Restart-InWindowsTerminal {
  if (-not $UseWindowsTerminal -or $NoWindowsTerminalRelaunch -or $env:WT_SESSION) { return }

  $installRoot = [IO.Path]::GetFullPath($Root).TrimEnd("\")
  $wt = Resolve-WindowsTerminal $WindowsTerminal $installRoot
  if (-not $wt) {
    throw "Windows Terminal not found. Use -WindowsTerminal `"C:\path\to\wt.exe`", or put wt.exe under the script folder / $installRoot\WindowsTerminal."
  }

  New-Item -ItemType Directory -Force -Path (Join-Path $installRoot "logs") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $installRoot "tmp") | Out-Null
  $log = Join-Path $installRoot "logs\install.log"
  $script = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
  if (-not $script) { throw "Cannot determine current install script path." }

  $wrapper = Join-Path $installRoot "tmp\install-hermes-in-windows-terminal.ps1"
  @"
`$ErrorActionPreference = "Stop"
try { Start-Transcript -Path $(Quote-PsString $log) -Append | Out-Null } catch {}
try {
  & $(Quote-PsString $script) -Root $(Quote-PsString $installRoot) -NodeMajor $NodeMajor -HermesBranch $(Quote-PsString $HermesBranch) -WebUiVersion $(Quote-PsString $WebUiVersion) -NodeMirror $(Quote-PsString $NodeMirror) -NpmRegistry $(Quote-PsString $NpmRegistry) -PypiIndex $(Quote-PsString $PypiIndex) -GithubProxy $(Quote-PsString $GithubProxy) -UvVersion $(Quote-PsString $UvVersion) -NoWindowsTerminalRelaunch
} finally {
  try { Stop-Transcript | Out-Null } catch {}
}
"@ | Set-Content -Path $wrapper -Encoding UTF8

  $wtArgs = "new-tab --title `"Hermes Installer`" powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File $(Quote-CmdArg $wrapper)"
  Info "Opening Windows Terminal: $wt"
  Info "Install log: $log"
  Start-Process -FilePath $wt -ArgumentList $wtArgs
  exit 0
}

$Root = [IO.Path]::GetFullPath($Root).TrimEnd("\")
Restart-InWindowsTerminal
$AgentDir = Join-Path $Root "hermes-agent"

New-Dir $Root
New-Dir "$Root\tmp"
New-Dir "$Root\bin"
New-Dir "$Root\cache\npm"
New-Dir "$Root\cache\uv"
New-Dir "$Root\npm-global"
New-Dir "$Root\hermes-web-ui-home"
New-Dir "$Root\ms-playwright"
New-Dir "$Root\logs"

function Set-HermesSessionEnv {
  $env:HERMES_ROOT = $Root
  $env:HERMES_HOME = $Root
  $env:HERMES_AGENT_DIR = $AgentDir
  $env:HERMES_WEB_UI_HOME = "$Root\hermes-web-ui-home"
  $env:PLAYWRIGHT_BROWSERS_PATH = "$Root\ms-playwright"
  $env:NPM_CONFIG_PREFIX = "$Root\npm-global"
  $env:npm_config_prefix = "$Root\npm-global"
  $env:NPM_CONFIG_CACHE = "$Root\cache\npm"
  $env:npm_config_cache = "$Root\cache\npm"
  $env:NPM_CONFIG_REGISTRY = $NpmRegistry
  $env:npm_config_registry = $NpmRegistry
  $env:UV_INSTALL_DIR = "$Root\uv"
  $env:UV_PYTHON_INSTALL_DIR = "$Root\uv-python"
  $env:UV_PYTHON_CACHE_DIR = "$Root\cache\uv\python"
  $env:UV_PYTHON_PREFERENCE = "only-managed"
  # Newer uv rejects UV_MANAGED_PYTHON when UV_PYTHON_PREFERENCE is set.
  Remove-Item Env:UV_MANAGED_PYTHON -ErrorAction SilentlyContinue
  $env:UV_PYTHON_NO_REGISTRY = "1"
  $env:UV_CACHE_DIR = "$Root\cache\uv"
  $env:UV_DEFAULT_INDEX = $PypiIndex
  $env:UV_INDEX_URL = $PypiIndex
  $env:PIP_INDEX_URL = $PypiIndex
  $env:UV_PYTHON_INSTALL_MIRROR = (Use-GithubProxy "https://github.com/astral-sh/python-build-standalone/releases/download")
  $env:HERMES_GIT_BASH_PATH = "$Root\git\bin\bash.exe"

  # Make git clone/fetch from github.com go through the proxy without touching
  # the user's global .gitconfig.
  if (-not [string]::IsNullOrWhiteSpace($GithubProxy)) {
    $env:GIT_CONFIG_COUNT = "1"
    $env:GIT_CONFIG_KEY_0 = "url.$(Use-GithubProxy 'https://github.com/').insteadOf"
    $env:GIT_CONFIG_VALUE_0 = "https://github.com/"
  }

  $env:Path = "$Root;$Root\node;$Root\npm-global;$Root\bin;$Root\git\cmd;$Root\git\bin;$Root\git\usr\bin;$Root\uv;$AgentDir\venv\Scripts;$env:Path"
}
Set-HermesSessionEnv

function Install-Node24 {
  $nodeExe = "$Root\node\node.exe"
  if (Test-Path $nodeExe) {
    $v = & $nodeExe -v
    if ($v -match "^v$NodeMajor\.") {
      Info "Node $v already installed"
      return
    }
  }

  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $env:PROCESSOR_ARCHITEW6432 -eq "ARM64") { "arm64" } elseif ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
  $zipName = $null
  $versionDir = $null
  $fileKey = "win-$arch-zip"

  foreach ($idx in @((Join-Url $NodeMirror "index.json"), "https://nodejs.org/dist/index.json")) {
    try {
      Info "Reading Node index $idx"
      $json = (Invoke-WebRequest -Uri $idx -UseBasicParsing -TimeoutSec 120).Content | ConvertFrom-Json
      $release = $json |
        Where-Object { $_.version -match "^v$NodeMajor\." -and $_.files -contains $fileKey } |
        Select-Object -First 1
      if ($release) {
        $versionDir = $release.version
        $zipName = "node-$versionDir-win-$arch.zip"
        break
      }
    } catch {
      Warn "Node index failed: $idx"
    }
  }

  if (-not $zipName) {
    foreach ($idx in @((Join-Url $NodeMirror "latest-v$NodeMajor.x/"), "https://nodejs.org/dist/latest-v$NodeMajor.x/")) {
      try {
        Info "Reading Node directory $idx"
        $html = (Invoke-WebRequest -Uri $idx -UseBasicParsing -TimeoutSec 120).Content
        $match = [regex]::Match($html, "node-v$NodeMajor\.\d+\.\d+-win-$([regex]::Escape($arch))\.zip")
        if ($match.Success) {
          $zipName = $match.Value
          $versionDir = $zipName -replace "^node-(v\d+\.\d+\.\d+)-win-.+$", '$1'
          break
        }
      } catch {
        Warn "Node directory failed: $idx"
      }
    }
  }

  if (-not $zipName -or -not $versionDir) {
    throw "Cannot find Node.js $NodeMajor Windows $arch zip. Try: -NodeMirror https://nodejs.org/dist or change -NodeMajor."
  }

  $zip = "$Root\tmp\$zipName"
  $extract = "$Root\tmp\node-extract"

  Download @(
    (Join-Url $NodeMirror "$versionDir/$zipName"),
    (Join-Url $NodeMirror "latest-v$NodeMajor.x/$zipName"),
    "https://nodejs.org/dist/$versionDir/$zipName",
    "https://nodejs.org/dist/latest-v$NodeMajor.x/$zipName"
  ) $zip

  if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
  Expand-Archive -Path $zip -DestinationPath $extract -Force
  if (Test-Path "$Root\node") { Remove-Item -Recurse -Force "$Root\node" }
  Move-Item (Get-ChildItem $extract -Directory | Select-Object -First 1).FullName "$Root\node"
}

function Install-Uv {
  if (Test-Path "$Root\uv\uv.exe") {
    Info "uv already installed"
    return
  }

  New-Dir "$Root\uv"
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $env:PROCESSOR_ARCHITEW6432 -eq "ARM64") {
    "aarch64-pc-windows-msvc"
  } elseif ([Environment]::Is64BitOperatingSystem) {
    "x86_64-pc-windows-msvc"
  } else {
    "i686-pc-windows-msvc"
  }

  $asset = "uv-$arch.zip"
  $zip = "$Root\tmp\$asset"
  Download @(
    (Use-GithubProxy "https://github.com/astral-sh/uv/releases/download/$UvVersion/$asset"),
    "https://releases.astral.sh/github/uv/releases/download/$UvVersion/$asset",
    "https://github.com/astral-sh/uv/releases/download/$UvVersion/$asset"
  ) $zip

  $extract = "$Root\tmp\uv-extract"
  if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
  Expand-Archive $zip $extract -Force
  Copy-Item (Get-ChildItem $extract -Recurse -Filter uv.exe | Select-Object -First 1).FullName "$Root\uv\uv.exe" -Force
  Copy-Item (Get-ChildItem $extract -Recurse -Filter uvx.exe | Select-Object -First 1).FullName "$Root\uv\uvx.exe" -Force
}

function Get-PortableHermesPython {
  if (-not (Test-Path "$Root\uv-python")) { return $null }
  return Get-ChildItem "$Root\uv-python" -Recurse -Filter python.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match "cpython-3\.11" -and $_.FullName -notmatch "\\venv\\" -and $_.FullName -notmatch "\\Scripts\\" } |
    Sort-Object FullName |
    Select-Object -First 1
}

function Install-HermesPython {
  $uv = "$Root\uv\uv.exe"
  if (-not (Test-Path $uv)) { throw "uv.exe not found at $uv" }

  New-Dir "$Root\uv-python"
  Set-HermesSessionEnv

  $existing = Get-PortableHermesPython
  if ($existing) {
    $env:HERMES_PORTABLE_PYTHON_EXE = $existing.FullName
    Info "Portable Python already installed: $($existing.FullName)"
    return
  }

  Info "Installing portable Python 3.11 under $Root\uv-python"
  & $uv python install 3.11 --install-dir "$Root\uv-python"
  if ($LASTEXITCODE -ne 0) { throw "uv python install 3.11 failed" }

  $py = Get-PortableHermesPython
  if (-not $py) { throw "Python 3.11 was installed, but python.exe was not found under $Root\uv-python" }
  $env:HERMES_PORTABLE_PYTHON_EXE = $py.FullName
  [Environment]::SetEnvironmentVariable("HERMES_PORTABLE_PYTHON_EXE", $py.FullName, "User")
  Info "Portable Python ready: $($py.FullName)"
}

function Patch-HermesAgentInstaller([string]$InstallerPath) {
  $py = Get-PortableHermesPython
  if (-not $py) { throw "Portable Python not found before patching Hermes installer" }
  $env:HERMES_PORTABLE_PYTHON_EXE = $py.FullName

  $old = '& $UvCmd venv venv --python $PythonVersion'
  $new = 'if ($env:HERMES_PORTABLE_PYTHON_EXE -and (Test-Path $env:HERMES_PORTABLE_PYTHON_EXE)) { & $UvCmd venv venv --python $env:HERMES_PORTABLE_PYTHON_EXE } else { & $UvCmd venv venv --python $PythonVersion }'
  $content = Get-Content -LiteralPath $InstallerPath -Raw
  $changed = $false

  if ($content.Contains($old)) {
    $content = $content.Replace($old, $new)
    $changed = $true
    Info "Patched Hermes installer to use portable Python: $($py.FullName)"
  } else {
    Warn "Could not patch Hermes installer venv command; it may still use uv's default Python discovery."
  }

  if (-not [string]::IsNullOrWhiteSpace($GithubProxy)) {
    $directRepoBase = "https://github.com/NousResearch/hermes-agent"
    $proxiedRepoBase = Use-GithubProxy $directRepoBase
    $sshRepoUrl = "git@github.com:NousResearch/hermes-agent.git"
    $proxiedRepoUrl = Use-GithubProxy "$directRepoBase.git"
    $urlChanged = $false

    if ($content.Contains($directRepoBase)) {
      $content = $content.Replace($directRepoBase, $proxiedRepoBase)
      $changed = $true
      $urlChanged = $true
    }
    if ($content.Contains($sshRepoUrl)) {
      $content = $content.Replace($sshRepoUrl, $proxiedRepoUrl)
      $changed = $true
      $urlChanged = $true
    }
    if ($urlChanged) {
      Info "Patched Hermes installer GitHub URLs to use proxy: $($GithubProxy.TrimEnd('/'))"
    }
  }

  if ($changed) {
    Set-Content -LiteralPath $InstallerPath -Value $content -Encoding UTF8
  }
}

function Install-PortableGit {
  if (Test-Path "$Root\git\cmd\git.exe") {
    Info "Portable Git already installed"
    return
  }

  $gitTag = "v2.54.0.windows.1"
  $gitVer = "2.54.0"
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64" -or $env:PROCESSOR_ARCHITEW6432 -eq "ARM64") { "arm64" } else { "64-bit" }
  $asset = if ($arch -eq "arm64") { "PortableGit-$gitVer-arm64.7z.exe" } else { "PortableGit-$gitVer-64-bit.7z.exe" }
  $url = "https://github.com/git-for-windows/git/releases/download/$gitTag/$asset"
  $tmp = "$Root\tmp\$asset"

  Download @((Use-GithubProxy $url), $url) $tmp
  if (Test-Path "$Root\git") { Remove-Item -Recurse -Force "$Root\git" }
  New-Dir "$Root\git"
  $p = Start-Process -FilePath $tmp -ArgumentList "-o`"$Root\git`"", "-y" -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "PortableGit extract failed: $($p.ExitCode)" }
}

function Install-Ripgrep {
  if (Test-Path "$Root\bin\rg.exe") { return }
  $ver = "15.1.0"
  $asset = "ripgrep-$ver-x86_64-pc-windows-msvc.zip"
  $url = "https://github.com/BurntSushi/ripgrep/releases/download/$ver/$asset"
  $zip = "$Root\tmp\ripgrep.zip"
  $extract = "$Root\tmp\ripgrep"
  Download @((Use-GithubProxy $url), $url) $zip
  if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
  Expand-Archive $zip $extract -Force
  Copy-Item (Get-ChildItem $extract -Recurse -Filter rg.exe | Select-Object -First 1).FullName "$Root\bin\rg.exe" -Force
}

function Install-Ffmpeg {
  if (Test-Path "$Root\bin\ffmpeg.exe") { return }
  $asset = "ffmpeg-master-latest-win64-gpl.zip"
  $url = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/$asset"
  $zip = "$Root\tmp\ffmpeg.zip"
  $extract = "$Root\tmp\ffmpeg"
  Download @(
    (Use-GithubProxy $url),
    "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip",
    $url
  ) $zip
  if (Test-Path $extract) { Remove-Item -Recurse -Force $extract }
  Expand-Archive $zip $extract -Force
  $bin = Get-ChildItem $extract -Recurse -Directory | Where-Object { $_.FullName -like "*\bin" } | Select-Object -First 1
  Copy-Item "$($bin.FullName)\ffmpeg.exe" "$Root\bin\ffmpeg.exe" -Force
  Copy-Item "$($bin.FullName)\ffprobe.exe" "$Root\bin\ffprobe.exe" -Force
}

function Write-HelperFiles {
@"
@echo off
set "HERMES_ROOT=%~dp0"
if "%HERMES_ROOT:~-1%"=="\" set "HERMES_ROOT=%HERMES_ROOT:~0,-1%"
set "HERMES_HOME=%HERMES_ROOT%"
set "HERMES_AGENT_DIR=%HERMES_ROOT%\hermes-agent"
set "HERMES_WEB_UI_HOME=%HERMES_ROOT%\hermes-web-ui-home"
set "PLAYWRIGHT_BROWSERS_PATH=%HERMES_ROOT%\ms-playwright"
set "UV_PYTHON_INSTALL_DIR=%HERMES_ROOT%\uv-python"
set "UV_PYTHON_CACHE_DIR=%HERMES_ROOT%\cache\uv\python"
set "UV_PYTHON_PREFERENCE=only-managed"
set "UV_PYTHON_NO_REGISTRY=1"
set "UV_CACHE_DIR=%HERMES_ROOT%\cache\uv"
set "UV_DEFAULT_INDEX=$PypiIndex"
set "UV_INDEX_URL=$PypiIndex"
set "PIP_INDEX_URL=$PypiIndex"
set "UV_PYTHON_INSTALL_MIRROR=$(Use-GithubProxy "https://github.com/astral-sh/python-build-standalone/releases/download")"
set "NPM_CONFIG_PREFIX=%HERMES_ROOT%\npm-global"
set "npm_config_prefix=%HERMES_ROOT%\npm-global"
set "NPM_CONFIG_CACHE=%HERMES_ROOT%\cache\npm"
set "npm_config_cache=%HERMES_ROOT%\cache\npm"
set "NPM_CONFIG_REGISTRY=$NpmRegistry"
set "npm_config_registry=$NpmRegistry"
set "HERMES_GITHUB_PROXY=$GithubProxy"
if not "$GithubProxy"=="" (
  set "GIT_CONFIG_COUNT=1"
  set "GIT_CONFIG_KEY_0=url.$(Use-GithubProxy "https://github.com/").insteadOf"
  set "GIT_CONFIG_VALUE_0=https://github.com/"
)
set "HERMES_GIT_BASH_PATH=%HERMES_ROOT%\git\bin\bash.exe"
set "HERMES_PY=%HERMES_AGENT_DIR%\venv\Scripts\python.exe"
set "HERMES_EXE=%HERMES_AGENT_DIR%\venv\Scripts\hermes.exe"
set "HERMES_BIN=%HERMES_EXE%"
set "HERMES_WEB_UI_BIN=%HERMES_ROOT%\npm-global\node_modules\hermes-web-ui\bin\hermes-web-ui.mjs"
set "PATH=%HERMES_ROOT%;%HERMES_ROOT%\node;%HERMES_ROOT%\npm-global;%HERMES_ROOT%\bin;%HERMES_ROOT%\git\cmd;%HERMES_ROOT%\git\bin;%HERMES_ROOT%\git\usr\bin;%HERMES_ROOT%\uv;%HERMES_AGENT_DIR%\venv\Scripts;%PATH%"
"@ | Set-Content "$Root\hermes-env.cmd" -Encoding ASCII

@'
@echo off
call "%~dp0hermes-env.cmd"
cd /d "%HERMES_AGENT_DIR%"
"%HERMES_PY%" "%HERMES_AGENT_DIR%\hermes" %*
'@ | Set-Content "$Root\hermes.cmd" -Encoding ASCII

@'
@echo off
setlocal EnableExtensions
call "%~dp0hermes-env.cmd"

set "WEBUI_PORT=8648"
set "TOKEN_FILE=%HERMES_WEB_UI_HOME%\.token"
if not exist "%HERMES_WEB_UI_HOME%" mkdir "%HERMES_WEB_UI_HOME%"
if not exist "%TOKEN_FILE%" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=([guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N')); Set-Content -Path '%TOKEN_FILE%' -Value $t -Encoding ASCII"
)
for /f "usebackq delims=" %%T in ("%TOKEN_FILE%") do set "AUTH_TOKEN=%%T"

call "%~dp0hermes-stop.bat" --quiet

if not exist "%HERMES_HOME%\logs" mkdir "%HERMES_HOME%\logs"

echo Starting Hermes gateway...
start "Hermes Gateway" /min cmd /d /c ""%HERMES_PY%" "%HERMES_AGENT_DIR%\hermes" gateway run >> "%HERMES_HOME%\logs\gateway.stdout.log" 2>> "%HERMES_HOME%\logs\gateway.stderr.log""

timeout /t 3 /nobreak >nul

echo Starting Hermes Web UI...
"%HERMES_ROOT%\node\node.exe" "%HERMES_WEB_UI_BIN%" start --port %WEBUI_PORT% >> "%HERMES_WEB_UI_HOME%\web-ui-cli.log" 2>&1

timeout /t 2 /nobreak >nul
powershell -NoProfile -ExecutionPolicy Bypass -Command "$token=(Get-Content -Raw '%TOKEN_FILE%').Trim(); $url='http://127.0.0.1:%WEBUI_PORT%/#/?token=' + [uri]::EscapeDataString($token); Start-Process $url"

echo.
echo Hermes gateway: http://127.0.0.1:8642
echo Hermes Web UI : http://127.0.0.1:%WEBUI_PORT%/#/?token=%AUTH_TOKEN%
endlocal
'@ | Set-Content "$Root\hermes-run.bat" -Encoding ASCII

@'
@echo off
setlocal EnableExtensions
call "%~dp0hermes-env.cmd"

if /i not "%~1"=="--quiet" echo Stopping Hermes Web UI...
if exist "%HERMES_WEB_UI_BIN%" "%HERMES_ROOT%\node\node.exe" "%HERMES_WEB_UI_BIN%" stop >nul 2>nul
call :kill_port 8648

if /i not "%~1"=="--quiet" echo Stopping Hermes gateway...
if exist "%HERMES_PY%" "%HERMES_PY%" "%HERMES_AGENT_DIR%\hermes" gateway stop >nul 2>nul
call :kill_port 8642

exit /b 0

:kill_port
for /f "tokens=5" %%p in ('netstat -ano ^| findstr /R /C:":%~1 .*LISTENING"') do taskkill /PID %%p /T /F >nul 2>nul
exit /b 0
'@ | Set-Content "$Root\hermes-stop.bat" -Encoding ASCII

@'
@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0hermes-upgrade.ps1" %*
exit /b %ERRORLEVEL%
'@ | Set-Content "$Root\hermes-upgrade.bat" -Encoding ASCII

@'
param(
  [switch]$Restart,
  [switch]$Backup,
  [switch]$ForceAgent
)

$ErrorActionPreference = "Stop"
$Root = (Split-Path -Parent $PSCommandPath).TrimEnd("\")
$EnvCmd = Join-Path $Root "hermes-env.cmd"

if (Test-Path $EnvCmd) {
  cmd.exe /d /c "call `"$EnvCmd`" && set" | ForEach-Object {
    $name, $value = $_ -split "=", 2
    if ($name) { Set-Item -Path "Env:$name" -Value $value }
  }
}

$AgentDir = Join-Path $Root "hermes-agent"
$Python = Join-Path $AgentDir "venv\Scripts\python.exe"
$HermesScript = Join-Path $AgentDir "hermes"
$Npm = Join-Path $Root "node\npm.cmd"
$Node = Join-Path $Root "node\node.exe"
$WebCli = Join-Path $Root "npm-global\node_modules\hermes-web-ui\bin\hermes-web-ui.mjs"
$Registry = if ($env:NPM_CONFIG_REGISTRY) { $env:NPM_CONFIG_REGISTRY } else { "https://registry.npmjs.org" }

if (-not (Test-Path $Python)) { throw "Missing Hermes Python: $Python" }
if (-not (Test-Path $HermesScript)) { throw "Missing Hermes launcher: $HermesScript" }
if (-not (Test-Path $Npm)) { throw "Missing npm: $Npm" }

$env:HERMES_ROOT = $Root
$env:HERMES_HOME = $Root
$env:HERMES_AGENT_DIR = $AgentDir
$env:HERMES_WEB_UI_HOME = Join-Path $Root "hermes-web-ui-home"
$env:HERMES_BIN = Join-Path $AgentDir "venv\Scripts\hermes.exe"
$env:VIRTUAL_ENV = Join-Path $AgentDir "venv"
$env:UV_PROJECT_ENVIRONMENT = Join-Path $AgentDir "venv"
$env:UV_PYTHON_INSTALL_DIR = Join-Path $Root "uv-python"
$env:UV_CACHE_DIR = Join-Path $Root "cache\uv"
$env:NPM_CONFIG_PREFIX = Join-Path $Root "npm-global"
$env:NPM_CONFIG_CACHE = Join-Path $Root "cache\npm"
$env:NPM_CONFIG_REGISTRY = $Registry
$env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $Root "ms-playwright"
$env:Path = "$Root;$Root\node;$Root\npm-global;$Root\bin;$Root\git\cmd;$Root\git\bin;$Root\git\usr\bin;$Root\uv;$AgentDir\venv\Scripts;$env:Path"

Write-Host "Stopping Hermes..." -ForegroundColor Cyan
& (Join-Path $Root "hermes-stop.bat") --quiet | Out-Null

Write-Host "Upgrading Hermes Agent..." -ForegroundColor Cyan
$agentArgs = @($HermesScript, "update")
if ($Backup) { $agentArgs += "--backup" }
if ($ForceAgent) { $agentArgs += "--force" }
& $Python @agentArgs
if ($LASTEXITCODE -ne 0) { throw "Hermes Agent upgrade failed." }

Write-Host "Upgrading hermes-web-ui..." -ForegroundColor Cyan
& $Npm install -g "hermes-web-ui@latest" --registry $Registry --prefix "$Root\npm-global" --cache "$Root\cache\npm"
if ($LASTEXITCODE -ne 0) { throw "hermes-web-ui upgrade failed." }

Write-Host "Versions:" -ForegroundColor Cyan
& $Python $HermesScript --version
if (Test-Path $WebCli) { & $Node $WebCli -v }

Write-Host "Checking Hermes config..." -ForegroundColor Cyan
& $Python $HermesScript config check
if ($LASTEXITCODE -ne 0) {
  Write-Warning "config check reported issues. You may need: $Root\hermes.cmd config migrate"
}

if ($Restart) {
  Write-Host "Restarting Hermes..." -ForegroundColor Cyan
  & (Join-Path $Root "hermes-run.bat")
} else {
  Write-Host "Upgrade done. Start with: $Root\hermes-run.bat" -ForegroundColor Green
}
'@ | Set-Content "$Root\hermes-upgrade.ps1" -Encoding UTF8

@'
param(
  [string]$Root = (Split-Path -Parent $PSCommandPath),
  [string]$ZipPath = "C:\hermes.zip"
)
$ErrorActionPreference = "Stop"
$Root = [IO.Path]::GetFullPath($Root).TrimEnd("\")
cmd /c "`"$Root\hermes-stop.bat`" --quiet" | Out-Null
Set-Content -Path "$Root\install-root.txt" -Value $Root -Encoding ASCII

if (Test-Path $ZipPath) { Remove-Item -Force $ZipPath }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
  Get-ChildItem -LiteralPath $Root -Recurse -Force -File | ForEach-Object {
    $full = $_.FullName
    if ($full -like "$Root\tmp\*" -or $full -like "$Root\cache\npm\*" -or $full -like "$Root\cache\uv\*" -or $full -like "$Root\logs\*") { return }
    if (([IO.Path]::GetFullPath($ZipPath)) -eq $full) { return }
    $rel = $full.Substring($Root.Length).TrimStart("\") -replace "\\","/"
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $full, $rel, [System.IO.Compression.CompressionLevel]::Optimal) | Out-Null
  }
}
finally { $zip.Dispose() }
Write-Host "Created $ZipPath"
'@ | Set-Content "$Root\hermes-pack.ps1" -Encoding UTF8

@'
param(
  [string]$Root = (Split-Path -Parent $PSCommandPath),
  [string]$OldRoot = ""
)
$ErrorActionPreference = "Stop"
$Root = [IO.Path]::GetFullPath($Root).TrimEnd("\")
if (-not $OldRoot) {
  $marker = Join-Path $Root "install-root.txt"
  $OldRoot = if (Test-Path $marker) { (Get-Content $marker -Raw).Trim() } else { "C:\hermes" }
}
$OldRoot = [IO.Path]::GetFullPath($OldRoot).TrimEnd("\")

function Replace-TextPath($file) {
  $exts = @(".cmd",".bat",".ps1",".psm1",".py",".pth",".cfg",".ini",".json",".yaml",".yml",".toml",".txt")
  $names = @(".env","install-root.txt")
  if (($exts -notcontains $file.Extension.ToLowerInvariant()) -and ($names -notcontains $file.Name.ToLowerInvariant())) { return }
  try {
    $s = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
    $n = $s.Replace($OldRoot, $Root)
    if ($n -ne $s) { Set-Content -LiteralPath $file.FullName -Value $n -Encoding UTF8 }
  } catch {}
}

function Replace-BytesSameLength($path, [byte[]]$old, [byte[]]$new) {
  if ($old.Length -ne $new.Length) { return }
  $bytes = [IO.File]::ReadAllBytes($path)
  $changed = $false
  for ($i = 0; $i -le $bytes.Length - $old.Length; $i++) {
    $ok = $true
    for ($j = 0; $j -lt $old.Length; $j++) {
      if ($bytes[$i + $j] -ne $old[$j]) { $ok = $false; break }
    }
    if ($ok) {
      [Array]::Copy($new, 0, $bytes, $i, $new.Length)
      $changed = $true
      $i += $old.Length - 1
    }
  }
  if ($changed) { [IO.File]::WriteAllBytes($path, $bytes) }
}

Write-Host "Relocating Hermes: $OldRoot -> $Root"
Get-ChildItem -LiteralPath $Root -Recurse -Force -File | ForEach-Object { Replace-TextPath $_ }

if ($OldRoot.Length -eq $Root.Length) {
  $oldBytes = [Text.Encoding]::UTF8.GetBytes($OldRoot)
  $newBytes = [Text.Encoding]::UTF8.GetBytes($Root)
  Get-ChildItem "$Root\hermes-agent\venv\Scripts" -Filter *.exe -ErrorAction SilentlyContinue | ForEach-Object {
    Replace-BytesSameLength $_.FullName $oldBytes $newBytes
  }
} else {
  Write-Warning "目标路径长度和原路径不同，venv\Scripts\*.exe 无法二进制原位改写。建议使用 X:\hermes 这种同长度路径。"
}

Set-Content -Path "$Root\install-root.txt" -Value $Root -Encoding ASCII
Write-Host "Relocate done. Open a new terminal or run hermes-run.bat directly."
'@ | Set-Content "$Root\hermes-relocate.ps1" -Encoding UTF8
}

Info "Installing portable dependencies under $Root"
Install-Node24
Install-Uv
Install-HermesPython
Install-PortableGit
Install-Ripgrep
Install-Ffmpeg
Write-HelperFiles

Add-UserPathEntries @(
  $Root, "$Root\node", "$Root\npm-global", "$Root\bin",
  "$Root\git\cmd", "$Root\git\bin", "$Root\git\usr\bin",
  "$Root\uv", "$AgentDir\venv\Scripts"
)

[Environment]::SetEnvironmentVariable("HERMES_ROOT", $Root, "User")
[Environment]::SetEnvironmentVariable("HERMES_HOME", $Root, "User")
[Environment]::SetEnvironmentVariable("HERMES_WEB_UI_HOME", "$Root\hermes-web-ui-home", "User")
[Environment]::SetEnvironmentVariable("PLAYWRIGHT_BROWSERS_PATH", "$Root\ms-playwright", "User")
[Environment]::SetEnvironmentVariable("HERMES_GIT_BASH_PATH", "$Root\git\bin\bash.exe", "User")
[Environment]::SetEnvironmentVariable("HERMES_BIN", "$AgentDir\venv\Scripts\hermes.exe", "User")
[Environment]::SetEnvironmentVariable("NPM_CONFIG_REGISTRY", $NpmRegistry, "User")
[Environment]::SetEnvironmentVariable("UV_DEFAULT_INDEX", $PypiIndex, "User")
[Environment]::SetEnvironmentVariable("UV_INDEX_URL", $PypiIndex, "User")
[Environment]::SetEnvironmentVariable("PIP_INDEX_URL", $PypiIndex, "User")
[Environment]::SetEnvironmentVariable("UV_PYTHON_INSTALL_DIR", "$Root\uv-python", "User")
[Environment]::SetEnvironmentVariable("UV_PYTHON_CACHE_DIR", "$Root\cache\uv\python", "User")
[Environment]::SetEnvironmentVariable("UV_PYTHON_PREFERENCE", "only-managed", "User")
[Environment]::SetEnvironmentVariable("UV_MANAGED_PYTHON", $null, "User")
[Environment]::SetEnvironmentVariable("UV_PYTHON_NO_REGISTRY", "1", "User")
[Environment]::SetEnvironmentVariable("UV_PYTHON_INSTALL_MIRROR", (Use-GithubProxy "https://github.com/astral-sh/python-build-standalone/releases/download"), "User")

Set-HermesSessionEnv

Info "Configuring npm registry"
& "$Root\node\npm.cmd" config set registry $NpmRegistry --global
& "$Root\node\npm.cmd" config set prefix "$Root\npm-global" --global
& "$Root\node\npm.cmd" config set cache "$Root\cache\npm" --global

Info "Installing Hermes Agent"
$installer = "$Root\tmp\install-hermes-agent.ps1"
Download @(
  (Use-GithubProxy "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1"),
  "https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.ps1"
) $installer
Patch-HermesAgentInstaller $installer

powershell -NoProfile -ExecutionPolicy Bypass -File $installer `
  -HermesHome $Root `
  -InstallDir $AgentDir `
  -Branch $HermesBranch `
  -SkipSetup `
  -NonInteractive
if ($LASTEXITCODE -ne 0) { throw "Hermes Agent installer failed" }

Info "Installing hermes-web-ui"
$npm = "$Root\node\npm.cmd"
$spec = if ($WebUiVersion -eq "latest") { "hermes-web-ui@latest" } else { "hermes-web-ui@$WebUiVersion" }
& $npm install -g --registry $NpmRegistry --prefix "$Root\npm-global" --cache "$Root\cache\npm" $spec
if ($LASTEXITCODE -ne 0) { throw "npm install hermes-web-ui failed" }

Write-HelperFiles

Info "Verifying"
& "$Root\node\node.exe" -v
& "$Root\uv\uv.exe" --version
& "$AgentDir\venv\Scripts\python.exe" "$AgentDir\hermes" --version
& "$Root\node\node.exe" "$Root\npm-global\node_modules\hermes-web-ui\bin\hermes-web-ui.mjs" -v

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "1) Configure: $Root\hermes.cmd setup"
Write-Host "2) Run      : $Root\hermes-run.bat"
Write-Host "3) Stop     : $Root\hermes-stop.bat"
Write-Host "4) Package  : powershell -ExecutionPolicy Bypass -File $Root\hermes-pack.ps1 -ZipPath C:\hermes.zip"
Write-Host "5) Upgrade  : $Root\hermes-upgrade.bat -Restart"
