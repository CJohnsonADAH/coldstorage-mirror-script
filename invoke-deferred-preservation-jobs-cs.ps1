Param(
    [switch] $SU=$false,
    [switch] $Verbose=$false,
    [switch] $Scheduled=$false,
    [switch] $Batch=$false,
    [switch] $Debug=$false
)

If ( $Verbose ) {
    $VerbosePreference="Continue"
}
$Interactive = ( -Not $Batch )

#$Verbose = ( $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent )
#$Verbose = $( If ( $Verbose -eq $null ) { $false } Else { $Verbose } )
#$Debug = ( $PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent )
#$Debug = $( If ( $Debug -eq $null ) { $false } Else { $Debug } )

$global:gCSInvokeDeferredPreservationJobsCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gCSInvokeDeferredPreservationJobsCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageUserPrivileges.psm1" )


$Invoc = $MyInvocation
$cmd = $Invoc.MyCommand
If ( -Not ( Test-UserHasNetworkAccess ) ) {
    If ( $SU ) {
        $cmdName = $cmd.Name
        $loc = ( Get-ColdStorageAccessTestPath )
        "[{0}] Unable to acquire network access to {1}" -f $cmdName,$loc | Write-Error
        Exit 255
    }
    Else {
        $retval = ( Invoke-SelfWithNetworkAccess -Invocation:$Invoc )

        Exit $retval
    }
}
Else {
    ( "[{0}] User has network access to {1}; good to go!" -f $cmd.Name,( Get-ColdStorageAccessTestPath ) ) | Write-Verbose
}

If ( $Scheduled -and $Interactive ) {
    $ExecuteTimeout = $null
}
Else {
    $ExecuteTimeout = 60
}

& get-deferred-preservation-jobs-cs.ps1 -Wildcard -Items |% {
    $Destination = ( & get-deferred-preservation-jobs-cs.ps1 -Directory -Mkdir | Select-Object -First 1 | Join-Path -ChildPath ( ".run-{0}" -f ( Get-Date -Format 'yyyyMMdd-HHmmss' ) ) )
    If ( -Not ( Test-Path $Destination ) ) {
        $DestinationItem = ( New-Item -ItemType Directory -Path $Destination )
    }
    Else {
        $DestinationItem = ( Get-Item -LiteralPath $Destination -Force )
    }

    $Original = $_.FullName
    $ScriptName = ( $Destination | Join-Path -ChildPath ( "{0}.ps1" -f ( $_.Name -replace "[^0-9A-Za-z]","_" ) ) )
    Get-Content $_.FullName | Select-Object -Unique | Out-File -LiteralPath $ScriptName
    Remove-Item $_.FullName -Verbose
    Get-ChildItem $Destination -File |? { $_.Name -like "*.ps1" } |% {
        $Script = $_.FullName

        $OK = $false
        $DefaultRetain = 'Y'

        $IsReport = ( $_.Name -match '^(.*)_DEFERRED_REPORT_([0-9]+)_log.*$' )
        
        $IsToBeExecuted = $true
        If ( -Not $IsReport ) {
            "" | Write-Host
            "--- {0} ---" -f ${Script} | Write-Host -ForegroundColor Yellow -BackgroundColor Black
            Get-Content "${Script}" | Write-Host -ForegroundColor Yellow -BackgroundColor Black
            "--- EOF ---" -f ${Script} | Write-Host -ForegroundColor Yellow -BackgroundColor Black
            "" | Write-Host
            $IsToBeExecuted = ( & read-yesfromhost-cs.ps1 -Prompt "Execute ${Script}" -Timeout:$ExecuteTimeout )
            $DefaultDismiss = 'Y'
        }
        Else {
            $DefaultDismiss = 'Y'
        }

        If ( $IsToBeExecuted ) {
            & "${Script}"
            $OK = ( & read-yesfromhost-cs.ps1 -Prompt "Results OK?" -Timeout:600 -DefaultInput:$DefaultDismiss )
        }
        If ( $OK ) {
            $DefaultRetain = 'N'
        }
        $ExecuteTimeout = 60 # after the first interaction, we can use timeouts

        If ( $OK ) {
            Move-Item "${Script}" ( "${Script}" -replace "[.]ps1$",".COMPLETED.txt" ) -Verbose
        }
        ElseIf ( & read-yesfromhost-cs.ps1 -Prompt "Retain ${Original} to run later?" -Timeout:600 -DefaultInput:$DefaultRetain ) {
            Move-Item "${Script}" "${Original}" -Verbose
        }
        Else {
            Remove-Item "${Script}" -Verbose
        }
    }
}
& get-deferred-preservation-jobs-cs.ps1 -Directory | Select-Object -First:1 |% {
    $Dir = ( Get-Item -LiteralPath $_ )
    Get-ChildItem -LiteralPath $Dir.FullName -Directory |? { $_.Name -like '.run-*' } |? { ( Get-ChildItem $_.FullName | Measure-Object ).Count -eq 0 } |% { Remove-Item $_.FullName -Verbose }
}

If ( $SU ) {

    ( "Job Completed @ {0}" -f ( Get-Date ) ) | Write-Host -ForegroundColor Green -BackgroundColor Black
    $YN = ( & read-yesfromhost-cs.ps1 -Prompt "Close window?" -Timeout:60 )
    If ( -Not $YN ) {
        $Close = ( Read-Host -Prompt "Press ENTER to Close..." )
    }

}
