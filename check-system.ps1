# OIG System Requirements Check
# Run in PowerShell: .\check-system.ps1
# Or paste directly into a PowerShell window

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OIG System Requirements Check" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$allPass = $true

# ── CPU ──────────────────────────────────────────────────────────────
$cpu = (Get-CimInstance Win32_Processor).Name
Write-Host "CPU: $cpu" -ForegroundColor White
Write-Host ""

# ── RAM ──────────────────────────────────────────────────────────────
$ramBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
$ramGB = [math]::Round($ramBytes / 1GB, 1)
$ramOk = $ramGB -ge 32
if (-not $ramOk) { $allPass = $false }
$ramStatus = if ($ramOk) { "PASS" } else { "FAIL - need 32GB minimum" }
$ramColor = if ($ramOk) { "Green" } else { "Red" }
Write-Host "RAM: ${ramGB} GB " -NoNewline -ForegroundColor White
Write-Host "[$ramStatus]" -ForegroundColor $ramColor
Write-Host ""

# ── Disk Space ───────────────────────────────────────────────────────
$drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Sort-Object -Property FreeSpace -Descending
$bestDrive = $drives | Select-Object -First 1
$bestFreeGB = [math]::Round($bestDrive.FreeSpace / 1GB, 1)
$bestTotalGB = [math]::Round($bestDrive.Size / 1GB, 1)
$diskOk = $bestFreeGB -ge 50
if (-not $diskOk) { $allPass = $false }
$diskStatus = if ($diskOk) { "PASS" } else { "FAIL - need 50GB free minimum" }
$diskColor = if ($diskOk) { "Green" } else { "Red" }

Write-Host "Disk Space:" -ForegroundColor White
foreach ($drive in $drives) {
    $freeGB = [math]::Round($drive.FreeSpace / 1GB, 1)
    $totalGB = [math]::Round($drive.Size / 1GB, 1)
    $usedGB = [math]::Round(($drive.Size - $drive.FreeSpace) / 1GB, 1)
    Write-Host "  $($drive.DeviceID) ${freeGB} GB free / ${totalGB} GB total" -ForegroundColor Gray
}
Write-Host "  Best drive: $($bestDrive.DeviceID) with ${bestFreeGB} GB free " -NoNewline -ForegroundColor White
Write-Host "[$diskStatus]" -ForegroundColor $diskColor
Write-Host ""

# ── GPU ──────────────────────────────────────────────────────────────
$gpuFound = $false
$gpuOk = $false
$vramOk = $false
$archOk = $false
$vramGB = 0
$archName = "Unknown"
$computeCap = ""

# Check for nvidia-smi
$nvsmi = $null
$nvsmiPaths = @(
    "nvidia-smi",
    "C:\Windows\System32\nvidia-smi.exe",
    "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe"
)
foreach ($path in $nvsmiPaths) {
    try {
        $testOutput = & $path "--query-gpu=name" "--format=csv,noheader" 2>$null
        if ($testOutput) {
            $nvsmi = $path
            break
        }
    } catch {}
}

if ($nvsmi) {
    $gpuFound = $true
    $gpuName = & $nvsmi "--query-gpu=name" "--format=csv,noheader" 2>$null
    $vramMB = & $nvsmi "--query-gpu=memory.total" "--format=csv,noheader,nounits" 2>$null
    $computeCap = (& $nvsmi "--query-gpu=compute_cap" "--format=csv,noheader" 2>$null).Trim()
    $driverVer = & $nvsmi "--query-gpu=driver_version" "--format=csv,noheader" 2>$null

    $vramGB = [math]::Round([int]$vramMB / 1024, 1)
    $vramOk = $vramGB -ge 8

    if ($computeCap) {
        $major = [int]($computeCap.Split('.')[0])
        $minor = [int]($computeCap.Split('.')[1])
        $archOk = $major -ge 8
        $archName = switch ($major) {
            7 { "Turing (RTX 20-series)" }
            8 { if ($minor -ge 9) { "Ada Lovelace (RTX 40-series)" } else { "Ampere (RTX 30-series)" } }
            9 { "Ada Lovelace (RTX 40-series)" }
            10 { "Blackwell (RTX 50-series)" }
            default { "Compute $computeCap" }
        }
    }
    $gpuOk = $vramOk -and $archOk

    Write-Host "GPU: $gpuName" -ForegroundColor White
    Write-Host "  Driver: $driverVer" -ForegroundColor Gray

    $vramStatus = if ($vramOk) { "PASS" } else { "FAIL - need 8GB minimum" }
    $vramColor = if ($vramOk) { "Green" } else { "Red" }
    Write-Host "  VRAM: ${vramGB} GB " -NoNewline -ForegroundColor White
    Write-Host "[$vramStatus]" -ForegroundColor $vramColor

    $archStatus = if ($archOk) { "PASS" } else { "FAIL - need RTX 30-series (Ampere) or newer" }
    $archColor = if ($archOk) { "Green" } else { "Red" }
    Write-Host "  Architecture: $archName ($computeCap) " -NoNewline -ForegroundColor White
    Write-Host "[$archStatus]" -ForegroundColor $archColor
} else {
    # Fallback to WMI
    $gpus = Get-CimInstance Win32_VideoController | Where-Object { $_.Name -match 'NVIDIA' }
    if ($gpus) {
        $gpuFound = $true
        foreach ($gpu in $gpus) {
            Write-Host "GPU: $($gpu.Name)" -ForegroundColor White
            Write-Host "  VRAM: Unable to determine (install NVIDIA drivers for accurate info)" -ForegroundColor Yellow
            Write-Host "  Architecture: Unable to determine" -ForegroundColor Yellow
        }
    }
}

