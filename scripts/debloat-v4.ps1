param(
    [Parameter(Mandatory = $true)][string]$WimPath,
    [string]$MountDir = "D:\mount4",
    [string]$LogFile  = "D:\debloat4.log"
)

$ErrorActionPreference = "Continue"
$ProgressPreference    = "SilentlyContinue"

function Log {
    param([string]$msg)
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

Set-Content -Path $LogFile -Value ("LuoLite ISO v4 start " + (Get-Date)) -Encoding UTF8

# ============ phase 1+2: v3 (= v2 base debloat + winre/print/winre extras)
Log "== phase 1+2: debloat-v3 =="
& "$PSScriptRoot\debloat-v3.ps1" -WimPath $WimPath -MountDir "D:\mount3" -LogFile "D:\debloat3.log"
Log "phase 1+2 done"

# ============ phase 3: final cut for this request
if (Test-Path $MountDir) {
    dism /Unmount-Image /MountDir:"$MountDir" /Discard | Out-Null
    Remove-Item -Recurse -Force $MountDir -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path $MountDir | Out-Null
Log "mounting phase 3"
dism /Mount-Image /ImageFile:"$WimPath" /Index:1 /MountDir:"$MountDir" /Quiet
if ($LASTEXITCODE -ne 0) { throw "mount failed $LASTEXITCODE" }

# ---- extra appx removals requested this round
$extraApps = @(
    "Microsoft.Windows.Backup","Microsoft.Backup",
    "Microsoft.Windows.VoiceAccess","Microsoft.VoiceAccess",
    "Microsoft.Windows.Troubleshoot","Microsoft.GetHelp",
    "Microsoft.Windows.Photos.PreviewApp"
)
foreach ($pat in $extraApps) {
    Get-AppxProvisionedPackage -Path $MountDir -ErrorAction SilentlyContinue |
        Where-Object { $_.PackageName -like "*$pat*" } | ForEach-Object {
            Log ("  removing appx " + $_.PackageName)
            try { Remove-AppxProvisionedPackage -Path $MountDir -PackageName $_.PackageName -ErrorAction Stop | Out-Null }
            catch { Log ("    [WARN] " + $_.Exception.Message) }
        }
}

# ---- verify what we keep
Log "== kept packages check =="
Get-AppxProvisionedPackage -Path $MountDir -ErrorAction SilentlyContinue |
    Where-Object { $_.PackageName -match "Photos|Notepad|ScreenSketch|WebExperience|WindowsStore|Paint" } |
    ForEach-Object { Log ("  KEEP? " + $_.PackageName) }

# ---- file level: paint, magnifier, narrator, backup payload
foreach ($f in @(
    "Windows\System32\mspaint.exe",
    "Windows\System32\Magnify.exe",
    "Windows\System32\Narrator.exe",
    "Windows\System32\WindowsBackup.exe"
)) {
    $p = Join-Path $MountDir $f
    if (Test-Path $p) { try { Remove-Item -Force $p -ErrorAction Stop; Log ("  del " + $f) } catch { } }
}
foreach ($d in @("Windows\System32\WindowsBackup","Program Files\WindowsApps")) {
    if ($d -eq "Program Files\WindowsApps") { continue }
    $p = Join-Path $MountDir $d
    if (Test-Path $p) { try { Remove-Item -Recurse -Force $p -ErrorAction Stop; Log ("  del dir " + $d) } catch { } }
}

# ---- speech payload: force delete with takeown/icacls
foreach ($p in @("Windows\Speech","Windows\Speech_OneCore")) {
    $full = Join-Path $MountDir $p
    if (Test-Path $full) {
        & takeown /f "$full" /r /d y 2>$null | Out-Null
        & icacls "$full" /grant "*S-1-5-32-544:(F)" /t /q 2>$null | Out-Null
        try {
            $mb = [math]::Round(((Get-ChildItem $full -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum)/1MB,1)
            Remove-Item -Recurse -Force $full -ErrorAction Stop
            Log ("removed " + $p + " (" + $mb + " MB)")
        } catch { Log ("  [WARN] still locked: " + $p) }
    }
}

# ---- registry: block re-download of removed apps, disable backup/recall
$softReg = Join-Path $MountDir "Windows\System32\config\SOFTWARE"
$sysReg  = Join-Path $MountDir "Windows\System32\config\SYSTEM"
reg load HKLM\OFSW4 $softReg | Out-Null
reg load HKLM\OFSYS4 $sysReg | Out-Null
$SW4 = "HKLM:\OFSW4"
foreach ($pair in @(
    @("$SW4\Policies\Microsoft\Windows\WindowsBackup","DisableBackup",1),
    @("$SW4\Microsoft\Windows\CurrentVersion\WindowsBackup","DisableBackup",1),
    @("$SW4\Policies\Microsoft\Windows\CloudContent","DisableTailoredExperiencesWithDiagnosticData",1),
    @("$SW4\Microsoft\Windows\CurrentVersion\Explorer\Advanced","ShowCopilotButton",0)
)) {
    try {
        $path = $pair[0]; $name = $pair[1]; $val = $pair[2]
        if (-not (Test-Path -LiteralPath $path)) { New-Item -Path $path -Force | Out-Null }
        New-ItemProperty -Path $path -Name $name -Value $val -PropertyType DWord -Force | Out-Null
    } catch { }
}
[gc]::Collect()
reg unload HKLM\OFSW4  | Out-Null
reg unload HKLM\OFSYS4 | Out-Null

Log "== ResetBase (phase 3) =="
dism /Image:"$MountDir" /Cleanup-Image /StartComponentCleanup /ResetBase /Quiet | Out-Null
Log ("  exit " + $LASTEXITCODE)

Log "unmount commit (phase 3)"
dism /Unmount-Image /MountDir:"$MountDir" /Commit /Quiet
if ($LASTEXITCODE -ne 0) { throw "commit failed $LASTEXITCODE" }
Log "DONE"
