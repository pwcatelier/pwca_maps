# THES-83: adds the land cover (FORMAT.md 7.7, layer kind 6) to the display's map card pack. The owner, 2026-10-21:
# "have Panoptes and Branding prep this, then provide me the powershell command so I can run it offline to build the
# map files." Offline: it reads only the OpenStreetMap extract already on this PC. Nothing here touches a card or a
# board, and no file that is already built is changed: today's pack (F2: water, roads, names, rider symbols, street
# names) is only read.
#
# Run it from your OWN PowerShell window (not from inside an app that may restart) and leave the window open:
#   powershell -NoProfile -ExecutionPolicy Bypass -File C:\git\pwca_maps\out\_wt-thes83\tools\add_land_cover.ps1
#
# Three steps, each with a marker file when it has finished (<Work>\<step>.done):
#   build     one run over the OpenStreetMap extract: <Work>\pack\<Name>-land-01.pmt, -02 ... (tools/build_pack.py
#             --layer land; a layer is cut into files under 2 GiB, as the base pack's north-america-01..03.pmt are)
#   check     decodes every tile of every .pmt of it, one file after the other (tools/pmt.py check); the first that
#             fails stops the step
#   assemble  a NEW, complete card folder <Card>\PANOPTES: today's files copied unchanged (each checked against its
#             sha256), the land cover beside them, one MANIFEST.sha256, CURRENT naming the pack <PackId>
# The same command run again carries on at the first step without a marker; a step that was stopped starts again from
# its beginning. The script never writes into a card folder that exists: it stops and says so.
#
# The window shows a percent line for the step in hand and for all steps, and the same in its title. Every line of a
# step goes to <Work>\<step>.log; start, end and the percent lines also go to <Work>\run.log. A failed step stops the
# run. The steps run at HIGH priority (pass -Normal for normal priority, -Low below normal when the PC is needed).
#
# The tools run from a snapshot (a detached git worktree of -Commit under <Repo>\out), so the working tree can be
# edited while the build runs. -Commit defaults to the commit this script's own folder is at.
param(
    [string]$Repo = "C:\git\pwca_maps",
    [string]$Commit = "",
    [string]$Extract = "C:\git\pwca_maps\sources\north-america-latest.osm.pbf",
    [string]$BasePack = "C:\temp\panoptes-maps\card-2026-10-06-F2\PANOPTES\MAPS\NA-20260924-F2",
    [string]$Work = "C:\git\pwca_maps\out\na-land",
    [string]$Card = "C:\temp\panoptes-maps\card-2026-10-21-F3",
    [string]$PackId = "NA-20260924-F3",
    [string]$Name = "north-america",
    [switch]$Normal,
    [switch]$Low
)
# "Continue": git and python write ordinary progress to their error stream, which must not end this script; every
# step's exit code is checked instead.
$ErrorActionPreference = "Continue"
if (-not $Commit) { $Commit = "$(git -C $PSScriptRoot rev-parse HEAD 2>$null)".Trim() }
$short = "$(git -C $Repo rev-parse --short $Commit 2>$null)".Trim()
if (-not $short) {
    Write-Host "No such commit in ${Repo}: $Commit"
    exit 2
}
foreach ($need in @($Extract, (Join-Path $BasePack "MANIFEST.sha256"), (Join-Path $BasePack "SOURCES.json"))) {
    if (-not (Test-Path $need)) {
        Write-Host "Missing: $need"
        exit 2
    }
}
& python -c "import numpy" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "python with numpy is needed (the earlier map builds used the same)"
    exit 2
}
$snap = Join-Path $Repo "out\_tools-$short"
if (-not (Test-Path (Join-Path $snap "tools\build_pack.py"))) {
    git -C $Repo worktree add --detach $snap $Commit 2>&1 | Out-Null
}
if (-not (Select-String -Path (Join-Path $snap "tools\pmt.py") -Pattern "KIND_LAND" -Quiet)) {
    Write-Host "Could not make the snapshot of the tools at $snap (is $Commit a commit with the land cover?)"
    exit 2
}
New-Item -ItemType Directory -Force $Work | Out-Null
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
function Run-Step([string]$step, [string[]]$stepArgs, [switch]$Append) {
    $log = Join-Path $Work "$step.log"
    if ((Test-Path $log) -and -not $Append) { Remove-Item $log }
    & python -u @stepArgs 2>&1 | ForEach-Object {
        $line = "$_"
        Add-Content -Path $log -Value $line -Encoding utf8
        if ($line -match "PROGRESS (\d+)% of this build \((.*)\)") {
            $pct = [int]$Matches[1]
            $overall = [int]($script:doneShare + $share[$step] * $pct / 100)
            Say ("{0}: {1}%   all steps: {2}%   ({3})" -f $step, $pct, $overall, $Matches[2])
            $Host.UI.RawUI.WindowTitle = "Map land cover: all $overall% - $step $pct%"
        } elseif ($line -match "Traceback|Error|error:|PASSED|^OK|wrote |copying |assembled |areas|tiles") {
            Say ("{0}: {1}" -f $step, $line)
        }
    }
    return $LASTEXITCODE
}
Say ("START (tools at {0}; extract {1}; today's pack {2}; work folder {3}; new card folder {4}, pack {5})" -f $short, $Extract, $BasePack, $Work, $Card, $PackId)
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
        $a = @((Join-Path $snap "tools\build_pack.py"), $Extract, $packPartial, "--layer", "land", "--name", "$Name-land")
        if ($Low) { $a += "--low-priority" } elseif (-not $Normal) { $a += "--high-priority" }
        $code = Run-Step $step $a
        if ($code -eq 0) { Rename-Item $packPartial "pack" }
    } elseif ($step -eq "check") {
        # Every file of the layer (2026-10-21: the North America land cover came out as two parts, -01 and -02, and a
        # check that wanted exactly one file stopped the run). At least one; the first that fails stops the step.
        $land = @(Get-ChildItem $pack -Filter "*.pmt" -File | Sort-Object Name)
        if ($land.Count -lt 1) {
            Say "check: no .pmt in $pack"
            $code = 4
        } else {
            $log = Join-Path $Work "check.log"
            if (Test-Path $log) { Remove-Item $log }
            foreach ($f in $land) {
                Say ("check: {0} ({1:N0} bytes), file {2} of {3}" -f $f.Name, $f.Length, ([array]::IndexOf($land, $f) + 1), $land.Count)
                $code = Run-Step $step @((Join-Path $snap "tools\pmt.py"), "check", $f.FullName) -Append
                if ($code -ne 0) {
                    Say "check: $($f.Name) failed"
                    break
                }
            }
        }
    } else {
        if (Test-Path $Card) {
            Say "STOPPED: $Card exists. This script never writes into a card folder that exists: pass -Card with a folder that does not exist."
            $Host.UI.RawUI.WindowTitle = "Map land cover: STOPPED (the card folder exists)"
            exit 3
        }
        if (Test-Path $cardPartial) { Remove-Item -Recurse -Force $cardPartial }
        $code = Run-Step $step @((Join-Path $snap "tools\assemble_pack.py"), $packDir, $BasePack, $pack)
        if ($code -eq 0) {
            # CURRENT as the pack of today has it: the pack's name and one line feed.
            [IO.File]::WriteAllText((Join-Path $cardPartial "PANOPTES\MAPS\CURRENT"), "$PackId`n", (New-Object Text.ASCIIEncoding))
            Rename-Item $cardPartial (Split-Path -Leaf $Card)
        }
    }
    Say "${step}: exit $code"
    if ($code -ne 0) {
        Say "STOPPED: the $step step failed. See $(Join-Path $Work "$step.log"). The same command starts this step again."
        $Host.UI.RawUI.WindowTitle = "Map land cover: FAILED at $step"
        exit $code
    }
    Set-Content -Path $marker -Value ("{0} tools {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $short) -Encoding ascii
    $doneShare += $share[$step]
}
$final = Join-Path $Card "PANOPTES\MAPS\$PackId"
$bytes = (Get-ChildItem $final -File | Measure-Object Length -Sum).Sum
Say ("ALL STEPS FINISHED. The new card folder: {0} (copy its folder PANOPTES onto the card's top level). Pack {1}: {2} files, {3:N0} bytes." -f $Card, $PackId, (Get-ChildItem $final -File).Count, $bytes)
$Host.UI.RawUI.WindowTitle = "Map land cover: FINISHED"