if (-not $gpuFound) {
    $allPass = $false
    $allGpus = Get-CimInstance Win32_VideoController
    Write-Host "GPU: No NVIDIA GPU detected " -NoNewline -ForegroundColor White
    Write-Host "[FAIL]" -ForegroundColor Red
    Write-Host ""
    $nonNvidiaNames = ($allGpus | Select-Object -ExpandProperty Name) -join ', '
    # Get accurate VRAM via DirectX diagnostics
    $dxDiag = @{}
    try {
        & dxdiag /t $env:TEMP\dxdiag.txt 2>$null
        Start-Sleep -Seconds 5
        $dxLines = Get-Content "$env:TEMP\dxdiag.txt" -ErrorAction SilentlyContinue
        if ($dxLines) {
            $currentCard = $null
            foreach ($line in $dxLines) {
                if ($line -match "Card name:\s*(.+)") {
                    $currentCard = $Matches[1].Trim()
                }
                if ($currentCard -and $line -match "Dedicated Memory:\s*(\d+)\s*MB") {
                    $dxDiag[$currentCard] = [int]$Matches[1]
                    $currentCard = $null
                }
            }
        }
        Remove-Item "$env:TEMP\dxdiag.txt" -ErrorAction SilentlyContinue
    } catch {}

    Write-Host ""
    Write-Host "  GPUs found on this system:" -ForegroundColor Gray
    foreach ($g in $allGpus) {
        # Look up accurate VRAM from DirectX diagnostics
        $dxVram = $dxDiag[$g.Name]
        if (-not $dxVram) {
            # Fuzzy match if exact name doesn't match
            foreach ($key in $dxDiag.Keys) {
                if ($key -like "*$($g.Name)*" -or $g.Name -like "*$key*") {
                    $dxVram = $dxDiag[$key]; break
                }
            }
        }
        $vramStr = if ($dxVram) { "$([math]::Round($dxVram / 1024, 1)) GB" } else { "unknown" }
        Write-Host "    - $($g.Name) (VRAM: $vramStr)" -ForegroundColor Gray
        if ($g.Name -match 'AMD|Radeon') {
            Write-Host "      AMD GPUs are not currently supported. OIG requires an NVIDIA GPU." -ForegroundColor Yellow
        } elseif ($g.Name -match 'Intel|Arc|Iris|UHD') {
            Write-Host "      Intel GPUs are not currently supported. OIG requires an NVIDIA GPU." -ForegroundColor Yellow
            if ($g.Name -match 'Arc') {
                Write-Host "      Intel Arc support may be added in a future update." -ForegroundColor Yellow
            }
        } elseif ($g.Name -match 'Microsoft Basic|Standard VGA') {
            Write-Host "      This is a basic display driver, not a GPU." -ForegroundColor Yellow
        }
    }
    Write-Host ""
    Write-Host "  OIG requires an NVIDIA RTX 30-series (Ampere) or newer GPU." -ForegroundColor Yellow
    Write-Host "  Recommended: RTX 3060 12GB, RTX 4060 8GB, RTX 5060 8GB, or better." -ForegroundColor Yellow
} elseif (-not $gpuOk) {
    $allPass = $false
}

# ── Summary ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$items = @(
    @{ Name = "CPU"; Value = $cpu; Ok = $true; Note = "" },
    @{ Name = "RAM"; Value = "${ramGB} GB"; Ok = $ramOk; Note = if ($ramOk) { "" } else { "(minimum 32GB)" } },
    @{ Name = "Disk"; Value = "${bestFreeGB} GB free on $($bestDrive.DeviceID)"; Ok = $diskOk; Note = if ($diskOk) { "" } else { "(minimum 50GB free)" } },
    @{ Name = "GPU"; Value = if ($gpuFound) { "$gpuName" } else { "$nonNvidiaNames (no NVIDIA GPU)" }; Ok = $gpuFound -and $gpuOk; Note = "" },
    @{ Name = "VRAM"; Value = if ($gpuFound) { "${vramGB} GB" } else { "N/A - requires NVIDIA GPU" }; Ok = $vramOk; Note = if ($vramOk) { "" } else { "(minimum 8GB)" } },
    @{ Name = "Arch"; Value = if ($gpuFound) { "$archName" } else { "N/A - requires NVIDIA GPU" }; Ok = $archOk; Note = if ($archOk) { "" } else { "(need RTX 30-series+)" } }
)

foreach ($item in $items) {
    $icon = if ($item.Ok) { "[PASS]" } else { "[FAIL]" }
    $color = if ($item.Ok) { "Green" } else { "Red" }
    $line = "  $($item.Name.PadRight(6)) $($item.Value)"
    if ($item.Note) { $line += " $($item.Note)" }
    Write-Host "$line " -NoNewline -ForegroundColor White
    Write-Host $icon -ForegroundColor $color
}

Write-Host ""
if ($allPass) {
    Write-Host "  Your system meets all requirements for OIG!" -ForegroundColor Green
    if ($vramGB -ge 12) {
        Write-Host "  With ${vramGB}GB VRAM, you can run all features including video generation." -ForegroundColor Green
    } else {
        Write-Host "  With ${vramGB}GB VRAM, image generation will work great." -ForegroundColor Green
        Write-Host "  Video generation requires 32GB+ VRAM (cloud GPU recommended)." -ForegroundColor Yellow
    }
} else {
    Write-Host "  Your system does not meet all requirements." -ForegroundColor Red
    Write-Host "  See the items marked [FAIL] above for details." -ForegroundColor Red
}
Write-Host ""
