param(
    [Parameter(Mandatory = $true)][string]$WimPath,
    [string]$MountDir = "D:\mount6",
    [string]$LogFile  = "D:\debloat6.log"
)

$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"

function Log { param([string]$m) $l = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Write-Host $l; Add-Content -Path $LogFile -Value $l -Encoding UTF8 }
function SetReg { param([string]$P,[string]$N,$V,[string]$T="DWord") try { if(-not(Test-Path -LiteralPath $P)){New-Item -Path $P -Force|Out-Null}; New-ItemProperty -Path $P -Name $N -Value $V -PropertyType $T -Force|Out-Null } catch {} }

Set-Content -Path $LogFile -Value ("LuoLite v6 deep purge " + (Get-Date)) -Encoding UTF8

Log "== phase 1: v5 chain =="
& "$PSScriptRoot\debloat-v5.ps1" -WimPath $WimPath -MountDir "D:\mount5" -LogFile "D:\debloat5.log"
Log "phase1 done"

if (Test-Path $MountDir) { dism /Unmount-Image /MountDir:"$MountDir" /Discard | Out-Null; Remove-Item -Recurse -Force $MountDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $MountDir | Out-Null
Log "mount phase6"
dism /Mount-Image /ImageFile:"$WimPath" /Index:1 /MountDir:"$MountDir" /Quiet
if ($LASTEXITCODE -ne 0) { throw "mount failed" }

# ---------- 要彻底挖掉的包名关键字 ----------
$patterns = @(
 "GettingStarted","Getstarted","DevHome","MicrosoftTeams","OneDriveSync","OneDrive",
 "WindowsBackup","VoiceAccess","SoundRecorder","QuickAssist","Quick Assist","SecHealthUI",
 "MSPaint","WindowsAlarms","OutlookForWindows","SolitaireCollection","Clipchamp","GamingApp",
 "XboxGamingOverlay","XboxIdentityProvider","XboxSpeechToTextOverlay","Xbox.TCUI",
 "WindowsFeedbackHub","GetHelp","WindowsMaps","WebExperience","WindowsCamera","People",
 "SkypeApp","MicrosoftOfficeHub","Microsoft3DViewer","Print3D","MixedReality","Wallet",
 "YourPhone","ParentalControls","Family","BingNews","BingWeather","ZuneMusic","ZuneVideo",
 "StickyNotes","Todos","Copilot","PowerAutomateDesktop","Microsoft.WindowsTerminal",
 "CorrelationVector","Windows.DevHome","HoloShell","ECApp","Lockscreen"
)

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

# ---------- 1. WindowsApps 包体目录 ----------
$wa = Join-Path $MountDir "Program Files\WindowsApps"
Log "== WindowsApps payload =="
if (Test-Path $wa) {
  Get-ChildItem -LiteralPath $wa -Force | Where-Object { $_.PSIsContainer } | ForEach-Object {
    $n = $_.Name
    foreach ($p in $patterns) {
      if ($n -like "*$p*") {
        if (ForceDel $_.FullName) { Log ("  - WA " + $n) }
        break
      }
    }
  }
}

# ---------- 2. AppRepository 残留注册 ----------
$ar = Join-Path $MountDir "ProgramData\Microsoft\Windows\AppRepository"
Log "== AppRepository =="
if (Test-Path $ar) {
  Get-ChildItem -LiteralPath $ar -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $n = $_.Name
    foreach ($p in $patterns) {
      if ($n -like "*$p*") { if (ForceDel $_.FullName) { Log ("  - AR " + $n) }; break }
    }
  }
  Get-ChildItem -LiteralPath $ar -Force -Filter "*.srd" -ErrorAction SilentlyContinue | ForEach-Object {
    Log ("  srd kept: " + $_.Name)
  }
}

# ---------- 3. 默认用户配置文件里的包注册 ----------
$defPk = Join-Path $MountDir "Users\Default\AppData\Local\Packages"
Log "== Default user packages =="
if (Test-Path $defPk) {
  Get-ChildItem -LiteralPath $defPk -Force | ForEach-Object {
    foreach ($p in $patterns) { if ($_.Name -like "*$p*") { if (ForceDel $_.FullName) { Log ("  - DU " + $_.Name) }; break } }
  }
}

