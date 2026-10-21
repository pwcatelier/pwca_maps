# THES-83: adds the buildings by the water (FORMAT-1.4-BUILDINGS.md, layer kind 9) to the display's map card pack.
# The owner, 2026-10-21: "Have Panoptes roll the buildings and landmarks into its next firmware.  I'm building the files
# now." Offline: it reads only the OpenStreetMap extract already on this PC. Nothing here touches a card or a board,
# and no file that is already built is changed: the newest card pack is only read.
#
# Run it from your OWN PowerShell window (not from inside an app that may restart) and leave the window open:
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\git\pwca_maps\out\_wt-thes83\tools\add_buildings.ps1
# Run it after the land cover and the landmarks have finished: it builds on the newest finished card pack.
#
# Three steps, each with a marker file when it has finished (<Work>\<step>.done):
#   build     passes over the OpenStreetMap extract: the water a rider is on marks the zoom-14 tiles near it, then the
#             buildings that start in those tiles are cut into <Work>\pack\<Name>-buildings*.pmt (tools/build_pack.py
#             --layer buildings; one level, zooms 15 and 16)
#   check     decodes every tile of each file (tools/pmt.py check)
#   assemble  a NEW, complete card folder <Card>\PANOPTES: the base pack's files copied unchanged (each checked against
#             its sha256), the buildings beside them, one MANIFEST.sha256, CURRENT naming the pack <PackId>
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
# run. The steps run at HIGH priority (pass -Normal for normal priority, -Low below normal when the PC is needed).
# The build needs about 2 GiB of disk in <Work> for a while (the bit set of the nodes by the water).
#
# The tools run from a snapshot (a detached git worktree of -Commit under <Repo>\out), so the working tree can be
# edited while the build runs. -Commit defaults to the commit this script's own folder is at.
param(
    [string]$Repo = "C:\git\pwca_maps",
    [string]$Commit = "",
    [string]$Extract = "C:\git\pwca_maps\sources\north-america-latest.osm.pbf",
    [string]$Cards = "C:\temp\panoptes-maps",
    [string]$BasePack = "",
    [string]$Work = "C:\git\pwca_maps\out\na-buildings",
    [string]$Card = "",
    [string]$PackId = "",
    [string]$Name = "north-america",
    [int]$Processes = 4,
    [switch]$Normal,
    [switch]$Low,
    [switch]$IgnoreOthers # a test run beside an add-on that has not finished
)
# "Continue": git and python write ordinary progress to their error stream, which must not end this script; every
# step's exit code is checked instead.
$ErrorActionPreference = "Continue"
$title = "Map buildings"
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
foreach ($need in @($Extract, (Join-Path $BasePack "MANIFEST.sha256"), (Join-Path $BasePack "SOURCES.json"))) {
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
if (-not (Test-Path (Join-Path $snap "tools\build_pack.py"))) {
    git -C $Repo worktree add --detach $snap $Commit 2>&1 | Out-Null
}
if (-not (Select-String -Path (Join-Path $snap "tools\build_pack.py") -Pattern "buildings-full" -SimpleMatch -Quiet)) {
    Write-Host "Could not make the snapshot of the tools at $snap (is $Commit a commit with the buildings?)"
    exit 2
}
$runLog = Join-Path $Work "run.log"
$pack = Join-Path $Work "pack"
$packPartial = Join-Path $Work "pack.partial"
$cardPartial = "$Card.partial"
$packDir = Join-Path $cardPartial "PANOPTES\MAPS\$PackId"
$steps = @("build", "check", "assemble")
$share = @{ "build" = 85; "check" = 10; "assemble" = 5 }
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
        } elseif ($line -match "Traceback|Error|error:|PASSED|^OK|wrote |copying |assembled |water side|buildings|features|done: ") {
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
        $a = @((Join-Path $snap "tools\build_pack.py"), $Extract, $packPartial, "--layer", "buildings", "--name",
               "$Name-buildings", "--processes", "$Processes")
        if ($Low) { $a += "--low-priority" } elseif (-not $Normal) { $a += "--high-priority" }
        $code = Run-Step $step $a
        if ($code -eq 0) { Rename-Item $packPartial "pack" }
    } elseif ($step -eq "check") {
        $files = Get-ChildItem $pack -Filter "*.pmt" -File
        if ($files.Count -lt 1) {
            Say "check: no .pmt in $pack"
            $code = 4
        }
        foreach ($f in $files) {
            if ($code -eq 0) { $code = Run-Step $step @((Join-Path $snap "tools\pmt.py"), "check", $f.FullName) }
        }
    } else {
        if (Test-Path $Card) {
            Say "STOPPED: $Card exists. This script never writes into a card folder that exists: pass -Card with a folder that does not exist."
            $Host.UI.RawUI.WindowTitle = "${title}: STOPPED (the card folder exists)"
            exit 3
        }
        if (Test-Path $cardPartial) { Remove-Item -Recurse -Force $cardPartial }
        $code = Run-Step $step @((Join-Path $snap "tools\assemble_pack.py"), $packDir, $BasePack, $pack)
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
