<#
.SYNOPSIS
    Chandigarh Police Cyber Crime Investigation Platform (PS3-DWID)
    Air-Gapped Windows / PowerShell Startup & Dependency Verification Script
.DESCRIPTION
    Checks Python 3 (bypassing Windows Store aliases), SQLite3, Tesseract OCR,
    and probes offline model servers running on localhost:8012 (LiquidAI SLM)
    and localhost:8015 (dots.ocr VLM), then launches the Forensic Web Platform
    on port 8000.
#>

[CmdletBinding()]
param(
    [int]$LiquidPort = 8012,
    [int]$DotsPort = 8015,
    [int]$WebPort = 8000,
    [switch]$NoBrowser,
    [switch]$SkipCheck,
    [switch]$ForceRestart
)

$ErrorActionPreference = "Continue"

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "   CHANDIGARH POLICE CYBER CRIME INVESTIGATION PLATFORM (PS3-DWID)" -ForegroundColor Cyan
Write-Host "   Section 63(4) BSA Compliant Forensic Triage & Offline SLM" -ForegroundColor DarkCyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
Set-Location $ScriptDir

# Ensure logs directory exists
if (-not (Test-Path "logs")) {
    New-Item -ItemType Directory -Path "logs" | Out-Null
}

$AllDepsMet = $true

# Force UTF-8 environment for Python child processes on Windows
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"

# -----------------------------------------------------------------------------
# 1. Dependency Check: Python (Find Real Python, Skip Windows Store Stubs)
# -----------------------------------------------------------------------------
Write-Host "[1/4] Checking Python Environment..." -ForegroundColor Yellow

function Get-ValidPython {
    # 1. Local virtual environments
    $venvPaths = @(
        "$ScriptDir\.venv\Scripts\python.exe",
        "$ScriptDir\venv\Scripts\python.exe"
    )
    foreach ($vp in $venvPaths) {
        if (Test-Path $vp) { return $vp }
    }

    # 2. Check where.exe to filter out WindowsApps stubs
    $wherePy = where.exe python 2>$null
    if ($wherePy) {
        foreach ($line in ($wherePy -split "`r?`n")) {
            $trimmed = $line.Trim()
            if ($trimmed -and (Test-Path $trimmed) -and ($trimmed -notmatch "WindowsApps")) {
                return $trimmed
            }
        }
    }

    # 3. Known standard Windows installation paths
    $commonPaths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python*\python.exe",
        "$env:LOCALAPPDATA\Python\pythoncore-*\python.exe",
        "$env:LOCALAPPDATA\Python\bin\python.exe",
        "C:\Program Files\Python*\python.exe",
        "C:\Program Files (x86)\Python*\python.exe",
        "C:\Python*\python.exe"
    )
    foreach ($cp in $commonPaths) {
        $found = Get-Item $cp -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found -and (Test-Path $found.FullName)) {
            return $found.FullName
        }
    }

    # 4. Try py.exe launcher if not WindowsApps
    $pyCmd = Get-Command py.exe -ErrorAction SilentlyContinue
    if ($pyCmd -and $pyCmd.Source -notmatch "WindowsApps") {
        return $pyCmd.Source
    }

    # 5. Fallback to Get-Command python
    $cmd = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

$PythonBin = Get-ValidPython
$PythonArgs = @()

