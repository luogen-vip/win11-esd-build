param(
    [Parameter(Mandatory = $true)][string]$WimPath,
    [string]$MountDir = "D:\mount",
    [string]$LogFile  = "D:\optimize.log"
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
    } catch { Log ("  [WARN] reg $Path\$Name : " + $_.Exception.Message) }
}

Set-Content -Path $LogFile -Value ("Optimize start " + (Get-Date)) -Encoding UTF8

# ---------------------------------------------------------------- mount
if (Test-Path $MountDir) { Log "Removing stale mount dir"; dism /Unmount-Image /MountDir:"$MountDir" /Discard | Out-Null; Remove-Item -Recurse -Force $MountDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $MountDir | Out-Null

Log "Mounting $WimPath (index 1)"
dism /Mount-Image /ImageFile:"$WimPath" /Index:1 /MountDir:"$MountDir" /Quiet
if ($LASTEXITCODE -ne 0) { throw "DISI mount failed with $LASTEXITCODE" }
Log "Mounted OK"

# ---------------------------------------------------------------- 1. remove provisioned UWP apps
$appPatterns = @(
    "Clipchamp.Clipchamp",
    "Microsoft.WindowsCommunicationsApps",
    "Microsoft.MicrosoftStickyNotes",
    "Microsoft.WindowsCamera",
    "Microsoft.WindowsAlarms",
    "Microsoft.Copilot",
    "Microsoft.Todos",
    "Microsoft.BingWeather",
    "Microsoft.MSNWeather",
    "Microsoft.YourPhone",
    "Microsoft.GamingApp",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxIdentityProvider",
    "Microsoft.XboxSpeechToTextOverlay",
    "Microsoft.Xbox.TCUI",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.BingNews",
    "Microsoft.MSNNews",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "Microsoft.People",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.SkypeApp",
    "Microsoft.Teams",
    "Microsoft.OutlookForWindows",
    "Microsoft.Microsoft3DViewer",
    "Microsoft.Print3D",
    "Microsoft.MixedReality.Portal",
    "Microsoft.Wallet",
    "Microsoft.OneConnect",
    "Microsoft.DevHome",
    "Microsoft.MicrosoftOfficeHub",
    "Microsoft.549981C3F5F10",
    "Microsoft.StorePurchaseApp",
    "Microsoft.WindowsFeedbackHub"
)

Log "== Removing provisioned appx packages =="
$prov = Get-AppxProvisionedPackage -Path $MountDir -ErrorAction SilentlyContinue
Log ("  total provisioned: " + ($prov | Measure-Object).Count)
foreach ($p in $prov) {
    foreach ($pat in $appPatterns) {
        if ($p.PackageName -like "*$pat*") {
            Log ("  removing " + $p.PackageName)
            try { Remove-AppxProvisionedPackage -Path $MountDir -PackageName $p.PackageName -ErrorAction Stop | Out-Null }
            catch { Log ("    [WARN] " + $_.Exception.Message) }
            break
        }
    }
}

# ---------------------------------------------------------------- 2. remove optional features
$featOff = @(
    "Printing-Foundation-Features",
    "Printing-Foundation-InternetPrinting-Client",
    "Printing-Foundation-LPDPrintService",
    "Faxing",
    "WorkFolders-Client",
    "Containers-DisposableClientVM",
    "Microsoft-Hyper-V-All",
    "VirtualMachinePlatform",
    "Internet-Explorer-Optional-amd64",
    "WindowsMediaPlayer",
    "TelnetClient",
    "TFTP",
    "SimpleTCP",
    "SNMP",
    "DirectPlay",
    "XPS-Foundation-Package"
)
Log "== Disabling optional features =="
foreach ($f in $featOff) {
    dism /Image:"$MountDir" /Disable-Feature /FeatureName:$f /Quiet | Out-Null
    Log ("  {0} -> exit {1}" -f $f, $LASTEXITCODE)
}

# ---------------------------------------------------------------- 3. remove driver packages (printer / GPU / VR)
Log "== Driver packages before =="
$drv = Get-WindowsDriver -Path $MountDir -All -ErrorAction SilentlyContinue
Log ("  total drivers: " + ($drv | Measure-Object).Count)

$badDrv = $drv | Where-Object {
    $_.ClassName -in @("Printer", "PrintQueue") -or
    $_.ProviderName -match "NVIDIA|Intel Corporation|Oculus|Valve|HTC|Ricoh|Canon|Epson|Brother|Kyocera|Xerox" -or
    $_.OriginalFileName -match "printer|nvlddmkm|igdlh|oculus|vive"
}
foreach ($d in $badDrv) {
    Log ("  removing driver: " + $d.ProviderName + " / " + $d.ClassName + " / " + $d.OriginalFileName)
    try { Remove-WindowsDriver -Path $MountDir -Driver $d.OriginalFileName -ErrorAction Stop | Out-Null }
    catch { Log ("    [WARN] " + $_.Exception.Message) }
}
Log ("  drivers left: " + ((Get-WindowsDriver -Path $MountDir -All -ErrorAction SilentlyContinue | Measure-Object).Count))

# ---------------------------------------------------------------- 4. load hives and apply registry
$sysReg  = Join-Path $MountDir "Windows\System32\config\SYSTEM"
$softReg = Join-Path $MountDir "Windows\System32\config\SOFTWARE"
$defReg  = Join-Path $MountDir "Windows\System32\config\DEFAULT"

Log "== Loading registry hives =="
reg load HKLM\OFFSYSTEM  $sysReg  | Out-Null
reg load HKLM\OFFSOFTWARE $softReg | Out-Null
reg load HKLM\OFFDEFAULT $defReg | Out-Null

$CS = "HKLM:\OFFSYSTEM\ControlSet001"
$SW = "HKLM:\OFFSOFTWARE"
$DF = "HKLM:\OFFDEFAULT"

# ---- services to disable (4 = disabled, 3 = manual)
$svcDisabled = @(
    "wuauserv", "UsoSvc", "WaaSMedicSvc", "DoSvc",
    "DiagTrack", "dmwappushservice", "WerSvc",
    "SysMain", "MapsBroker", "RemoteRegistry", "RetailDemo",
    "Fax", "Spooler", "wisvc", "WMPNetworkSvc",
    "XblAuthManager", "XblGameSave", "XboxGipSvc", "XboxNetApiSvc",
    "SecurityHealthService", "WdNisSvc", "Sense",
    "PcaSvc", "DPS", "WdiServiceHost", "WdiSystemHost"
)
$svcManual = @("BITS", "WinDefend", "wscsvc")   # keep as manual, not fully off

Log "== Services =="
foreach ($s in $svcDisabled) {
    $k = "$CS\Services\$s"
    if (Test-Path $k) { SetReg -Path $k -Name Start -Value 4; Log "  disabled $s" }
    else { Log "  (not present) $s" }
}
foreach ($s in $svcManual) {
    $k = "$CS\Services\$s"
    if (Test-Path $k) { SetReg -Path $k -Name Start -Value 3; Log "  manual $s" }
}

# ---- Windows Update: fully off, no driver updates, hide UI
$wu = "$SW\Policies\Microsoft\Windows\WindowsUpdate"
SetReg $wu "NoAutoUpdate" 1
SetReg $wu "AUOptions" 1
SetReg $wu "ExcludeWUDriversInQualityUpdate" 1
SetReg $wu "SetDisableUXWUAccess" 1
SetReg $wu "DoNotConnectToWindowsUpdateInternetLocations" 1
$wuau = "$SW\Policies\Microsoft\Windows\WindowsUpdate\AU"
SetReg $wuau "NoAutoUpdate" 1
SetReg $wuau "AUOptions" 1
SetReg $wuau "NoAutoRebootWithLoggedOnUsers" 1
SetReg "$SW\Policies\Microsoft\Windows\WindowsUpdate\AU" "UseWUServer" 1
# stop store from auto-updating apps
SetReg "$SW\Policies\Microsoft\WindowsStore" "AutoDownload" 2
# stop driver search via device installation
SetReg "$SW\Policies\Microsoft\Windows\DriverSearching" "SearchOrderConfig" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\DriverSearching" "SearchOrderConfig" 0

# ---- telemetry / diagnostics upload
SetReg "$SW\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0
SetReg "$SW\Policies\Microsoft\Windows\DataCollection" "DoNotShowFeedbackNotifications" 1
SetReg "$SW\Policies\Microsoft\Windows\DataCollection" "DisableOneSettingsDownloads" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\DataCollection" "AllowTelemetry" 0
SetReg "$SW\Policies\Microsoft\Windows\CloudContent" "DisableWindowsConsumerFeatures" 1
SetReg "$SW\Policies\Microsoft\Windows\CloudContent" "DisableSoftLanding" 1
SetReg "$SW\Policies\Microsoft\Windows\CloudContent" "DisableSpotlightCollectionOnDesktop" 1

# ---- Microsoft Defender (off, user request)
SetReg "$SW\Policies\Microsoft\Windows Defender" "DisableAntiSpyware" 1
SetReg "$SW\Policies\Microsoft\Windows Defender" "DisableAntiVirus" 1
SetReg "$SW\Policies\Microsoft\Windows Defender" "DisableRoutinelyTakingAction" 1
SetReg "$SW\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableRealtimeMonitoring" 1
SetReg "$SW\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableBehaviorMonitoring" 1
SetReg "$SW\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableOnAccessProtection" 1
SetReg "$SW\Policies\Microsoft\Windows Defender\Real-Time Protection" "DisableScanOnRealtimeEnable" 1
SetReg "$SW\Policies\Microsoft\Windows Defender\Spynet" "SubmitSamplesConsent" 2

# ---- SmartScreen / download zone prompts / attachment manager (no "keep or delete" popup)
SetReg "$SW\Microsoft\Windows\CurrentVersion\Explorer" "SmartScreenEnabled" "Off" "String"
SetReg "$SW\Policies\Microsoft\Windows\System" "EnableSmartScreen" 0
SetReg "$SW\Policies\Microsoft\Windows\System" "ShellSmartScreenLevel" "Warn" "String"
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\Attachments" "SaveZoneInformation" 2
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\Attachments" "HideZoneInfoOnProperties" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\Attachments" "ScanWithAntiVirus" 1
# Edge smart screen off + no startup boost + no background mode
SetReg "$SW\Policies\Microsoft\Edge" "SmartScreenEnabled" 0
SetReg "$SW\Policies\Microsoft\Edge" "SmartScreenPuaEnabled" 0
SetReg "$SW\Policies\Microsoft\Edge" "StartupBoostEnabled" 0
SetReg "$SW\Policies\Microsoft\Edge" "BackgroundModeEnabled" 0
# Edge auto update off
SetReg "$SW\Policies\Microsoft\EdgeUpdate\Update{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}" "Update" 0
SetReg "$SW\Policies\Microsoft\EdgeUpdate" "UpdateDefault" 0
SetReg "$SW\Policies\Microsoft\EdgeUpdate" "DisableAutoUpdateChecksCheckboxValue" 1

# ---- UAC: "never notify" (EnableLUA stays 1 so Store/UWP keeps working)
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\System" "ConsentPromptBehaviorAdmin" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\System" "PromptOnSecureDesktop" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\System" "EnableInstallerDetection" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\System" "EnableLUA" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\System" "FilterAdministratorToken" 0

# ---- OOBE: allow local account, skip network requirement
SetReg "$SW\Microsoft\Windows\CurrentVersion\OOBE" "BypassNRO" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\OOBE" "HideOnlineAccountScreens" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\OOBE" "HideWirelessSetupInOOBE" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\OOBE" "DisableVoice" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\OOBE" "PrivacyConsentStatus" 1
# skip "let's finish setting up your device" nags
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-310093Enabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338388Enabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SubscribedContent-338389Enabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SilentInstalledAppsEnabled" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SystemPaneSuggestionsEnabled" 0

# ---- search / cortana / web results
SetReg "$SW\Policies\Microsoft\Windows\Windows Search" "AllowCortana" 0
SetReg "$SW\Policies\Microsoft\Windows\Windows Search" "DisableWebSearch" 1
SetReg "$SW\Policies\Microsoft\Windows\Windows Search" "ConnectedSearchUseWeb" 0
SetReg "$SW\Policies\Microsoft\Windows\Windows Search" "AllowSearchToUseLocation" 0
SetReg "$SW\Policies\Microsoft\Windows\Windows Search" "DisableRemovableDriveIndexing" 1

# ---- power: no hibernation / no fast startup
SetReg "$CS\Control\Session Manager\Power" "HibernateEnabled" 0
SetReg "$CS\Control\Session Manager\Power" "HiberbootEnabled" 0
SetReg "$CS\Control\Power" "HibernateEnabled" 0
SetReg "$CS\Control\Power" "PlatformAoAcOverride" 0

# ---- time service: use China NTP
SetReg "$CS\Services\W32Time\Parameters" "NtpServer" "ntp.aliyun.com,0x9 ntp1.aliyun.com,0x9 ntp.tencent.com,0x9" "String"
SetReg "$CS\Services\W32Time\Parameters" "Type" "NTP" "String"
SetReg "$CS\Services\W32Time\TimeProviders\NtpClient" "Enabled" 1
SetReg "$CS\Services\W32Time\TimeProviders\NtpClient" "SpecialPollInterval" 3600
SetReg "$CS\Services\W32Time" "Start" 2
SetReg "$CS\Control\TimeZoneInformation" "TimeZoneKeyName" "China Standard Time" "String"
SetReg "$CS\Control\TimeZoneInformation" "StandardName" "中国标准时间" "String"

# ---- misc: no recent items, no game bar tips, no "meet Windows", no suggestion popups
SetReg "$SW\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_TrackDocs" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0
SetReg "$SW\Microsoft\GameBar" "ShowStartupPanel" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoWindowsTips" 1
SetReg "$SW\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications" 0
SetReg "$SW\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0

# ---- DEFAULT user hive (applies to new accounts)
SetReg "$DF\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSecondsInSystemClock" 1
SetReg "$DF\Control Panel\International" "sShortTime" "HH:mm" "String"
SetReg "$DF\Control Panel\International" "sTimeFormat" "HH:mm:ss" "String"
SetReg "$DF\Control Panel\International" "sShortDate" "yyyy/M/d" "String"
SetReg "$DF\Control Panel\International" "sLongDate" "yyyy'年'M'月'd'日'" "String"
SetReg "$DF\Control Panel\International" "iTime" 1
SetReg "$DF\Control Panel\International" "iTimePrefix" 0
SetReg "$DF\Control Panel\Desktop" "ScreenSaveActive" "0" "String"
SetReg "$DF\Control Panel\Desktop" "MenuShowDelay" "0" "String"
SetReg "$DF\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarSmallIcons" 0
SetReg "$DF\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "EnableBalloonTips" 0
SetReg "$DF\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" 0

# ---- unload
Log "== Unloading hives =="
[gc]::Collect()
reg unload HKLM\OFFSYSTEM   | Out-Null
reg unload HKLM\OFFSOFTWARE | Out-Null
reg unload HKLM\OFFDEFAULT  | Out-Null

# ---------------------------------------------------------------- 5. component cleanup (reset base -> only latest LCU remains)
Log "== Cleanup-Image /ResetBase (drop superseded update backups) =="
dism /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet | Out-Null
Log ("  exit " + $LASTEXITCODE)

# also drop old WinSxS backup left by app removals
dism /Image:"$MountDir" /Cleanup-Image /SPSuperseded /Quiet | Out-Null

# ---------------------------------------------------------------- 6. report languages
Log "== Installed languages after edit =="
dism /Image:"$MountDir" /Get-InstalledLanguages | Select-String -Pattern "Language|zh-CN|en-US" | ForEach-Object { Log ("  " + $_.Line.Trim()) }

# ---------------------------------------------------------------- 7. unmount
Log "Unmounting (commit)"
dism /Unmount-Image /MountDir:"$MountDir" /Commit /Quiet
if ($LASTEXITCODE -ne 0) { throw "Unmount commit failed with $LASTEXITCODE" }
Log "DONE"
