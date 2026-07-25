#requires -Version 3.0
<#
.SYNOPSIS
    CheckMK local check for Broadcom/LSI (Avago) SAS/RAID controllers via StorCLI.

.DESCRIPTION
    Calls storcli64.exe for each controller found on the system and reports, per
    controller:
      - Controller status
      - ROC temperature (with warn/crit thresholds + perfdata)
      - Memory correctable / uncorrectable ECC errors (perfdata)
      - Drive state (Onln / UGood / Rbld / Failed / ...)

.NOTES
    Install:
      Copy this file to the CheckMK Windows agent local-check directory, e.g.
        C:\ProgramData\checkmk\agent\local\check_lsi.ps1

    Thresholds:
      Adjust -TempWarn / -TempCrit below to match your card's datasheet. 55/60C
      are reasonable defaults for SAS3008-class HBAs (official maximum 55C, throttle is usually at ~90C).
#>

param(
    [string]$StorCliPath = '',
    [int]$TempWarn = 55,
    [int]$TempCrit = 60
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-CmkLine {
    param(
        [int]$State,
        [string]$Service,
        [string]$Perf = '-',
        [string]$Text
    )
    if ([string]::IsNullOrWhiteSpace($Perf)) { $Perf = '-' }
    Write-Output "$State `"$Service`" $Perf $Text"
}

function Find-StorCli {
    param([string]$PreferredPath)

    $candidates = @(
        $PreferredPath,
        'C:\Program Files\StorCLI\storcli64.exe',
        '.\storcli64.exe'
    ) | Where-Object { $_ }

    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    $cmd = Get-Command 'storcli64.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

try {
    $storcli = Find-StorCli -PreferredPath $StorCliPath
    if (-not $storcli) {
        Write-CmkLine -State 3 -Service 'LSI StorCLI' -Text 'storcli64.exe not found (checked common install paths and PATH)'
        return
    }

    # How many controllers are present?
    $countRaw = & $storcli 'show' 'ctrlcount' 'nolog' 2>$null
    $ctrlCount = 1
    if ($countRaw) {
        $countText = $countRaw -join "`n"
        if ($countText -match 'Controller Count\s*=\s*(\d+)') {
            $ctrlCount = [int]$Matches[1]
        }
    }
    if ($ctrlCount -lt 1) {
        Write-CmkLine -State 3 -Service 'LSI StorCLI' -Text 'No controllers reported by storcli64.exe'
        return
    }

    $driveLineRegex = '^\s*(?<eid>[^:\s]*):(?<slot>\d+)\s+(?<did>\d+)\s+(?<state>\S+)\s+(?<dg>\S+)\s+(?<size>[\d.]+\s*[KMGT]B)\s+(?<intf>\S+)\s+(?<med>\S+)\s+(?<sed>\S+)\s+(?<pi>\S+)\s+(?<sesz>\S+)\s+(?<model>.+?)\s+(?<sp>\S+)\s*$'

    foreach ($c in 0..($ctrlCount - 1)) {

        $raw = & $storcli "/c$c" 'show' 'all' 'nolog' 2>$null
        if (-not $raw) {
            Write-CmkLine -State 3 -Service "LSI Controller ${c}" -Text "No output querying controller $c"
            continue
        }
        $text = $raw -join "`n"

        # Controller status
        $ctrlStatus = 'UNKNOWN'
        $ctrlModel = 'UNKNOWN'
        $ctrlSerial = 'UNKNOWN'
        $ctrlFirmware = 'UNKNOWN'
        if ($text -match 'Model\s*=\s*(\S+)') { $ctrlModel = $Matches[1] }
        if ($text -match 'Serial Number\s*=\s*(\S+)') { $ctrlSerial = $Matches[1] }
        if ($text -match 'Firmware Version\s*=\s*(\S+)') { $ctrlFirmware = $Matches[1] }
        if ($text -match 'Controller Status\s*=\s*(\S+)') { $ctrlStatus = $Matches[1] }
        $ctrlState = if ($ctrlStatus -eq 'OK') { 0 } else { 2 }
        Write-CmkLine -State $ctrlState -Service "$ctrlModel C${c} Status" -Text "Status: $ctrlStatus, Model: $ctrlModel, Serial Number: $ctrlSerial, Firmware: $ctrlFirmware"

        # ROC temperature
        if ($text -match 'ROC temperature\(Degree Celsius\)\s*=\s*(\d+)') {
            $temp = [int]$Matches[1]
            $tState = 0
            if ($temp -ge $TempCrit) { $tState = 2 }
            elseif ($temp -ge $TempWarn) { $tState = 1 }
            $perf = "temp=$temp;$TempWarn;$TempCrit;0;120"
            Write-CmkLine -State $tState -Service "$ctrlModel C${c} Temperature" -Perf $perf -Text "ROC temperature: ${temp}C (warn/crit $TempWarn/$TempCrit)"
        } else {
            Write-CmkLine -State 3 -Service "$ctrlModel C${c} Temperature" -Text 'ROC temperature not reported by controller'
        }

        # Memory ECC errors
        $memCorr = 0
        $memUncorr = 0
        if ($text -match 'Memory Correctable Errors\s*=\s*(\d+)') { $memCorr = [int]$Matches[1] }
        if ($text -match 'Memory Uncorrectable Errors\s*=\s*(\d+)') { $memUncorr = [int]$Matches[1] }
        $memState = 0
        if ($memUncorr -gt 0) { $memState = 2 }
        elseif ($memCorr -gt 0) { $memState = 1 }
        $memPerf = "correctable=$memCorr;1;;0;|uncorrectable=$memUncorr;;1;0;"
        Write-CmkLine -State $memState -Service "$ctrlModel C${c} Memory Errors" -Perf $memPerf -Text "Correctable: $memCorr, Uncorrectable: $memUncorr"

        # Physical drives
        $driveLines = $raw | Where-Object { $_ -match $driveLineRegex }

        foreach ($line in $driveLines) {
            if ($line -notmatch $driveLineRegex) { continue }
            $slot   = $Matches['slot']
            $eid    = $Matches['eid']
            $dstate = $Matches['state']
            $model  = $Matches['model'].Trim()
            $size   = $Matches['size']

            if ($dstate -match '^(Onln|UGood|Optl)$') { $dStatus = 0 }
            elseif ($dstate -match '^(Rbld|Dgrd|RGrd)$') { $dStatus = 1 }
            elseif ($dstate -match '^(Failed|UBad|Offln|Missing)$') { $dStatus = 2 }
            else { $dStatus = 3}

            # Pull this drive's detailed block
            $blockPattern = "Drive /c$c/s$slot - Detailed Information[\s\S]*?(?=Drive /c$c/s\d+ :|\z)"
            $detail = ''
            if ($text -match $blockPattern) { $detail = $Matches[0] }

            $driveSerial = 'UNKNOWN'
            $driveLinkSpeed = 'UNKNOWN'
            if ($detail -match 'SN\s*=\s*(\S+)') { $driveSerial = $Matches[1] }
            if ($detail -match 'Link Speed\s*=\s*(\S+)') { $driveLinkSpeed = $Matches[1] }

            $eidLabel = if ($eid) { $eid } else { '0' }
            $noteText = "Status: $dState, Slot ${eidLabel}:${slot} [$model, $size, SN $driveSerial], Link: $driveLinkSpeed"

            Write-CmkLine -State $dStatus -Service "$ctrlModel C${c} Drive $driveSerial" -Text $noteText
        }
    }
}
catch {
    Write-CmkLine -State 3 -Service 'LSI StorCLI' -Text "Check failed: $($_.Exception.Message)"
}