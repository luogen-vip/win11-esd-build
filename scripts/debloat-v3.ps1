param(
    [Parameter(Mandatory = $true)][string]$WimPath,
    [string]$MountDir = "D:\mount3",
    [string]$LogFile  = "D:\debloat3.log"
)

$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"

function Log {
    param([string]$msg)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

Set-Content -Path $LogFile -Value ("LuoLite MAX debloat start " + (Get-Date)) -Encoding UTF8

# ============================ step 1: run the standard debloat first
Log "== phase 1: base debloat (debloat-v2) =="
& "$PSScriptRoot\debloat-v2.ps1" -WimPath $WimPath -MountDir "D:\mount" -LogFile "D:\debloat2.log"
Log "phase 1 finished"

# ============================ step 2: extra aggressive pass
if (Test-Path $MountDir) {
    dism /Unmount-Image /MountDir:"$MountDir" /Discard | Out-Null
    Remove-Item -Recurse -Force $MountDir -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $MountDir | Out-Null
Log "mounting for phase 2"
dism /Mount-Image /ImageFile:"$WimPath" /Index:1 /MountDir:"$MountDir" /Quiet
if ($LASTEXITCODE -ne 0) { throw "mount failed $LASTEXITCODE" }

# ---- kill WinRE (saves ~400-500MB)
$winre = Join-Path $MountDir "Windows\System32\Recovery\winre.wim"
if (Test-Path $winre) {
    $sz = [math]::Round((Get-Item $winre).Length/1MB,1)
    Remove-Item -Force $winre -ErrorAction SilentlyContinue
    Log ("removed winre.wim ({0} MB)" -f $sz)
} else { Log "winre.wim not present" }
$reagent = Join-Path $MountDir "Windows\System32\Recovery\ReAgent.xml"
if (Test-Path $reagent) { Remove-Item -Force $reagent -ErrorAction SilentlyContinue; Log "removed ReAgent.xml" }
# 系统属性里的“重置此电脑”入口失效，但不会报错

# ---- reserved storage OFF
$sysReg  = Join-Path $MountDir "Windows\System32\config\SYSTEM"
$softReg = Join-Path $MountDir "Windows\System32\config\SOFTWARE"
reg load HKLM\OFSYS3 $sysReg  | Out-Null
reg load HKLM\OFSW3  $softReg | Out-Null
try {
    New-Item -Path "HKLM:\OFSW3\Microsoft\Windows\CurrentVersion\ReserveManager" -Force | Out-Null
    New-ItemProperty -Path "HKLM:\OFSW3\Microsoft\Windows\CurrentVersion\ReserveManager" -Name ShippedWithReserves -Value 0 -PropertyType DWord -Force | Out-Null
    Log "reserved storage disabled"
} catch { Log "  [WARN] reserved storage key" }
# 关闭“快速启动/休眠”等残留
try {
    New-ItemProperty -Path "HKLM:\OFSYS3\ControlSet001\Control\Session Manager\Power" -Name HibernateEnabled -Value 0 -PropertyType DWord -Force | Out-Null
} catch {}
[gc]::Collect()
reg unload HKLM\OFSYS3 | Out-Null
reg unload HKLM\OFSW3  | Out-Null

# ---- delete printer driver store folders (file level, DISM refuses)
$drvStore = Join-Path $MountDir "Windows\System32\DriverStore\FileRepository"
if (Test-Path $drvStore) {
    Get-ChildItem -Path $drvStore -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "prn*" -or $_.Name -like "ntprint*" } |
        ForEach-Object {
            try { Remove-Item -Recurse -Force $_.FullName -ErrorAction Stop; Log ("  del " + $_.Name) } catch { }
        }
}

# ---- remove speech / narrator payloads (no speech features needed)
foreach ($p in @("Windows\Speech","Windows\Speech_OneCore")) {
    $full = Join-Path $MountDir $p
    if (Test-Path $full) {
        try {
            $mb = [math]::Round(((Get-ChildItem $full -Recurse -File | Measure-Object Length -Sum).Sum)/1MB,1)
            Remove-Item -Recurse -Force $full -ErrorAction Stop
            Log ("removed " + $p + " (" + $mb + " MB)")
        } catch { Log ("  [WARN] cannot remove " + $p) }
    }
}

# ---- drop leftover locale/cache blobs
foreach ($p in @("Windows\System32\LogFiles","Windows\Temp","Users\Default\AppData\Local\Temp")) {
    $full = Join-Path $MountDir $p
    if (Test-Path $full) {
        Get-ChildItem -Path $full -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Log ("cleaned " + $p)
    }
}

# ---- component cleanup again after file deletions
Log "== ResetBase (phase 2) =="
dism /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet | Out-Null
Log ("  exit " + $LASTEXITCODE)

Log "unmount commit (phase 2)"
dism /Unmount-Image /MountDir:"$MountDir" /Commit /Quiet
if ($LASTEXITCODE -ne 0) { throw "commit failed $LASTEXITCODE" }
Log "DONE"
