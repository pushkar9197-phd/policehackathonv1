<#
.SYNOPSIS
    Chandigarh Police Cyber Crime Investigation Platform (PS3-DWID)
    Windows & NVIDIA CUDA Whisper ASR Environment Setup & Diagnostic Tool
.DESCRIPTION
    Verifies and configures:
    1. NVIDIA GPU & CUDA capability via nvidia-smi.
    2. Whisper executable (tools\whisper\whisper-cli.exe with AVX2/AVX512/CUDA).
    3. FFmpeg and FFprobe binaries for WhatsApp (.opus / .ogg) normalization.
    4. Whisper GGML models (models\whisper\ggml-base.bin).
    5. Python virtual environment & optional faster-whisper CUDA fallback.
#>

[CmdletBinding()]
param(
    [switch]$DownloadModels,
    [switch]$TestAudio
)

Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host "   CHANDIGARH POLICE CYBER CRIME INVESTIGATION PLATFORM (PS3-DWID)" -ForegroundColor Cyan
Write-Host "   Windows Whisper ASR & GPU Hardware Acceleration Diagnostic" -ForegroundColor DarkCyan
Write-Host "=================================================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } elseif ($MyInvocation.MyCommand.Path) { Split-Path -Parent $MyInvocation.MyCommand.Path } else { (Get-Location).Path }
Set-Location $ScriptDir

# 1. Check NVIDIA GPU & CUDA
Write-Host "[1/5] Probing Hardware Acceleration (NVIDIA GPU / CUDA)..." -ForegroundColor Yellow
$NvidiaFound = $false
$GpuName = "None"
$GpuVram = "0 MB"

if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
    try {
        $gpuQuery = & nvidia-smi --query-gpu=name,memory.total --format=csv,noheader,nounits 2>&1
        if ($LASTEXITCODE -eq 0 -and $gpuQuery) {
            $parts = $gpuQuery[0] -split ","
            $GpuName = $parts[0].Trim()
            $GpuVram = "$($parts[1].Trim()) MB"
            $NvidiaFound = $true
            Write-Host "   [OK] Dedicated NVIDIA GPU Detected: $GpuName ($GpuVram VRAM)" -ForegroundColor Green
            Write-Host "      CUDA acceleration will enable ultra-fast transcription on larger models." -ForegroundColor DarkGray
        }
    } catch {}
}

if (-not $NvidiaFound) {
    Write-Host "   [INFO] No NVIDIA GPU detected via nvidia-smi." -ForegroundColor DarkYellow
    Write-Host "      Whisper will operate using multi-threaded CPU mode (AVX2/AVX512)." -ForegroundColor DarkGray
}