# ---------- 4. AppxAllUserStore 注册表 ----------
Log "== AppxAllUserStore =="
reg load HKLM\OFSW6 (Join-Path $MountDir "Windows\System32\config\SOFTWARE") | Out-Null
foreach ($node in @("Applications","InboxApplications")) {
  $base = "HKLM:\OFSW6\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\$node"
  if (Test-Path $base) {
    Get-ChildItem -Path $base -ErrorAction SilentlyContinue | ForEach-Object {
      foreach ($p in $patterns) {
        if ($_.PSChildName -like "*$p*") {
          try { Remove-Item -LiteralPath $_.PSPath -Recurse -Force -ErrorAction Stop; Log ("  - REG " + $_.PSChildName) } catch {}
          break
        }
      }
    }
  }
}
[gc]::Collect(); Start-Sleep -Seconds 1
reg unload HKLM\OFSW6 | Out-Null

# ---------- 5. 受保护的 exe / msc（强力解锁后删） ----------
$targets = @(
 "Windows\System32\psr.exe","Windows\System32\iscsicpl.exe","Windows\System32\printmanagement.msc",
 "Windows\System32\charmap.exe","Windows\System32\mstsc.exe","Windows\System32\odbcad32.exe",
 "Windows\System32\Narrator.exe","Windows\System32\Magnify.exe","Windows\System32\mspaint.exe",
 "Windows\System32\WindowsBackup.exe","Windows\System32\quickassist.exe","Windows\System32\QuickAssist.exe",
 "Windows\SysWOW64\psr.exe","Windows\SysWOW64\iscsicpl.exe","Windows\SysWOW64\charmap.exe",
 "Windows\SysWOW64\mstsc.exe","Windows\SysWOW64\odbcad32.exe","Windows\SysWOW64\Narrator.exe",
 "Windows\SysWOW64\Magnify.exe","Windows\SysWOW64\mspaint.exe",
 "Windows\System32\WindowsPowerShell\v1.0\powershell_ise.exe",
 "Windows\System32\OneDriveSetup.exe","Windows\SysWOW64\OneDriveSetup.exe",
 "Windows\System32\Speech","Windows\Speech_OneCore","Windows\System32\Speech_OneCore",
 "Windows\System32\WindowsBackup","Windows\System32\VoiceAccess","Windows\System32\ScreenRecorder"
)
Log "== protected files =="
foreach ($t in $targets) {
  $p = Join-Path $MountDir $t
  if (ForceDel $p) { Log ("  del " + $t) }
}

# ---------- 6. 可选功能彻底移除 ----------
Log "== features =="
foreach ($f in @("MicrosoftWindowsPowerShellISE","MicrosoftWindowsPowerShellISE-x86","Printing-XPSServices-Features","Printing-Foundation-Features","Printing-Foundation-InternetPrinting-Client","FaxService","WorkFolders-Client","MicrosoftWindows.Speech.VoiceAccess","MicrosoftWindows.Speech.Narrator")) {
  $r = & dism /Image:"$MountDir" /Disable-Feature /FeatureName:$f /Remove /Quiet /NoRestart 2>&1 | Out-String
  Log ("  " + $f + " -> " + ($r -split "`n" | Select-String -Pattern "错误|Error|操作成功|completed successfully" | Select-Object -First 1))
}

# ---------- 7. 清残留缓存 ----------
foreach ($c in @("Windows\Temp","Windows\Logs","Windows\SoftwareDistribution\Download","ProgramData\Microsoft\Windows\WER")) {
  $p = Join-Path $MountDir $c
  if (Test-Path $p) { Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue | ForEach-Object { ForceDel $_.FullName | Out-Null } }
}

Log "== ResetBase phase6 =="
dism /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet | Out-Null

Log "unmount commit"
dism /Unmount-Image /MountDir:"$MountDir" /Commit /Quiet
if ($LASTEXITCODE -ne 0) { throw "commit failed" }
Log "DONE"
