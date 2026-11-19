param(
    [Parameter(Mandatory = $true)][string]$WimPath,
    [string]$MountDir = "D:\mount9",
    [string]$LogFile  = "D:\debloat9.log"
)
$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"
function Log { param([string]$m) $l = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Write-Host $l; Add-Content -Path $LogFile -Value $l -Encoding UTF8 }
Set-Content -Path $LogFile -Value ("LuoMicro v9 " + (Get-Date)) -Encoding UTF8

Log "== phase 1: v8 chain =="
& "$PSScriptRoot\debloat-v8.ps1" -WimPath $WimPath -MountDir "D:\mount8" -LogFile "D:\debloat8.log"
Log "phase1 done"

if (Test-Path $MountDir) { dism /Unmount-Image /MountDir:"$MountDir" /Discard | Out-Null; Remove-Item -Recurse -Force $MountDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $MountDir | Out-Null
dism /Mount-Image /ImageFile:"$WimPath" /Index:1 /MountDir:"$MountDir" /Quiet
if ($LASTEXITCODE -ne 0) { throw "mount failed" }

function ForceDel {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  try {
    & takeown /f "$Path" /r /d y 2>$null | Out-Null
    & icacls "$Path" /grant "*S-1-5-32-544:(F)" /t /q 2>$null | Out-Null
    & icacls "$Path" /grant "*S-1-5-18:(F)" /t /q 2>$null | Out-Null
    & attrib -r -s -h "$Path" /s /d 2>$null | Out-Null
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    return $true
  } catch { Log ("    WARN " + $_.Exception.Message); return $false }
}

# ---- DriverStore 大幅瘦身：只留启动/显示/存储/USB/HID/网络必需驱动
Log "== DriverStore prune =="
$dr = Join-Path $MountDir "Windows\System32\DriverStore\FileRepository"
$keepPat = @("basicdisplay","basicrender","disk.inf","usb","usbport","usbstor","usbccgp","usbhub",
 "hid","hiddigi","kbd","mouse","net","storahci","stornvme","storport","storvsc","vhdmp",
 "volume","partmgr","pci","acpi","processor","intelppm","amdppm","cmbatt","battery",
 "hdaudio","audio","ksfilter","swenum","umpass","sfloppy","cdrom","msft",
 "bth","bluetooth","wlan","wifi","sdhost","uart","serial","monitor","camera")
if (Test-Path $dr) {
  $before = (Get-ChildItem -LiteralPath $dr -Force -ErrorAction SilentlyContinue | Measure-Object).Count
  Get-ChildItem -LiteralPath $dr -Force -ErrorAction SilentlyContinue | Where-Object PSIsContainer | ForEach-Object {
    $n = $_.Name.ToLower()
    $keep = $false
    foreach ($k in $keepPat) { if ($n -like "*$k*") { $keep = $true; break } }
    if (-not $keep) { if (ForceDel $_.FullName) { } }
  }
  $after = (Get-ChildItem -LiteralPath $dr -Force -ErrorAction SilentlyContinue | Measure-Object).Count
  Log ("  DriverStore {0} -> {1} folders" -f $before, $after)
}

# ---- 其余可删杂项
foreach ($d in @("Windows\assembly","Windows\Microsoft.NET\Framework\v1.0.3705",
 "Windows\System32\WindowsPowerShell\v1.0\Examples","Windows\System32\oobe\info",
 "Windows\System32\Windows\WinSxS\Backup","Windows\servicing\LCU")) {
  $p = Join-Path $MountDir $d
  if (Test-Path $p -and (Test-Path $p -PathType Container)) { ForceDel $p | Out-Null; Log ("  del " + $d) }
}

Log "== ResetBase phase9 =="
dism /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet | Out-Null
dism /Image:"$MountDir" /Cleanup-Image /SPSuperseded /Quiet | Out-Null
Log "unmount commit"
dism /Unmount-Image /MountDir:"$MountDir" /Commit /Quiet
if ($LASTEXITCODE -ne 0) { throw "commit failed" }
Log "DONE"