# 2. Check FFmpeg / FFprobe
Write-Host "`n[2/5] Checking FFmpeg and FFprobe (Required for Opus/OGG WhatsApp Audio)..." -ForegroundColor Yellow
$FfmpegBin = $null
$FfmpegCandidates = @(
    "$ScriptDir\tools\ffmpeg\bin\ffmpeg.exe",
    "$ScriptDir\tools\ffmpeg\ffmpeg.exe",
    "C:\ffmpeg\bin\ffmpeg.exe",
    "C:\Program Files\ffmpeg\bin\ffmpeg.exe",
    "$env:LOCALAPPDATA\Programs\ffmpeg\bin\ffmpeg.exe"
)
foreach ($c in $FfmpegCandidates) {
    if (Test-Path $c) { $FfmpegBin = $c; break }
}
if (-not $FfmpegBin -and (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    $FfmpegBin = (Get-Command ffmpeg).Source
}

if ($FfmpegBin) {
    Write-Host "   [OK] FFmpeg found: $FfmpegBin" -ForegroundColor Green
} else {
    Write-Host "   [WARN] FFmpeg is NOT found in PATH or standard locations." -ForegroundColor Red
    Write-Host "      Run: winget install Gyan.FFmpeg.Essentials" -ForegroundColor DarkGray
}

# 3. Check Whisper Executable
Write-Host "`n[3/5] Checking Whisper CLI Executable..." -ForegroundColor Yellow
$WhisperBin = $null
$WhisperCandidates = @(
    "$ScriptDir\tools\whisper\whisper-cli.exe",
    "$ScriptDir\tools\whisper\whisper.exe",
    "C:\whisper-cpp\whisper-cli.exe",
    "C:\whisper-cpp\whisper.exe",
    "C:\whisper\whisper-cli.exe",
    "C:\whisper\whisper.exe",
    "$env:LOCALAPPDATA\Programs\whisper\whisper-cli.exe"
)
foreach ($wc in $WhisperCandidates) {
    if (Test-Path $wc) { $WhisperBin = $wc; break }
}
if (-not $WhisperBin) {
    if (Get-Command whisper-cli -ErrorAction SilentlyContinue) { $WhisperBin = (Get-Command whisper-cli).Source }
    elseif (Get-Command whisper-cpp -ErrorAction SilentlyContinue) { $WhisperBin = (Get-Command whisper-cpp).Source }
}

if ($WhisperBin) {
    Write-Host "   [OK] Whisper executable found: $WhisperBin" -ForegroundColor Green
} else {
    Write-Host "   [WARN] Standalone whisper-cli.exe not found." -ForegroundColor DarkYellow
    Write-Host "      Download from https://github.com/ggml-org/whisper.cpp/releases and extract to tools\whisper" -ForegroundColor DarkGray
}

# 4. Check Models in models/whisper/
Write-Host "`n[4/5] Checking Local Offline Whisper Models..." -ForegroundColor Yellow
$ModelDir = "$ScriptDir\models\whisper"
if (-not (Test-Path $ModelDir)) {
    New-Item -ItemType Directory -Path $ModelDir -Force | Out-Null
}

$AvailableModels = @()
$CheckTiers = @(
    @{ Name = "ggml-medium.bin"; Tier = "MEDIUM"; ExpectedSizeMB = 1530 },
    @{ Name = "ggml-small.bin";  Tier = "SMALL";  ExpectedSizeMB = 487 },
    @{ Name = "ggml-base.bin";   Tier = "BASE";   ExpectedSizeMB = 148 }
)

foreach ($item in $CheckTiers) {
    $p = "$ModelDir\$($item.Name)"
    if (Test-Path $p) {
        $sizeMB = [math]::Round((Get-Item $p).Length / 1MB, 1)
        Write-Host "   [OK] [$($item.Tier)] $($item.Name) ($sizeMB MB) is ready." -ForegroundColor Green
        $AvailableModels += $item
    } else {
        Write-Host "   [--] [$($item.Tier)] $($item.Name) is not downloaded." -ForegroundColor DarkGray
    }
}

if ($AvailableModels.Count -eq 0) {
    Write-Host "   [WARN] No GGML models found in $ModelDir." -ForegroundColor Yellow
} else {
    $activeModel = $AvailableModels[0]
    Write-Host "   [TARGET] Active Selected Model: $($activeModel.Tier) ($($activeModel.Name))" -ForegroundColor Cyan
}

# 5. Check Python Fallback Packages
Write-Host "`n[5/5] Checking Python ASR Capabilities..." -ForegroundColor Yellow
$py = if (Test-Path "$ScriptDir\.venv\Scripts\python.exe") { "$ScriptDir\.venv\Scripts\python.exe" } else { "python" }

$audioWorkerCheck = & $py -c "import audio_worker; print(audio_worker.get_whisper_binary() is not None)" 2>$null
if ($audioWorkerCheck -match "True") {
    Write-Host "   [OK] audio_worker module: Whisper binary and model detected and bound!" -ForegroundColor Green
} else {
    Write-Host "   [INFO] audio_worker module: Operating with forensic fallback normalizer." -ForegroundColor DarkCyan
}

Write-Host ""
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "DIAGNOSTIC SUMMARY" -ForegroundColor Green
Write-Host "   * NVIDIA GPU:        $(if ($NvidiaFound) {"$GpuName ($GpuVram)"} else {'None (CPU Mode)'})" -ForegroundColor $(if ($NvidiaFound) {'Green'} else {'DarkYellow'})
Write-Host "   * Whisper Binary:    $(if ($WhisperBin) {$WhisperBin} else {'Missing'})" -ForegroundColor $(if ($WhisperBin) {'Green'} else {'DarkYellow'})
Write-Host "   * FFmpeg Normalizer: $(if ($FfmpegBin) {$FfmpegBin} else {'Missing'})" -ForegroundColor $(if ($FfmpegBin) {'Green'} else {'Red'})
Write-Host "   * Active Model:      $(if ($AvailableModels.Count -gt 0) {"$($AvailableModels[0].Tier) ($($AvailableModels[0].Name))"} else {'None'})" -ForegroundColor $(if ($AvailableModels.Count -gt 0) {'Green'} else {'Red'})
Write-Host "=================================================================" -ForegroundColor Green
Write-Host "Ready to launch: .\start.ps1`n" -ForegroundColor Cyan
