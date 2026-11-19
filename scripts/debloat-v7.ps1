param(
    [Parameter(Mandatory = $true)][string]$WimPath,
    [string]$MountDir = "D:\mount7",
    [string]$LogFile  = "D:\debloat7.log"
)

$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"

function Log { param([string]$m) $l = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Write-Host $l; Add-Content -Path $LogFile -Value $l -Encoding UTF8 }

Set-Content -Path $LogFile -Value ("LuoMicro v7 ultra-lite " + (Get-Date)) -Encoding UTF8

Log "== phase 1: v6 chain =="
& "$PSScriptRoot\debloat-v6.ps1" -WimPath $WimPath -MountDir "D:\mount6" -LogFile "D:\debloat6.log"
Log "phase1 done"

if (Test-Path $MountDir) { dism /Unmount-Image /MountDir:"$MountDir" /Discard | Out-Null; Remove-Item -Recurse -Force $MountDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $MountDir | Out-Null
Log "mount phase7"
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

# ---------- 1. 干掉 Edge 全家 ----------
Log "== Edge =="
foreach ($p in @(
  "Program Files (x86)\Microsoft\Edge","Program Files\Microsoft\Edge",
  "Program Files (x86)\Microsoft\EdgeUpdate","Program Files (x86)\Microsoft\EdgeCore",
  "Program Files (x86)\Microsoft\EdgeWebView","Program Files\Microsoft\EdgeWebView",
  "Program Files (x86)\Microsoft\EdgeApplication","ProgramData\Microsoft\EdgeUpdate"
)) { if (ForceDel (Join-Path $MountDir $p)) { Log ("  del " + $p) } }
foreach ($f in @(
  "Windows\System32\MicrosoftEdge*.exe","Windows\System32\msedge.exe"
)) { Get-ChildItem -Path (Join-Path $MountDir $f) -ErrorAction SilentlyContinue | ForEach-Object { if (ForceDel $_.FullName) { Log ("  del " + $_.Name) } } }

# ---------- 2. 再挖一轮 UWP 包体 + 注册 ----------
$patterns2 = @(
 "Windows.Photos","WindowsStore","StorePurchaseApp","Windows.Settings","ImmersiveControlPanel",
 "Windows.Cortana","Windows.Search","Windows.CommunicationsApps","Windows.MediaPlayer",
 "Windows.Devices.Call","Windows.SecondaryTileExperience","Windows.Feedback","AAD.BrokerPlugin",
 "Windows.CloudExperienceHost","Windows.AccountsControl","Windows.OOBE"
)
$wa = Join-Path $MountDir "Program Files\WindowsApps"
Log "== WindowsApps round2 =="
if (Test-Path $wa) {
  Get-ChildItem -LiteralPath $wa -Force | Where-Object PSIsContainer | ForEach-Object {
    foreach ($p in $patterns2) { if ($_.Name -like "*$p*") { if (ForceDel $_.FullName) { Log ("  - WA " + $_.Name) }; break } }
  }
}
$ar = Join-Path $MountDir "ProgramData\Microsoft\Windows\AppRepository"
if (Test-Path $ar) {
  Get-ChildItem -LiteralPath $ar -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    foreach ($p in $patterns2) { if ($_.Name -like "*$p*") { if (ForceDel $_.FullName) { Log ("  - AR " + $_.Name) }; break } }
  }
}
reg load HKLM\OFSW7 (Join-Path $MountDir "Windows\System32\config\SOFTWARE") | Out-Null
$base = "HKLM:\OFSW7\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Applications"
if (Test-Path $base) {
  Get-ChildItem -Path $base -ErrorAction SilentlyContinue | ForEach-Object {
    foreach ($p in $patterns2) { if ($_.PSChildName -like "*$p*") { try { Remove-Item -LiteralPath $_.PSPath -Recurse -Force -ErrorAction Stop; Log ("  - REG " + $_.PSChildName) } catch {}; break } }
  }
}
[gc]::Collect(); Start-Sleep 1
reg unload HKLM\OFSW7 | Out-Null

# ---------- 3. 删搜索 / 生物识别 / 备份 / 恢复 / 其他大块 ----------
Log "== big blocks =="
foreach ($d in @(
 "Windows\System32\SearchIndexer.exe","Windows\System32\SearchProtocolHost.exe","Windows\System32\SearchFilterHost.exe",
 "Windows\System32\Search.UIF","Windows\System32\WinBioPlugIns","Windows\System32\WinBioDatabase",
 "Windows\System32\WindowsBackup","Windows\System32\Recovery","Windows\System32\Migration",
 "Windows\System32\migwiz","Windows\System32\winevt","Windows\System32\SMI",
 "Windows\Panther","Windows\Prefetch","Windows\CSC","Windows\Temp","Windows\SoftwareDistribution\Download",
 "Windows\System32\LogFiles","Windows\Logs","ProgramData\Microsoft\Windows\WER",
 "Windows\System32\Speech","Windows\Speech_OneCore","Windows\System32\Speech_OneCore",
 "Windows\System32\WindowsPowerShell\v1.0\Modules\PSDiagnostics",
 "Windows\System32\DriverStore\FileRepository\prnms001.inf_x86_*",
 "Windows\System32\DriverStore\FileRepository\prnms002.inf_x86_*",
 "Windows\System32\DriverStore\FileRepository\prnms003.inf_x86_*"
)) {
  $p = Join-Path $MountDir $d
  if (Test-Path $p) { if (ForceDel $p) { Log ("  del " + $d) } }
}
Get-ChildItem -Path (Join-Path $MountDir "Windows\System32\DriverStore\FileRepository") -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like "prn*" -and $_.PSIsContainer } | ForEach-Object { if (ForceDel $_.FullName) { Log ("  del prn " + $_.Name) } }

