# checkmk localcheck for 'Veeam Agent for Microsoft Windows FREE' 
# Works as a local check only
# Original idea: https://github.com/Steffen-MLR/veeam-agent-check

# Set age threshold
$days_warn = 7
$days_crit = 14

# Set Log Dir of Veeam Endpoint Backup
$logdir = "C:\ProgramData\Veeam\Endpoint"

# Get all Log Files of Jobs
$logfiles = Get-ChildItem -Path "$logdir" -Include Job.*.Backup.*log -Recurse -ErrorAction SilentlyContinue

if (-not $logfiles) { 
    $statusMessage = "No log files found in $logdir"
    $statusNumber = "3"
}
else {
    # Filter out Logs of old Jobs
    # Attention: This is only applicable if using the free Version, with only one Job
    $logfile = $logfiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    # Parse the Logfile and Extract the expected information
    $loglineMatch = Select-String -Path "$logfile" -Pattern 'Job session .*' | Select-Object -Last 1
    $logline = $loglineMatch.Line

    if (-not $logline) { 
        $statusMessage = "No job session found in $logfile"
        $statusNumber = "3"
    }
    else {
        if ($logline | Select-String -Pattern 'Job session is running') {
            $statusNumber = "0"
            $jobstatus = "Running"
        } 
        elseif ($logline | Select-String -Pattern 'Job session .* has been completed') {
            $statusMatch = $logline | Select-String -Pattern "status: '([a-zA-Z]*)'"
            if ($statusMatch) { 
                $jobstatus = $statusMatch.Matches[0].Groups[1].Value
            }
            else {
                $jobstatus = "Unknown"
            }

            # Map to checkmk/nagios states
            switch ($jobstatus) {
                Success { $statusNumber = "0" }
                Warning { $statusNumber = "1" }
                Failed { $statusNumber = "2" }
                Default { $statusNumber = "3" }
            }
        }
        else {
            $statusNumber = "3"
            $jobstatus = "Unknown"
            $statusMessage = "No job session found in $logfile"
        }

        # Find the time of the last backup
        $timeMatch = $logline | Select-String -Pattern "\b(\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2})\b"
        if ($timeMatch) {
            $time = $timeMatch.Matches[0].Groups[1].Value
            $jobage = (Get-Date) - (Get-Date $time)
            
            if ($jobage.Days -ge $days_crit) {
                $statusMessage = "$time, older than $days_crit day(s)"
                $statusNumber = "2"
            } elseif ($jobage.Days -ge $days_warn) {
                $statusMessage = "$time, older than $days_warn day(s)"
                $statusNumber = "1"
            } else {
                $statusMessage = "$time"
            }
        } else {
            $statusMessage = "Job time is unknown"
            $statusNumber = "3"
        }
    }
}

# Output in checkmk localcheck Format
Write-Output "$statusNumber `"VeeamBackup`" - Last Backup State: $jobstatus, $statusMessage"
exit $statusNumber