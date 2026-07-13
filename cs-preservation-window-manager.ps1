 $Repos=@( "Unprocessed@4", "Processed@4", "Access", "Unprocessed", "Processed" )
 & wait-maintenanceschedule.ps1 -Label:"Daily Mirror Data Transfer" -Loop -Job:{
    invoke-repositories-daily-mirror-cs.ps1 -Repositories:$Repos -Schedule:$null
    Sleep 10
} -By:"5:30 PM"