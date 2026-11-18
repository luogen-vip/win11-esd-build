param(
    [Parameter(Mandatory = $true)][string]$WimPath,
    [string]$MountDir = "D:\mount5",
    [string]$LogFile  = "D:\debloat5.log"
)

$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"

function Log { param([string]$m) $l = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Write-Host $l; Add-Content -Path $LogFile -Value $l -Encoding UTF8 }
function SetReg { param([string]$P,[string]$N,$V,[string]$T="DWord") try { if(-not(Test-Path -LiteralPath $P)){New-Item -Path $P -Force|Out-Null}; New-ItemProperty -Path $P -Name $N -Value $V -PropertyType $T -Force|Out-Null } catch {} }

Set-Content -Path $LogFile -Value ("LuoLite v5 " + (Get-Date)) -Encoding UTF8

# ---------- phase 1: v4 chain (v2 base + winre/print + backup/voice)
Log "== phase 1: debloat-v4 chain =="
& "$PSScriptRoot\debloat-v4.ps1" -WimPath $WimPath -MountDir "D:\mount4" -LogFile "D:\debloat4.log"
Log "phase 1 done"

# ---------- phase 2: final aggressive cut
if (Test-Path $MountDir) { dism /Unmount-Image /MountDir:"$MountDir" /Discard | Out-Null; Remove-Item -Recurse -Force $MountDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $MountDir | Out-Null
Log "mounting phase 2"
dism /Mount-Image /ImageFile:"$WimPath" /Index:1 /MountDir:"$MountDir" /Quiet
if ($LASTEXITCODE -ne 0) { throw "mount failed" }

# ---- appx: only keep Edge/Photos/Settings/Notepad/ScreenSketch/Explorer/Store
$del = @(
 "Microsoft.Paint","Microsoft.MSPaint","Microsoft.WindowsAlarms","Microsoft.OutlookForWindows",
 "Microsoft.MicrosoftSolitaireCollection","Microsoft.Clipchamp","Microsoft.GamingApp",
 "Microsoft.XboxGamingOverlay","Microsoft.XboxIdentityProvider","Microsoft.XboxSpeechToTextOverlay",
 "Microsoft.Xbox.TCUI","Microsoft.DevHome","Microsoft.WindowsFeedbackHub","Microsoft.GetHelp",
 "Microsoft.Getstarted","Microsoft.Windows.GettingStarted","Microsoft.WindowsMaps",
 "Microsoft.OneDriveSync","Microsoft.ZuneMusic","Microsoft.ZuneVideo","Microsoft.People",
 "Microsoft.SkypeApp","Microsoft.Teams","Microsoft.BingNews","Microsoft.BingWeather",
 "Microsoft.YourPhone","Microsoft.MicrosoftOfficeHub","Microsoft.Microsoft3DViewer",
 "Microsoft.Print3D","Microsoft.MixedReality.Portal","Microsoft.Wallet","Microsoft.OneConnect",
 "Microsoft.WindowsCommunicationsApps","Microsoft.MicrosoftStickyNotes","Microsoft.WindowsCamera",
 "Microsoft.Todos","Microsoft.Copilot","Microsoft.SecHealthUI","Microsoft.Windows.Backup",
 "Microsoft.Windows.VoiceAccess","Microsoft.VoiceAccess","Microsoft.WindowsTerminal",
 "Microsoft.Windows.Photos.PreviewApp","Microsoft.WebExperience","Microsoft.Windows.WebExperience",
 "Microsoft.PowerAutomateDesktop","Microsoft.BingSearch","Microsoft.RemoteDesktop",
 "Microsoft.CorrelationVector","Microsoft.Windows.ParentalControls","Microsoft.Family"
)
Log "== appx removal =="
Get-AppxProvisionedPackage -Path $MountDir -ErrorAction SilentlyContinue | ForEach-Object {
  $pkg = $_
  foreach ($pat in $del) { if ($pkg.PackageName -like "*$pat*") {
    Log ("  - " + $pkg.PackageName)
    try { Remove-AppxProvisionedPackage -Path $MountDir -PackageName $pkg.PackageName -ErrorAction Stop | Out-Null } catch { Log ("    WARN " + $_.Exception.Message) }
    break } }
}
Log "== kept =="
Get-AppxProvisionedPackage -Path $MountDir -ErrorAction SilentlyContinue |
  Where-Object { $_.PackageName -match "Photos|Notepad|ScreenSketch|WindowsStore|Settings|Shell" } |
  ForEach-Object { Log ("  KEEP " + $_.PackageName) }

# ---- file level cuts (safe ones only: no power/shell core)
$files = @(
 "Windows\System32\psr.exe","Windows\System32\iscsicpl.exe","Windows\System32\printmanagement.msc",
 "Windows\System32\charmap.exe","Windows\System32\mstsc.exe","Windows\System32\odbcad32.exe",
 "Windows\System32\Narrator.exe","Windows\System32\Magnify.exe","Windows\System32\mspaint.exe",
 "Windows\System32\WindowsBackup.exe"
)
foreach ($f in $files) { $p = Join-Path $MountDir $f; if (Test-Path $p) { try { Remove-Item -Force $p -ErrorAction Stop; Log ("  del " + $f) } catch { Log ("  WARN locked " + $f) } } }
foreach ($d in @("Windows\System32\WindowsBackup","Windows\System32\Speech","Windows\Speech_OneCore")) {
  $p = Join-Path $MountDir $d
  if (Test-Path $p) { & takeown /f "$p" /r /d y 2>$null | Out-Null; & icacls "$p" /grant "*S-1-5-32-544:(F)" /t /q 2>$null | Out-Null
    try { Remove-Item -Recurse -Force $p -ErrorAction Stop; Log ("  del dir " + $d) } catch { Log ("  WARN locked " + $d) } }
}

# ---- services: disable only safe extras; NEVER touch power/plugplay/wdi/dps
Log "== extra services disabled =="
$svcExtra = @("SessionSharing","iscsi","iscsivdisk","RemoteAccess","SharedAccess","PhoneSvc","SEMgrSvc",
 "WalletService","WpcMonSvc","AssignedAccessManagerSvc","TapiSrv","NfcCx","XblAuthManager",
 "XblGameSave","XboxGipSvc","XboxNetApiSvc","SDRSVC","wbengine","HomeGroupListener","HomeGroupProvider",
 "PrintDeviceConfigurationService","PrintNotify","Spooler","Fax","stisvc","WbioSrvc","SensorService",
 "SensorDataService","EFS","BDESVC","NaturalAuthentication","TabletInputService","hidserv","ScDeviceEnum","MixedRealitySvc")
$CS = "HKLM:\OFFSYSTEM5\ControlSet001"
reg load HKLM\OFFSYSTEM5 (Join-Path $MountDir "Windows\System32\config\SYSTEM") | Out-Null
reg load HKLM\OFFSOFTWARE5 (Join-Path $MountDir "Windows\System32\config\SOFTWARE") | Out-Null
reg load HKLM\OFFDEFAULT5 (Join-Path $MountDir "Windows\System32\config\DEFAULT") | Out-Null
foreach ($s in $svcExtra) { $k = "$CS\Services\$s"; if (Test-Path $k) { SetReg -Path $k -Name Start -Value 4; Log ("  off " + $s) } }

$SW5 = "HKLM:\OFFSOFTWARE5"
# ---- Windows Update: fully off, keep components but block use
$wu = "$SW5\Policies\Microsoft\Windows\WindowsUpdate"
SetReg $wu "NoAutoUpdate" 1; SetReg $wu "AUOptions" 1; SetReg $wu "ExcludeWUDriversInQualityUpdate" 1
SetReg $wu "SetDisableUXWUAccess" 1; SetReg "$wu\AU" "NoAutoUpdate" 1; SetReg "$wu\AU" "AUOptions" 1
SetReg "$SW5\Policies\Microsoft\Windows\WindowsUpdate\AU" "NoAutoRebootWithLoggedOnUsers" 1
SetReg "$SW5\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 0
SetReg "$SW5\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config" "DODownloadMode" 0
SetReg "$SW5\Policies\Microsoft\WindowsStore" "AutoDownload" 2
SetReg "$SW5\Policies\Microsoft\WindowsStore" "DisableAppUpdate" 1
SetReg "$SW5\Policies\Microsoft\Windows\Appx" "DisableAutomaticAppUpdates" 1
# ---- ads/suggestions off, but keep search history ON
SetReg "$SW5\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy" 1
SetReg "$SW5\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
SetReg "HKLM:\OFFDEFAULT5\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
SetReg "$SW5\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338387Enabled" 0
SetReg "$SW5\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" 0
SetReg "$SW5\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338389Enabled" 0
SetReg "$SW5\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353698Enabled" 0
SetReg "$SW5\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" 0
SetReg "$SW5\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SilentInstalledAppsEnabled" 0
SetReg "$SW5\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1
SetReg "$SW5\Policies\Microsoft\Windows\CloudContent" "DisableSoftLanding" 1
SetReg "$SW5\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0
SetReg "$SW5\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 0
# 保留搜索历史（你说要打开“改进开始和搜索结果”）
SetReg "HKLM:\OFFDEFAULT5\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0
# ---- no auto driver install + keep power stack intact
SetReg "$SW5\Microsoft\Windows\CurrentVersion\DriverSearching" "SearchOrderConfig" 0
SetReg "$SW5\Policies\Microsoft\Windows\DeviceInstall\Settings" "PreventDeviceMetadataFromNetwork" 1
# ---- security / popups fully off
SetReg "$SW5\Policies\Microsoft\Windows Defender" "DisableAntiSpyware" 1
SetReg "$SW5\Policies\Microsoft\Windows Defender" "DisableAntiVirus" 1
SetReg "$SW5\Policies\Microsoft\Windows\System" "EnableSmartScreen" 0
SetReg "$SW5\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled" "Off" "String"
SetReg "$SW5\Policies\Microsoft\Edge" "SmartScreenEnabled" 0
SetReg "$SW5\Policies\Microsoft\Edge" "SmartScreenPuaEnabled" 0
SetReg "$SW5\Policies\Microsoft\EdgeUpdate" "UpdateDefault" 0
SetReg "$SW5\Policies\Microsoft\EdgeUpdate" "DisableAutoUpdateChecksCheckboxValue" 1
# ---- explorer defaults
$DF = "HKLM:\OFFDEFAULT5\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
SetReg $DF "HideFileExt" 0; SetReg $DF "ShowSecondsInSystemClock" 1; SetReg $DF "ShowTaskViewButton" 0
# ---- UAC never notify, keep LUA on
SetReg "$SW5\Microsoft\Windows\CurrentVersion\Policies\System" "ConsentPromptBehaviorAdmin" 0
SetReg "$SW5\Microsoft\Windows\CurrentVersion\Policies\System" "PromptOnSecureDesktop" 0
SetReg "$SW5\Microsoft\Windows\CurrentVersion\Policies\System" "EnableLUA" 1
# ---- disable remote desktop host, keep SMB
SetReg "$CS\Control\Terminal Server" "fDenyTSConnections" 1
SetReg "$CS\Services\LanmanServer" "Start" 2
SetReg "$CS\Services\LanmanWorkstation" "Start" 2

[gc]::Collect()
foreach ($h in @("OFFSYSTEM5","OFFSOFTWARE5","OFFDEFAULT5")) { reg unload "HKLM\$h" | Out-Null }

# ---- languages: keep zh-CN only if en-US is removable? keep both per request
Log "== languages =="
dism /Image:"$MountDir" /Get-InstalledLanguages | Select-String "Language" | ForEach-Object { Log ("  " + $_.Line.Trim()) }

Log "== ResetBase phase5 =="
dism /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet | Out-Null
Log ("  exit " + $LASTEXITCODE)

Log "unmount commit"
dism /Unmount-Image /MountDir:"$MountDir" /Commit /Quiet
if ($LASTEXITCODE -ne 0) { throw "commit failed" }
Log "DONE"
