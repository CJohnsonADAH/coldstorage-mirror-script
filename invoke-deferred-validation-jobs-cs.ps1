Param(
    $N=1,
    [switch] $Fast=$false
)

$Cmd = $MyInvocation.MyCommand.Name

$DeferredFile = ( & get-deferred-preservation-jobs-cs.ps1 -JobType:REPORT | Select-Object -First 1 )

$jobs = ( & get-deferred-validation-jobs-cs.ps1 -Full:( -Not $Fast ) )
If ( $jobs.Count -gt 0 ) {
    $jobs | Sort-Object { Get-Random } | Select-Object -First:$N |% {
        Write-Progress -Activity "Considering for Validation" -Status $_.FullName
        
        $_ | & invoke-deferred-validation-job-item-cs.ps1 -Fast:$Fast -DeferredFile:$DeferredFile -Cmd:$Cmd
    }
}

