# checkmk localcheck for Syncthing
# 
# It works as a local check and is no full checkmk plugin
# feel free to open issues if you encounter any problems
# 

$status = "Failed"
$statusNumber = "2"

$status = (Invoke-RestMethod "http://localhost:8384/rest/noauth/health").status


# Map to checkmk/nagios states
switch ($status) 
{
    OK {$statusNumber = "0"}
}

# Output in checkmk localcheck Format
Write-Output "$statusNumber `"Syncthing`" - Local Syncthing service $status"