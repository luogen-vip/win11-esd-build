param(
    [Parameter(Mandatory = $true)][string]$WimPath,
    [string]$MountDir = "D:\mount",
    [string]$LogFile  = "D:\debloat2.log"
)

$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"

function Log {
    param([string]$msg)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function SetReg {
    param([string]$Path, [string]$Name, $Value, [string]$Type = "DWord")
    try {
        if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
        New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
    } catch { Log ("  [WARN] reg " + $Path + "\" + $Name + " : registry locked") }
}

Set-Content -Path $LogFile -Value ("LuoLite debloat start " + (Get-Date)) -Encoding UTF8

# ================================================================ mount
if (Test-Path $MountDir) {
    Log "cleaning stale mount"
    dism /Unmount-Image /MountDir:"$MountDir" /Discard | Out-Null
    Remove-Item -Recurse -Force $MountDir -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $MountDir | Out-Null
Log "mounting $WimPath"
dism /Mount-Image /ImageFile:"$WimPath" /Index:1 /MountDir:"$MountDir" /Quiet
if ($LASTEXITCODE -ne 0) { throw "mount failed $LASTEXITCODE" }
Log "mounted OK"

# ================================================================ 1. UWP removal
# 保留：Edge、照片、记事本、截图工具(ScreenSketch)、画图? (删)、设置、资源管理器、商店、小组件
$remove = @(
    "Microsoft.WindowsCommunicationsApps",
    "Microsoft.MicrosoftStickyNotes","Microsoft.WindowsCamera","Microsoft.WindowsAlarms",
    "Microsoft.Copilot","Microsoft.Todos","Microsoft.BingWeather","Microsoft.MSNWeather",
    "Microsoft.YourPhone","Microsoft.GamingApp","Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider","Microsoft.XboxSpeechToTextOverlay","Microsoft.Xbox.TCUI",
    "Microsoft.MicrosoftOfficeHub","Microsoft.GetHelp","Microsoft.Getstarted",
    "Microsoft.WindowsFeedbackHub","Microsoft.BingNews","Microsoft.MSNNews",
    "Microsoft.ZuneMusic","Microsoft.ZuneVideo","Microsoft.People",
    "Microsoft.MicrosoftSolitaireCollection","Microsoft.SkypeApp","Microsoft.Teams",
    "Microsoft.OutlookForWindows","Microsoft.Microsoft3DViewer","Microsoft.Print3D",
    "Microsoft.MixedReality.Portal","Microsoft.Wallet","Microsoft.OneConnect","Microsoft.DevHome",
    "Microsoft.549981C3F5F10","Microsoft.WindowsMaps","Microsoft.OneDriveSync",
    "Microsoft.MicrosoftEdgeDevToolsClient","Microsoft.MSPaint","Microsoft.Paint",
    "Microsoft.BingSearch","Microsoft.Family","MicrosoftCorporationII.MicrosoftFamily",
    "Microsoft.PowerAutomateDesktop","Microsoft.Windows.Photos.Preview",
    "Microsoft.SecHealthUI","Microsoft.WindowsTerminal",
    "Microsoft.MicrosoftOfficeHub","Microsoft.RemoteDesktop"
)
Log "== removing provisioned packages =="
$prov = Get-AppxProvisionedPackage -Path $MountDir -ErrorAction SilentlyContinue
Log ("  total: " + ($prov | Measure-Object).Count)
foreach ($p in $prov) {
    foreach ($pat in $remove) {
        if ($p.PackageName -like "*$pat*") {
            Log ("  - " + $p.PackageName)
            try { Remove-AppxProvisionedPackage -Path $MountDir -PackageName $p.PackageName -ErrorAction Stop | Out-Null }
            catch { Log ("    [WARN] " + $_.Exception.Message) }
            break
        }
    }
}

# ================================================================ 2. optional features
$featOff = @(
    "Printing-Foundation-Features","Printing-Foundation-InternetPrinting-Client",
    "Printing-Foundation-LPDPrintService","Printing-PrinterShare","Faxing",
    "WorkFolders-Client","Containers-DisposableClientVM","Microsoft-Hyper-V-All",
    "VirtualMachinePlatform","Internet-Explorer-Optional-amd64","WindowsMediaPlayer",
    "TelnetClient","TFTP","SimpleTCP","SNMP","DirectPlay","XPS-Foundation-Package",
    "MicrosoftWindows-TabletPC","OpticalMediaDisc"
)
Log "== disabling optional features =="
foreach ($f in $featOff) {
    dism /Image:"$MountDir" /Disable-Feature /FeatureName:$f /Quiet | Out-Null
    Log ("  {0} -> {1}" -f $f, $LASTEXITCODE)
}

# ================================================================ 3. drivers: printer class only (default ones can't be removed)
Log "== driver packages =="
$drv = Get-WindowsDriver -Path $MountDir -All -ErrorAction SilentlyContinue
Log ("  total: " + ($drv | Measure-Object).Count)
foreach ($d in ($drv | Where-Object { $_.ClassName -in @("Printer","PrintQueue") })) {
    try { Remove-WindowsDriver -Path $MountDir -Driver $d.Driver -ErrorAction Stop | Out-Null; Log ("  removed " + $d.Driver) }
    catch { }
}
Log ("  left: " + ((Get-WindowsDriver -Path $MountDir -All -ErrorAction SilentlyContinue | Measure-Object).Count))

# ================================================================ 4. registry
Log "== loading hives =="
$sysReg  = Join-Path $MountDir "Windows\System32\config\SYSTEM"
$softReg = Join-Path $MountDir "Windows\System32\config\SOFTWARE"
$defReg  = Join-Path $MountDir "Windows\System32\config\DEFAULT"
reg load HKLM\OFFSYSTEM  $sysReg  | Out-Null
reg load HKLM\OFFSOFTWARE $softReg | Out-Null
reg load HKLM\OFFDEFAULT $defReg | Out-Null
$CS = "HKLM:\OFFSYSTEM\ControlSet001"
$SW = "HKLM:\OFFSOFTWARE"
$DF = "HKLM:\OFFDEFAULT"

# ---- services disabled
$svcOff = @(
    "wuauserv","UsoSvc","WaaSMedicSvc","DoSvc","DiagTrack","dmwappushservice","WerSvc",
    "SysMain","MapsBroker","RemoteRegistry","RetailDemo","Fax","Spooler","wisvc",
    "XblAuthManager","XblGameSave","XboxGipSvc","XboxNetApiSvc",
    "SecurityHealthService","WdNisSvc","Sense","DsmSvc","stisvc","WbioSrvc",
    "SensorService","SensorDataService","WMPNetworkSvc","PcaSvc","DPS",
    "WdiServiceHost","WdiSystemHost","bthserv","BluetoothUserService","ScDeviceEnum",
    "WpcMonSvc","AssignedAccessManagerSvc","TapiSrv","PhoneSvc","SEMgrSvc","NfcCx","icssvc",
    "NaturalAuthentication","TabletInputService","hidserv","SharedAccess"
)
Log "== services: disabled =="
foreach ($s in $svcOff) {
    $k = "$CS\Services\$s"
    if (Test-Path $k) { SetReg -Path $k -Name Start -Value 4; Log "  off  $s" }
}
# keep LAN file sharing + On-Screen Keyboard support alive
foreach ($s in @("LanmanServer","LanmanWorkstation","WpnService","EventLog","gpsvc")) {
    $k = "$CS\Services\$s"
    if (Test-Path $k) { Log "  (keep) $s" }
}
foreach ($s in @("BITS","WinDefend","wscsvc")) {
    $k = "$CS\Services\$s"
    if (Test-Path $k) { SetReg -Path $k -Name Start -Value 3 }
}

# ---- Windows Update fully off + no driver updates
$wu = "$SW\Policies\Microsoft\Windows\WindowsUpdate"
SetReg $wu "NoAutoUpdate" 1
SetReg $wu "AUOptions" 1
SetReg $wu "ExcludeWUDriversInQualityUpdate" 1
SetReg $wu "SetDisableUXWUAccess" 1
SetReg $wu "DoNotConnectToWindowsUpdateInternetLocations" 1
SetReg "$wu\AU" "NoAutoUpdate" 1
SetReg "$wu\AU" "AUOptions" 1
SetReg "$wu\AU" "NoAutoRebootWithLoggedOnUsers" 1
SetReg "$SW\Policies\Microsoft\WindowsStore" "AutoDownload" 2
SetReg "$SW\Policies\Microsoft\Windows\DriverSearching" "SearchOrderConfig" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\DriverSearching" "SearchOrderConfig" 0

# ---- ads / telemetry / suggestions
SetReg "$SW\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
SetReg "$SW\Policies\Microsoft\Windows\DataCollection" "DoNotShowFeedbackNotifications" 1
SetReg "$SW\Policies\Microsoft\Windows\DataCollection" "DisableOneSettingsDownloads" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" 0
SetReg "$SW\Policies\Microsoft\Windows\AdvertisingInfo" "DisabledByGroupPolicy" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
SetReg "$DF\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0
SetReg "$SW\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1
SetReg "$SW\Policies\Microsoft\Windows\CloudContent" "DisableSoftLanding" 1
SetReg "$SW\Policies\Microsoft\Windows\CloudContent" "DisableSpotlightCollectionOnDesktop" 1
SetReg "$SW\Policies\Microsoft\Windows\CloudContent" "DisableConsumerAccountStateContent" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SilentInstalledAppsEnabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338389Enabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-353698Enabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SoftLandingEnabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "OemPreInstalledAppsEnabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "PreInstalledAppsEnabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0
SetReg "$SW\Policies\Microsoft\Windows\Explorer" "NoWindowsTips" 1
SetReg "$SW\Policies\Microsoft\Windows\Explorer" "DisableSearchBoxSuggestions" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\Search" "CortanaConsent" 0
SetReg "$SW\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0
SetReg "$SW\Policies\Microsoft\Windows\Windows Search" "DisableWebSearch" 1
SetReg "$SW\Policies\Microsoft\Windows\Windows Search" "ConnectedSearchUseWeb" 0
SetReg "$SW\Policies\Microsoft\Windows\Windows Search" "AllowSearchToUseLocation" 0

# ---- Defender / security center / smartscreen off
SetReg "$SW\Policies\Microsoft\Windows Defender" "DisableAntiSpyware" 1
SetReg "$SW\Policies\Microsoft\Windows Defender" "DisableAntiVirus" 1
SetReg "$SW\Policies\Microsoft\Windows Defender" "DisableRoutinelyTakingAction" 1
SetReg "$SW\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableRealtimeMonitoring" 1
SetReg "$SW\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableBehaviorMonitoring" 1
SetReg "$SW\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableOnAccessProtection" 1
SetReg "$SW\Policies\Microsoft\Windows Defender\Spynet" "SubmitSamplesConsent" 2
SetReg "$SW\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled" "Off" "String"
SetReg "$SW\Policies\Microsoft\Windows\System" "EnableSmartScreen" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\Attachments" "SaveZoneInformation" 2
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\Attachments" "HideZoneInfoOnProperties" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\Attachments" "ScanWithAntiVirus" 1

# ---- Edge: no auto update / no startup boost / no background
SetReg "$SW\Policies\Microsoft\Edge" "SmartScreenEnabled" 0
SetReg "$SW\Policies\Microsoft\Edge" "SmartScreenPuaEnabled" 0
SetReg "$SW\Policies\Microsoft\Edge" "StartupBoostEnabled" 0
SetReg "$SW\Policies\Microsoft\Edge" "BackgroundModeEnabled" 0
SetReg "$SW\Policies\Microsoft\EdgeUpdate" "UpdateDefault" 0
SetReg "$SW\Policies\Microsoft\EdgeUpdate" "DisableAutoUpdateChecksCheckboxValue" 1
SetReg "$SW\Policies\Microsoft\EdgeUpdate\Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" "Update" 0
SetReg "$SW\Policies\Microsoft\EdgeUpdate\Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" "Allowsxs" 0

# ---- UAC never notify (LUA stays on so UWP keeps working)
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\System" "ConsentPromptBehaviorAdmin" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\System" "PromptOnSecureDesktop" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\System" "EnableInstallerDetection" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\System" "EnableLUA" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\System" "FilterAdministratorToken" 0

# ---- OOBE local account
SetReg "$SW\Microsoft\Windows\CurrentVersion\OOBE" "BypassNRO" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\OOBE" "HideOnlineAccountScreens" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\OOBE" "HideWirelessSetupInOOBE" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\OOBE" "PrivacyConsentStatus" 1

# ---- power: no hibernation / no fast startup
SetReg "$CS\Control\Session Manager\Power" "HibernateEnabled" 0
SetReg "$CS\Control\Session Manager\Power" "HiberbootEnabled" 0
SetReg "$CS\Control\Power" "HibernateEnabled" 0

# ---- time: China NTP
SetReg "$CS\Services\W32Time\Parameters" "NtpServer" "ntp.aliyun.com,0x9 ntp1.aliyun.com,0x9 ntp.tencent.com,0x9" "String"
SetReg "$CS\Services\W32Time\Parameters" "Type" "NTP" "String"
SetReg "$CS\Services\W32Time\TimeProviders\NtpClient" "Enabled" 1
SetReg "$CS\Services\W32Time\TimeProviders\NtpClient" "SpecialPollInterval" 3600
SetReg "$CS\Services\W32Time" "Start" 2
SetReg "$CS\Control\TimeZoneInformation" "TimeZoneKeyName" "China Standard Time" "String"

# ---- DEFAULT user: show extensions, seconds clock, 24h, no tips
SetReg "$DF\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0
SetReg "$DF\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSecondsInSystemClock" 1
SetReg "$DF\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "EnableBalloonTips" 0
SetReg "$DF\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" 0
SetReg "$DF\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarDa" 1
SetReg "$DF\Control Panel\International" "sShortTime" "HH:mm" "String"
SetReg "$DF\Control Panel\International" "sTimeFormat" "HH:mm:ss" "String"
SetReg "$DF\Control Panel\International" "sShortDate" "yyyy/M/d" "String"
SetReg "$DF\Control Panel\International" "iTime" 1
SetReg "$DF\Control Panel\Desktop" "ScreenSaveActive" "0" "String"
SetReg "$DF\Control Panel\Desktop" "MenuShowDelay" "0" "String"
SetReg "$DF\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications" 0

# ---- disable OneDrive in shell / remove autostart hooks
SetReg "$SW\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" 1
SetReg "$SW\Policies\Microsoft\Windows\OneDrive" "DisableFileSync" 1

# ---- unload
Log "== unloading hives =="
[gc]::Collect()
reg unload HKLM\OFFSYSTEM   | Out-Null
reg unload HKLM\OFFSOFTWARE | Out-Null
reg unload HKLM\OFFDEFAULT  | Out-Null

# ================================================================ 5. file-level cleanup
$wallRoot = Join-Path $MountDir "Windows\Web\Wallpaper"
if (Test-Path $wallRoot) {
    Get-ChildItem -Path $wallRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "img0.jpg" } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    Get-ChildItem -Path (Join-Path $MountDir "Windows\Web\4K") -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne "img0.jpg" } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Log "  trimmed extra wallpapers"
}
foreach ($one in @("Windows\System32\OneDriveSetup.exe","Windows\SysWOW64\OneDriveSetup.exe")) {
    $p = Join-Path $MountDir $one
    if (Test-Path $p) { Remove-Item -Force $p -ErrorAction SilentlyContinue; Log ("  removed " + $one) }
}
# 删除 Store 自动安装的应用暂存（防止联网又下回来）
$stub = Join-Path $MountDir "Windows\SystemApps\Microsoft.Windows.ContentDeliveryManager_cw5n1h2txyewy"
if (Test-Path $stub) { Log "  ContentDeliveryManager kept (needed by shell)" }

# ================================================================ 6. component cleanup
Log "== ResetBase =="
dism /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet | Out-Null
Log ("  exit " + $LASTEXITCODE)

Log "== languages =="
dism /Image:"$MountDir" /Get-InstalledLanguages | Select-String -Pattern "zh-CN|en-US|Language" | ForEach-Object { Log ("  " + $_.Line.Trim()) }

# ================================================================ 7. unmount
Log "unmount commit"
dism /Unmount-Image /MountDir:"$MountDir" /Commit /Quiet
if ($LASTEXITCODE -ne 0) { throw "commit failed $LASTEXITCODE" }
Log "DONE"