if (-not $PythonBin) {
    Write-Host "   [FAIL] CRITICAL: Python 3 was not found in PATH or virtual environments!" -ForegroundColor Red
    Write-Host "      Please install Python 3.9+ from https://www.python.org/downloads/ (check 'Add Python to PATH')" -ForegroundColor Red
    $AllDepsMet = $false
} else {
    try {
        $pyVer = & $PythonBin --version 2>&1
        Write-Host "   [OK] Detected: $pyVer ($PythonBin)" -ForegroundColor Green

        # Verify SQLite3 availability
        $sqlCheck = & $PythonBin -c "import sqlite3; print(1)" 2>&1
        if ($sqlCheck -match "1") {
            Write-Host "   [OK] SQLite3 module: Available & Functional" -ForegroundColor Green
        } else {
            Write-Host "   [WARN] SQLite3 module verification warning: $sqlCheck" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "   [FAIL] Failed to execute Python: $_" -ForegroundColor Red
        $AllDepsMet = $false
    }
}

# -----------------------------------------------------------------------------
# 2. Dependency Check: Tesseract OCR
# -----------------------------------------------------------------------------
Write-Host "`n[2/4] Checking Tesseract OCR Engine..." -ForegroundColor Yellow

$Candidates = @(
    "$ScriptDir\tools\tesseract\tesseract.exe",
    "$ScriptDir\tesseract\tesseract.exe",
    "$env:LOCALAPPDATA\Programs\Tesseract-OCR\tesseract.exe",
    "C:\Program Files\Tesseract-OCR\tesseract.exe",
    "C:\Program Files (x86)\Tesseract-OCR\tesseract.exe",
    "$env:USERPROFILE\scoop\apps\tesseract\current\tesseract.exe",
    "C:\ProgramData\chocolatey\bin\tesseract.exe"
)

$TesseractBin = $null
foreach ($c in $Candidates) {
    if (Test-Path $c) {
        $TesseractBin = $c
        break
    }
}

if (-not $TesseractBin) {
    $whichTess = Get-Command tesseract, tesseract.exe -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($whichTess) {
        $TesseractBin = $whichTess.Source
    }
}

if ($TesseractBin) {
    $tDir = Split-Path -Parent $TesseractBin
    if ($env:PATH -notmatch [regex]::Escape($tDir)) {
        $env:PATH = "$tDir;$env:PATH"
    }
    $tessdataDir = Join-Path $tDir "tessdata"
    if (Test-Path $tessdataDir) {
        $env:TESSDATA_PREFIX = $tessdataDir
    }

    try {
        $tVer = (& $TesseractBin --version 2>&1)[0]
        Write-Host "   [OK] Detected: $tVer" -ForegroundColor Green
        Write-Host "   [OK] Binary Location: $TesseractBin" -ForegroundColor Green
    } catch {
        Write-Host "   [OK] Tesseract found at $TesseractBin" -ForegroundColor Green
    }
} else {
    Write-Host "   [WARN] Tesseract binary not found in standard paths." -ForegroundColor Yellow
    Write-Host "      Tesseract installer: https://github.com/UB-Mannheim/tesseract/wiki" -ForegroundColor DarkGray
    Write-Host "      (System will still operate using plain text, CSV, and remote/dots.ocr)" -ForegroundColor DarkGray
}

# -----------------------------------------------------------------------------
# 3. Probe Offline Model Servers (Localhost 8012 & 8015)
# -----------------------------------------------------------------------------
Write-Host "`n[3/4] Probing Offline Neural Model Servers..." -ForegroundColor Yellow

function Test-ModelEndpoint {
    param([string]$Url, [string]$Label, [int]$Port)
    try {
        $resp = Invoke-RestMethod -Uri $Url -TimeoutSec 2 -ErrorAction Stop
        $modelId = "Active Model"
        if ($resp.data -and $resp.data.Count -gt 0 -and $resp.data[0].id) {
            $modelId = $resp.data[0].id
        } elseif ($resp.id) {
            $modelId = $resp.id
        }
        return @{ Online = $true; Model = $modelId; Error = $null }
    } catch {
        return @{ Online = $false; Model = $null; Error = $_.Exception.Message }
    }
}

# A. Probe LiquidAI SLM (Port 8012)
$liquidResult = Test-ModelEndpoint -Url "http://127.0.0.1:$LiquidPort/v1/models" -Label "LiquidAI" -Port $LiquidPort
if ($liquidResult.Online) {
    Write-Host "   [ONLINE] LiquidAI LFM2.5 SLM responding on port $LiquidPort (Model: $($liquidResult.Model))" -ForegroundColor Green
} else {
    Write-Host "   [STANDBY] LiquidAI server not detected on http://127.0.0.1:$LiquidPort" -ForegroundColor DarkYellow
    Write-Host "      Command to start LiquidAI: llama-server.exe -m <model.gguf> --port $LiquidPort -ngl 99 -c 4096" -ForegroundColor DarkGray
    Write-Host "      Platform will operate in fallback mode using deterministic pattern matching." -ForegroundColor DarkGray
}

# B. Probe dots.ocr VLM (Port 8015)
$dotsResult = Test-ModelEndpoint -Url "http://127.0.0.1:$DotsPort/v1/models" -Label "dots.ocr" -Port $DotsPort
if ($dotsResult.Online) {
    Write-Host "   [ONLINE] dots.ocr Multimodal VLM responding on port $DotsPort (Model: $($dotsResult.Model))" -ForegroundColor Green
} else {
    Write-Host "   [STANDBY] dots.ocr server not active on http://127.0.0.1:$DotsPort" -ForegroundColor DarkCyan
    Write-Host "      Command to start dots.ocr: llama-server.exe -m <dots.gguf> --mmproj <mmproj.gguf> --port $DotsPort" -ForegroundColor DarkGray
    Write-Host "      OCR worker will automatically use Tesseract or native CLI engine." -ForegroundColor DarkGray
}

# -----------------------------------------------------------------------------
# 4. Launch Forensic Web Application (Port 8000)
# -----------------------------------------------------------------------------
Write-Host "`n[4/4] Starting Forensic Web Workbench..." -ForegroundColor Yellow

if (-not $PythonBin) {
    Write-Host "   [FAIL] Cannot start server: Python is missing. Aborting." -ForegroundColor Red
    exit 1
}

# Test if an existing server is active and healthy
$isAlreadyHealthy = $false
try {
    $healthResp = Invoke-RestMethod -Uri "http://127.0.0.1:$WebPort/api/health" -TimeoutSec 2 -ErrorAction Stop
    if ($healthResp.status -eq "online") {
        $isAlreadyHealthy = $true
    }
} catch {
    $isAlreadyHealthy = $false
}

# Clean up any dead, stale or lingering processes on port 8000 if not healthy or ForceRestart
if ((-not $isAlreadyHealthy) -or $ForceRestart) {
    try {
        $staleConns = Get-NetTCPConnection -LocalPort $WebPort -ErrorAction SilentlyContinue | Where-Object { $_.State -eq 'Listen' }
        foreach ($conn in $staleConns) {
            if ($conn.OwningProcess -and $conn.OwningProcess -gt 4) {
                Write-Host "   [CLEANUP] Terminating stale process on port $WebPort (PID: $($conn.OwningProcess))..." -ForegroundColor Yellow
                Stop-Process -Id $conn.OwningProcess -Force -ErrorAction SilentlyContinue
            }
        }
        Start-Sleep -Milliseconds 600
    } catch {
        # Ignore cleanup errors if port was already free
    }
    $isAlreadyHealthy = $false
}

$ServerProcess = $null

if ($isAlreadyHealthy) {
    Write-Host "   [OK] Forensic Web Server is already active and healthy on http://localhost:$WebPort" -ForegroundColor Green
} else {
    Write-Host "   [INIT] Starting server.py on http://127.0.0.1:$WebPort..." -ForegroundColor Cyan

    $stdoutPath = Join-Path $ScriptDir "logs\web_server.log"
    $stderrPath = Join-Path $ScriptDir "logs\web_server_err.log"
    $logHeader = "`n=== Server started at $(Get-Date) ==="
    Add-Content -Path $stdoutPath -Value $logHeader
    Add-Content -Path $stderrPath -Value $logHeader

    $serverArgs = @("-u", "server.py")

    $ServerProcess = Start-Process -FilePath $PythonBin `
        -ArgumentList $serverArgs `
        -WorkingDirectory $ScriptDir `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru `
        -NoNewWindow

    if (-not $ServerProcess) {
        Write-Host "   [FAIL] Failed to spawn server process." -ForegroundColor Red
        exit 1
    }

    Write-Host "   [OK] Web Server process spawned (PID: $($ServerProcess.Id)) -> logs\web_server.log" -ForegroundColor Green

    # Wait up to 15s for readiness via /api/health
    Write-Host "   Waiting for service readiness..." -NoNewline
    $ready = $false
    for ($i = 0; $i -lt 25; $i++) {
        Start-Sleep -Milliseconds 600
        try {
            $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$WebPort/api/health" -TimeoutSec 1 -ErrorAction Stop
            if ($resp.status -eq "online") {
                $ready = $true
                break
            }
        } catch {
            Write-Host "." -NoNewline
        }
    }
    Write-Host ""

    if ($ready) {
        Write-Host "   [ONLINE] Forensic Server is online and responsive!" -ForegroundColor Green
    } else {
        Write-Host "   [NOTICE] Server launched. FTS5 index initialization may complete shortly." -ForegroundColor DarkYellow
    }
}

# Auto-launch browser
$WebUrl = "http://localhost:$WebPort"
if (-not $NoBrowser) {
    Write-Host "`nOpening $WebUrl in default browser..." -ForegroundColor Cyan
    Start-Process $WebUrl
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "CHANDIGARH POLICE FORENSIC BENCHMARK OPERATIONAL" -ForegroundColor Green
Write-Host "   • Web Dashboard:     $WebUrl" -ForegroundColor White

$liquidLabel = if ($liquidResult.Online) { "[ONLINE]" } else { "[OFFLINE]" }
$liquidColor = if ($liquidResult.Online) { "Green" } else { "DarkYellow" }
Write-Host "   • LiquidAI (SLM):    http://localhost:$LiquidPort $liquidLabel" -ForegroundColor $liquidColor

$dotsLabel = if ($dotsResult.Online) { "[ONLINE]" } else { "[STANDBY]" }
$dotsColor = if ($dotsResult.Online) { "Green" } else { "DarkCyan" }
Write-Host "   • dots.ocr (VLM):    http://localhost:$DotsPort $dotsLabel" -ForegroundColor $dotsColor

Write-Host "   • Logs:              Get-Content logs\web_server.log -Wait" -ForegroundColor DarkGray
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "Press Ctrl+C to terminate the forensic server process.`n" -ForegroundColor Yellow

# Clean shutdown handler
try {
    while ($true) {
        if ($ServerProcess -and $ServerProcess.HasExited) {
            Write-Host "`n[NOTICE] Server process terminated with exit code $($ServerProcess.ExitCode)." -ForegroundColor Red
            if (Test-Path "logs\web_server_err.log") {
                Get-Content "logs\web_server_err.log" -Tail 10 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkRed }
            }
            break
        }
        Start-Sleep -Seconds 1
    }
} finally {
    if ($ServerProcess -and (-not $ServerProcess.HasExited)) {
        Write-Host "`nStopping forensic web server (PID: $($ServerProcess.Id))..." -ForegroundColor Yellow
        Stop-Process -Id $ServerProcess.Id -Force -ErrorAction SilentlyContinue
        Write-Host "Server stopped cleanly." -ForegroundColor Green
    }
}
