# checkmk localcheck for 'Veeam Agent for Microsoft Windows FREE' 
#
# It works as a local check and is no full checkmk plugin
# feel free to open issues if you encounter any problems
# Credits: https://github.com/Steffen-MLR/veeam-agent-check

# Set age threshold
$days_warn = 7
$days_crit = 14

# Set Log Dir of Veeam Endpoint Backup

$logdir = "C:\ProgramData\Veeam\Endpoint"

# Get all Log Files of Jobs

$logfiles = Get-ChildItem -Path $logdir -Include Job.*.Backup.*log -Recurse

# Filter out Logs of old Jobs
# Attention: This is only applicable if using the free Version, with only one Job
#            If you want to check multiple Tasks you should adapt this
$logfile = $logfiles | Sort-Object LastAccessTime -Descending | Select-Object -First 1

# Parse the Logfile and Extract the expected information
$logline = (Select-String -Path $logfile -Pattern 'Job session .*' | Select-Object -Last 1).Line
$time = ($logline | Select-String -Pattern "\[\d+.\d+.\d+ \d+:\d+:\d+\]").Matches[0].Value.trimstart("[").trimend("]")

if ($logline | Select-String -Pattern 'Job session is running') {
    $jobstatus = "Running"
} 
elseif ($logline | Select-String -Pattern 'Job session .* has been completed') {
    $jobstatus = ($logline | Select-String -Pattern "status: '[a-zA-Z]*'").Matches[0].Value.Split()[1].trim("'")
}
else {
    $jobstatus = "Unknown"
}

# Map to checkmk/nagios states
switch ($jobstatus) {
    Running { $statusNumber = "0" }
    Success { $statusNumber = "0" }
    Warning { $statusNumber = "1" }
    Failed { $statusNumber = "2" }
}

if (!$time) { 
    $status = "Unknown" 
    $statusNumber = "3" 
}
elseif ((Get-Date($time)) -le ((Get-Date).AddDays(-$days_warn))) {
    $status = "$time, older than $days_warn"
    $statusNumber = "1"
}
elseif ((Get-Date($time)) -le ((Get-Date).AddDays(-$days_crit))) {
    $status = "$time, older than $days_crit"
    $statusNumber = "2"
}
else { 
    $status = "$time"
}

# Output in checkmk localcheck Format
Write-Output "$statusNumber `"VeeamBackup`" - Last Backup State: $jobstatus, $status"