# ---------- 4. 可选功能：只留网络/音频/输入法相关 ----------
Log "== features =="
$rmFeat = @(
 "MicrosoftWindowsPowerShellISE","MicrosoftWindowsPowerShellISE-x86","FaxService",
 "Printing-XPSServices-Features","Printing-Foundation-Features","Printing-Foundation-InternetPrinting-Client",
 "Printing-Foundation-LPDPrintService","Printing-Foundation-LPRPortMonitor","WorkFolders-Client",
 "WindowsIdentityFoundation","MediaPlayback","WindowsMediaPlayer","Microsoft-Windows-MediaPlayer-Package",
 "Internet-Explorer-Optional-amd64","SMB1Protocol","MicrosoftWindows.Speech.Narrator",
 "MicrosoftWindows.Speech.VoiceAccess","TabletPCOptional","WirelessNetworking","SimpleTCP",
 "MSRDC-Infrastructure","MicrosoftWindows.Client.WebExperience"
)
foreach ($f in $rmFeat) {
  $r = & dism /Image:"$MountDir" /Disable-Feature /FeatureName:$f /Remove /Quiet /NoRestart 2>&1 | Out-String
  $line = ($r -split "`n" | Select-String -Pattern "错误|Error|操作成功|successfully" | Select-Object -First 1)
  Log ("  " + $f + " -> " + $line)
}

# ---------- 5. 服务再砍一层（保留网络/音频/USB/蓝牙/输入） ----------
Log "== services round2 =="
$CS = "HKLM:\OFSYSTEM7\ControlSet001"
reg load HKLM\OFSYSTEM7 (Join-Path $MountDir "Windows\System32\config\SYSTEM") | Out-Null
foreach ($s in @("WSearch","WinDefend","WdNisSvc","Sense","SecurityHealthService","mpssvc","wscsvc",
 "DiagTrack","dmwappushservice","WMPNetworkSvc","RemoteRegistry","MapsBroker","lfsvc","RetailDemo",
 "AJRouter","ALG","QWAVE","TimeBrokerSvc","DevQueryBroker","DevicesFlowUserSvc","WEPHOSTSVC",
 "diagnosticshub.standardcollector.service","DPS","WdiServiceHost","WdiSystemHost")) {
  $k = "$CS\Services\$s"
  if (Test-Path $k) {
    try { New-ItemProperty -Path $k -Name Start -Value 4 -PropertyType DWord -Force | Out-Null; Log ("  off " + $s) } catch {}
  }
}
[gc]::Collect(); Start-Sleep 1
reg unload HKLM\OFSYSTEM7 | Out-Null

# ---------- 6. 关掉系统还原 / 保留存储 ----------
Log "== disable restore & reserves =="
$SW = "HKLM:\OFSW7B"
reg load HKLM\OFSW7B (Join-Path $MountDir "Windows\System32\config\SOFTWARE") | Out-Null
Set-ItemProperty -Path "HKLM:\OFSW7B\Policies\Microsoft\Windows\WindowsUpdate" -Name "SetDisableUXWUAccess" -Value 1 -Force -ErrorAction SilentlyContinue
New-Item -Path "HKLM:\OFSW7B\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Force | Out-Null
Set-ItemProperty -Path "HKLM:\OFSW7B\Microsoft\Windows NT\CurrentVersion\SystemRestore" -Name "DisableSR" -Value 1 -Force
$cfg = Join-Path $MountDir "Windows\System32\config\SOFTWARE"
[gc]::Collect(); Start-Sleep 1
reg unload HKLM\OFSW7B | Out-Null
foreach ($f in @("Windows\System32\config\RegBack")) { $p = Join-Path $MountDir $f; if (Test-Path $p) { Get-ChildItem $p -Force | ForEach-Object { ForceDel $_.FullName | Out-Null } } }

Log "== ResetBase phase7 =="
dism /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet | Out-Null
dism /Image:"$MountDir" /Cleanup-Image /SPSuperseded /Quiet | Out-Null

Log "unmount commit"
dism /Unmount-Image /MountDir:"$MountDir" /Commit /Quiet
if ($LASTEXITCODE -ne 0) { throw "commit failed" }
Log "DONE"
