# 装完系统后一次性运行的优化脚本（右键“使用 PowerShell 运行”或用管理员 PowerShell 执行）
# 作用：处理只有进入系统后才能生效的个性化项（任务栏、电源、卓越模式、Edge 自启、管理员账户等）

$ErrorActionPreference = "Continue"

Write-Host "== 1. 开启内置 Administrator（相当于超级管理员） =="
net user Administrator /active:yes
net user Administrator *

Write-Host "== 2. 卓越模式（Ultimate Performance）调出来并启用 =="
powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61
$up = (powercfg -list | Select-String "卓越性能|Ultimate").ToString()
if ($up -match "([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})") {
    powercfg -setactive $Matches[1]
}

Write-Host "== 3. 永不熄屏 / 永不休眠 / 永不断电 =="
powercfg -change -monitor-timeout-ac 0
powercfg -change -monitor-timeout-dc 0
powercfg -change -standby-timeout-ac 0
powercfg -change -standby-timeout-dc 0
powercfg -change -hibernate-timeout-ac 0
powercfg -change -hibernate-timeout-dc 0
powercfg -change -disk-timeout-ac 0
powercfg -change -disk-timeout-dc 0
powercfg -h off
# USB 设备不自动断电
powercfg -setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg -setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
powercfg -setactive SCHEME_CURRENT

Write-Host "== 4. 任务栏时钟：显示秒 + 24 小时制 =="
$adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
Set-ItemProperty $adv -Name ShowSecondsInSystemClock -Value 1 -Type DWord
$intl = "HKCU:\Control Panel\International"
Set-ItemProperty $intl -Name sShortTime  -Value "HH:mm"    -Type String
Set-ItemProperty $intl -Name sTimeFormat -Value "HH:mm:ss" -Type String
Set-ItemProperty $intl -Name iTime       -Value 1          -Type String
Set-ItemProperty $intl -Name sShortDate  -Value "yyyy/M/d" -Type String
# 让任务栏日期区域带上星期（可能需重启资源管理器）
Set-ItemProperty $intl -Name sLongDate   -Value "yyyy'年'M'月'd'日'" -Type String

Write-Host "== 5. 关闭 Edge 开机自启 / 后台常驻 =="
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "MicrosoftEdgeAutoLaunch*" -ErrorAction SilentlyContinue
Get-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Property |
    Where-Object { $_ -like "*EdgeAutoLaunch*" } |
    ForEach-Object { Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name $_ }
$edgePol = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
if (!(Test-Path $edgePol)) { New-Item $edgePol -Force | Out-Null }
Set-ItemProperty $edgePol -Name StartupBoostEnabled   -Value 0 -Type DWord
Set-ItemProperty $edgePol -Name BackgroundModeEnabled -Value 0 -Type DWord

Write-Host "== 6. 关闭剩余 UWP（当前用户） =="
$rm = @("Clipchamp.Clipchamp","Microsoft.WindowsCommunicationsApps","Microsoft.MicrosoftStickyNotes",
"Microsoft.WindowsCamera","Microsoft.WindowsAlarms","Microsoft.Copilot","Microsoft.Todos",
"Microsoft.BingWeather","Microsoft.YourPhone","Microsoft.GamingApp","Microsoft.XboxGamingOverlay",
"Microsoft.XboxIdentityProvider","Microsoft.XboxSpeechToTextOverlay","Microsoft.Xbox.TCUI",
"Microsoft.MicrosoftOfficeHub","Microsoft.GetHelp","Microsoft.Getstarted","Microsoft.WindowsFeedbackHub",
"Microsoft.BingNews","Microsoft.ZuneMusic","Microsoft.ZuneVideo","Microsoft.People",
"Microsoft.MicrosoftSolitaireCollection","Microsoft.SkypeApp","Microsoft.Teams","Microsoft.OutlookForWindows",
"Microsoft.Microsoft3DViewer","Microsoft.Print3D","Microsoft.MixedReality.Portal","Microsoft.Wallet",
"Microsoft.OneConnect","Microsoft.DevHome","Microsoft.549981C3F5F10")
foreach ($n in $rm) {
    Get-AppxPackage -AllUsers -Name "*$n*" | ForEach-Object {
        Write-Host "  移除 $($_.Name)"
        Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue
    }
}

Write-Host "== 7. Defender 实时保护关闭 =="
Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction SilentlyContinue
Set-MpPreference -DisableIOAVProtection $true -ErrorAction SilentlyContinue
Set-MpPreference -MAPSReporting 0 -ErrorAction SilentlyContinue
Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue

Write-Host "== 8. 时间服务器改为国内（阿里云 / 腾讯） =="
w32tm /config /manualpeerlist:"ntp.aliyun.com,0x9 ntp1.aliyun.com,0x9 ntp.tencent.com,0x9" /syncfromflags:manual /update
Restart-Service w32time -ErrorAction SilentlyContinue
w32tm /resync /force

Write-Host "== 9. 彻底关闭 Windows 更新相关服务 =="
foreach ($s in "wuauserv","UsoSvc","WaaSMedicSvc","DoSvc") {
    sc.exe config $s start= disabled | Out-Null
    Stop-Service $s -Force -ErrorAction SilentlyContinue
}

Write-Host "== 10. 重启资源管理器，让设置立即生效 =="
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "全部完成。建议重启一次。"
pause
