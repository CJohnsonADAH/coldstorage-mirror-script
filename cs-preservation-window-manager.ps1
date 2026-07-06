 $Repos=@( "Masters@2", "Access@7", "Unprocessed", "Masters@4", "Processed", "Masters@10", "Access", "Masters@21", "Unprocessed", "Access@7", "Masters@60", "Processed", "Access", "Masters@365" )
 & wait-maintenanceschedule.ps1 -Label:"Daily Mirror Data Transfer" -Loop -Job:{
    invoke-repositories-daily-mirror-cs.ps1 -Repositories:$Repos -Schedule:$null
    Sleep 10
} -By:"6:00 PM"