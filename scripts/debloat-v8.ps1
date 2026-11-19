param(
    [Parameter(Mandatory = $true)][string]$WimPath,
    [string]$MountDir = "D:\mount8",
    [string]$LogFile  = "D:\debloat8.log"
)

$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"
function Log { param([string]$m) $l = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m; Write-Host $l; Add-Content -Path $LogFile -Value $l -Encoding UTF8 }

Set-Content -Path $LogFile -Value ("LuoMicro v8 ISO " + (Get-Date)) -Encoding UTF8

Log "== phase 1: v7 chain =="
& "$PSScriptRoot\debloat-v7.ps1" -WimPath $WimPath -MountDir "D:\mount7" -LogFile "D:\debloat7.log"
Log "phase1 done"

if (Test-Path $MountDir) { dism /Unmount-Image /MountDir:"$MountDir" /Discard | Out-Null; Remove-Item -Recurse -Force $MountDir -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $MountDir | Out-Null
Log "mount phase8"
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

# ---- 输入法（中文拼音）整套移除，压体积（后期可自行装第三方输入法）
Log "== IME removal =="
foreach ($p in @("Windows\System32\InputMethod\CHS","Windows\System32\InputMethod\SHARED",
 "Windows\System32\InputMethod\JPN","Windows\System32\InputMethod\KOR")) {
  if (ForceDel (Join-Path $MountDir $p)) { Log ("  del " + $p) }
}
foreach ($f in (Get-ChildItem -Path (Join-Path $MountDir "Windows\System32") -Filter "ChsIME*.dll" -ErrorAction SilentlyContinue)) {
  if (ForceDel $f.FullName) { Log ("  del " + $f.Name) }
}

# ---- 字体瘦身：只留中文界面必需 + 少量西文
Log "== fonts =="
$keepFonts = @("msyh","msyhbd","msyhl","simsun","simhei","segoeui","segoeuib","segoeuii","segoeuisl",
 "seguiemj","seguisym","tahoma","arial","arialbd","calibri","consola","consolab","cour","courbd",
 "lucon","malgun","seguibl","segmdl2","seguiicons","marlett","symbol","wingding","micross","msjh")
$fd = Join-Path $MountDir "Windows\Fonts"
if (Test-Path $fd) {
  Get-ChildItem -LiteralPath $fd -File -ErrorAction SilentlyContinue | ForEach-Object {
    $base = $_.BaseName.ToLower()
    $keep = $false
    foreach ($k in $keepFonts) { if ($base -like "$k*") { $keep = $true; break } }
    if (-not $keep) { ForceDel $_.FullName | Out-Null }
  }
}

# ---- 缩略图/壁纸只留一张
Log "== wallpapers =="
$wp = Join-Path $MountDir "Windows\Web\Wallpaper"
if (Test-Path $wp) {
  Get-ChildItem -LiteralPath $wp -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -notmatch "Windows") { ForceDel $_.FullName | Out-Null }
  }
  Get-ChildItem -LiteralPath (Join-Path $wp "Windows") -File -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending | Select-Object -Skip 1 |
    ForEach-Object { ForceDel $_.FullName | Out-Null }
}

# ---- 媒体示例/主题多余内容
foreach ($d in @("Windows\Media","Windows\Web\Screen","Windows\System32\WindowsCodecsRaw",
 "Windows\SystemApps\Microsoft.Windows.SecureAssessment","Windows\SystemApps\Microsoft.Windows.Cortana_cw5n1h2txyewy")) {
  $p = Join-Path $MountDir $d
  if (Test-Path $p -and (Test-Path $p -PathType Container)) { ForceDel $p | Out-Null; Log ("  del " + $d) }
}

Log "== ResetBase phase8 =="
dism /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet | Out-Null
dism /Image:"$MountDir" /Cleanup-Image /SPSuperseded /Quiet | Out-Null

Log "unmount commit"
dism /Unmount-Image /MountDir:"$MountDir" /Commit /Quiet
if ($LASTEXITCODE -ne 0) { throw "commit failed" }
Log "DONE"
