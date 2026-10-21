# THES-83: adds the landmarks (lighthouse, dam, lock, swimming beach: symbol classes 5 to 8,
# FORMAT-1.3-SYMBOLS-STREET-NAMES.md 2.2) to the display's map card pack. The owner, 2026-10-21: "Have Panoptes roll
# the buildings and landmarks into its next firmware.  I'm building the files now." Offline: it reads only the
# OpenStreetMap extract already on this PC. Nothing here touches a card or a board, and no file that is already built
# is changed: the newest card pack is only read.
#
# Run it from your OWN PowerShell window (not from inside an app that may restart) and leave the window open:
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\git\pwca_maps\out\_wt-thes83\tools\add_landmarks.ps1
# Run it after the land cover (add_land_cover.ps1) has finished: it builds on the newest finished card pack.
#
# Three steps, each with a marker file when it has finished (<Work>\<step>.done):
#   build     one run over the OpenStreetMap extract: <Work>\pack\<Name>-symbols.pmt, the rider symbols of today AND
#             the landmarks (tools/build_extras.py --only symbols --landmarks --road-fuel)
#   check     reads it back tile by tile and counts the symbols by class (tools/check_extras.py)
#   assemble  a NEW, complete card folder <Card>\PANOPTES: the base pack's files copied unchanged (each checked against
#             its sha256) but for its symbols file, which the new one replaces; one MANIFEST.sha256; CURRENT naming
#             the pack <PackId>
# The same command run again carries on at the first step without a marker; a step that was stopped starts again from
# its beginning. The script never writes into a card folder that exists: it stops and says so.
#
# Base and target: by default the base is the finished card folder under <Cards> with the highest F number
# (card-<date>-F<n>, its PANOPTES\MAPS\CURRENT naming a pack with a MANIFEST.sha256), and the new card folder is
# card-<today>-F<m>, m one above every F number under <Cards> (finished or not) and above 3 (the land cover's F3). The
# choice is written to <Work>\target.txt at the first run and kept by every later run. -BasePack, -Card and -PackId
# set them by hand.
#
# The window shows a percent line for the step in hand and for all steps, and the same in its title. Every line of a
# step goes to <Work>\<step>.log; start, end and the percent lines also go to <Work>\run.log. A failed step stops the
# run. The steps run at HIGH priority (pass -Normal for normal priority).
#
# The tools run from a snapshot (a detached git worktree of -Commit under <Repo>\out), so the working tree can be
# edited while the build runs. -Commit defaults to the commit this script's own folder is at.
param(
    [string]$Repo = "C:\git\pwca_maps",
    [string]$Commit = "",
    [string]$Extract = "C:\git\pwca_maps\sources\north-america-latest.osm.pbf",
    [string]$Cards = "C:\temp\panoptes-maps",
    [string]$BasePack = "",
    [string]$Work = "C:\git\pwca_maps\out\na-landmarks",
    [string]$Card = "",
    [string]$PackId = "",
    [string]$Name = "north-america",
    [int]$Processes = 4,
    [switch]$Normal,
    [switch]$IgnoreOthers # a test run beside an add-on that has not finished
)
# "Continue": git and python write ordinary progress to their error stream, which must not end this script; every
# step's exit code is checked instead.
$ErrorActionPreference = "Continue"
$title = "Map landmarks"
if (-not $Commit) { $Commit = "$(git -C $PSScriptRoot rev-parse HEAD 2>$null)".Trim() }
$short = "$(git -C $Repo rev-parse --short $Commit 2>$null)".Trim()
if (-not $short) {
    Write-Host "No such commit in ${Repo}: $Commit"
    exit 2
}
# Another add-on's run that has not finished: its card would leave this one out, or this one would leave it out.
foreach ($other in @("na-land", "na-landmarks", "na-buildings")) {
    $dir = Join-Path $Repo "out\$other"
    if (-not $IgnoreOthers -and $dir -ne $Work -and (Test-Path (Join-Path $dir "run.log")) -and -not (Test-Path (Join-Path $dir "assemble.done"))) {
        Write-Host "STOPPED: the add-on in $dir has not finished (no assemble.done). Finish it first (its own command carries on where it stopped), then run this one."
        exit 2
    }
}
New-Item -ItemType Directory -Force $Work | Out-Null
$target = Join-Path $Work "target.txt"
if (Test-Path $target) {
    $t = Get-Content $target
    if (-not $BasePack) { $BasePack = $t[0] }
    if (-not $Card) { $Card = $t[1] }
    if (-not $PackId) { $PackId = $t[2] }
}
if (-not $BasePack -or -not $Card -or -not $PackId) {
    $best = $null
    $top = 3
    foreach ($d in Get-ChildItem $Cards -Directory -Filter "card-*" -ErrorAction SilentlyContinue) {
        if ($d.Name -notmatch "-F(\d+)(\.partial)?$") { continue }
        $n = [int]$Matches[1]
        if ($n -gt $top) { $top = $n }
        if ($Matches[2]) { continue }
        $cur = Join-Path $d.FullName "PANOPTES\MAPS\CURRENT"
        if (-not (Test-Path $cur)) { continue }
        $id = (Get-Content $cur -TotalCount 1).Trim()
        $dir = Join-Path $d.FullName "PANOPTES\MAPS\$id"
        if ((Test-Path (Join-Path $dir "MANIFEST.sha256")) -and ($null -eq $best -or $n -gt $best.N)) {
            $best = @{ N = $n; Dir = $dir; Id = $id }
        }
    }
    if (-not $BasePack) {
        if ($null -eq $best) {
            Write-Host "No finished card folder under $Cards (card-<date>-F<n>\PANOPTES\MAPS\CURRENT): pass -BasePack"
            exit 2
        }
        $BasePack = $best.Dir
    }
    $m = $top + 1
    if (-not $PackId) { $PackId = ((Split-Path -Leaf $BasePack) -replace "-F\d+$", "") + "-F$m" }
    if (-not $Card) { $Card = Join-Path $Cards ("card-{0}-F{1}" -f (Get-Date -Format "yyyy-MM-dd"), $m) }
}
foreach ($need in @($Extract, (Join-Path $BasePack "MANIFEST.sha256"), (Join-Path $BasePack "SOURCES.json"),
                    (Join-Path $BasePack "$Name-symbols.pmt"))) {
    if (-not (Test-Path $need)) {
        Write-Host "Missing: $need"
        exit 2
    }
}
Set-Content -Path $target -Value @($BasePack, $Card, $PackId) -Encoding ascii
& python -c "import numpy" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "python with numpy is needed (the earlier map builds used the same)"
    exit 2
}
$snap = Join-Path $Repo "out\_tools-$short"
if (-not (Test-Path (Join-Path $snap "tools\build_extras.py"))) {
    git -C $Repo worktree add --detach $snap $Commit 2>&1 | Out-Null
}
if (-not (Select-String -Path (Join-Path $snap "tools\build_extras.py") -Pattern "--landmarks" -SimpleMatch -Quiet) -or
    -not (Select-String -Path (Join-Path $snap "tools\assemble_pack.py") -Pattern "--replace" -SimpleMatch -Quiet)) {
    Write-Host "Could not make the snapshot of the tools at $snap (is $Commit a commit with the landmarks?)"
    exit 2
}
$runLog = Join-Path $Work "run.log"
$pack = Join-Path $Work "pack"
$packPartial = Join-Path $Work "pack.partial"
$cardPartial = "$Card.partial"
$packDir = Join-Path $cardPartial "PANOPTES\MAPS\$PackId"
$steps = @("build", "check", "assemble")
$share = @{ "build" = 85; "check" = 5; "assemble" = 10 }
$doneShare = 0
function Say([string]$text) {
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $text
    Write-Host $line
    Add-Content -Path $runLog -Value $line -Encoding utf8
}
function Run-Step([string]$step, [string[]]$stepArgs) {
    $log = Join-Path $Work "$step.log"
    if (Test-Path $log) { Remove-Item $log }
    & python -u @stepArgs 2>&1 | ForEach-Object {
        $line = "$_"
        Add-Content -Path $log -Value $line -Encoding utf8
        if ($line -match "PROGRESS (\d+)% of this build \((.*)\)") {
            $pct = [int]$Matches[1]
            $overall = [int]($script:doneShare + $share[$step] * $pct / 100)
            Say ("{0}: {1}%   all steps: {2}%   ({3})" -f $step, $pct, $overall, $Matches[2])
            $Host.UI.RawUI.WindowTitle = "${title}: all $overall% - $step $pct%"
        } elseif ($line -match "Traceback|Error|error:|PASSED|SYMBOLS|^\s+zooms |wrote |copying |replaces |assembled |symbols: |class ") {
            Say ("{0}: {1}" -f $step, $line)
        }
    }
    return $LASTEXITCODE
}
Say ("START (tools at {0}; extract {1}; base pack {2}; work folder {3}; new card folder {4}, pack {5})" -f $short, $Extract, $BasePack, $Work, $Card, $PackId)
foreach ($step in $steps) {
    $marker = Join-Path $Work "$step.done"
    if (Test-Path $marker) {
        Say "${step}: finished in an earlier run ($((Get-Content $marker -TotalCount 1))); not repeated"
        $doneShare += $share[$step]
        continue
    }
    Say "${step}: start"
    $code = 0
    if ($step -eq "build") {
        foreach ($old in @($packPartial, $pack)) {
            if (Test-Path $old) { Remove-Item -Recurse -Force $old }
        }
        $a = @((Join-Path $snap "tools\build_extras.py"), $Extract, $packPartial, "--name", $Name, "--only", "symbols",
               "--landmarks", "--road-fuel", "--processes", "$Processes")
        if (-not $Normal) { $a += "--high-priority" }
        $code = Run-Step $step $a
        if ($code -eq 0) { Rename-Item $packPartial "pack" }
    } elseif ($step -eq "check") {
        $code = Run-Step $step @((Join-Path $snap "tools\check_extras.py"), $pack, "--json", (Join-Path $Work "check.json"))
    } else {
        if (Test-Path $Card) {
            Say "STOPPED: $Card exists. This script never writes into a card folder that exists: pass -Card with a folder that does not exist."
            $Host.UI.RawUI.WindowTitle = "${title}: STOPPED (the card folder exists)"
            exit 3
        }
        if (Test-Path $cardPartial) { Remove-Item -Recurse -Force $cardPartial }
        $code = Run-Step $step @((Join-Path $snap "tools\assemble_pack.py"), "--replace", $packDir, $BasePack, $pack)
        if ($code -eq 0) {
            # CURRENT as the packs before it have it: the pack's name and one line feed.
            [IO.File]::WriteAllText((Join-Path $cardPartial "PANOPTES\MAPS\CURRENT"), "$PackId`n", (New-Object Text.ASCIIEncoding))
            Rename-Item $cardPartial (Split-Path -Leaf $Card)
        }
    }
    Say "${step}: exit $code"
    if ($code -ne 0) {
        Say "STOPPED: the $step step failed. See $(Join-Path $Work "$step.log"). The same command starts this step again."
        $Host.UI.RawUI.WindowTitle = "${title}: FAILED at $step"
        exit $code
    }
    Set-Content -Path $marker -Value ("{0} tools {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $short) -Encoding ascii
    $doneShare += $share[$step]
}
$final = Join-Path $Card "PANOPTES\MAPS\$PackId"
$bytes = (Get-ChildItem $final -File | Measure-Object Length -Sum).Sum
Say ("ALL STEPS FINISHED. The new card folder: {0} (copy its folder PANOPTES onto the card's top level). Pack {1}: {2} files, {3:N0} bytes." -f $Card, $PackId, (Get-ChildItem $final -File).Count, $bytes)
$Host.UI.RawUI.WindowTitle = "${title}: FINISHED"
