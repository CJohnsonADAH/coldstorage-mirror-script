﻿Param(
    [switch] $Loop=$false
)

$global:gColdStorageMirrorCheckupCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gColdStorageMirrorCheckupCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" )
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
        $LoopCredentials = $null
        Do {
            $retval = ( Invoke-SelfWithNetworkAccess -Invocation:$Invoc -Credentials:$LoopCredentials -Loop:$Loop )
            $LoopCredentials = ( $retval.ISWNACredentials )
            $LoopCredentials.UserName | Write-Warning

            If ( $retval -gt 0 ) {
                "UGH: {0:N0}" -f $retval | Write-Error
            }
            If ( $Loop ) {
                $KeepOnGoing = ( & read-yesfromhost-cs.ps1 -Prompt "Repeat the startup process?" )
            }
        } While ( $Loop -and $KeepOnGoing )

        Exit $retval
    }
}
Else {
    $Host.UI.RawUI.ForegroundColor = 'White'
    $Host.UI.RawUI.BackgroundColor = 'DarkCyan'
    Clear-Host
    
    ( "[{0}] User has network access to {1}; good to go!" -f $cmd.Name,( Get-ColdStorageAccessTestPath ) ) | Write-Verbose
}

start PowerShell -WindowStyle Maximized { $Host.UI.RawUI.BackgroundColor = 'DarkGreen' ; Clear-Host ; ( '>>> Running Q-Number checkup as {0}' -f $env:USERNAME ) | Write-Host ; Get-ChildItem H:\Digitization\Masters\Q_numbers ; & coldstorage-mirror-checkup.ps1 -Q -Loop }
Start PowerShell -WindowStyle Maximized { $Host.UI.RawUI.BackgroundColor = 'DarkGreen' ; Clear-Host ; ( '>>> Running ER checkup as {0}' -f $env:USERNAME ) | Write-Host ; Get-ChildItem H:\ElectronicRecords ; & coldstorage-mirror-checkup.ps1 -ER -Loop }

Do {
    ( '>>> Checking for deferred preservation jobs' ) | Write-Host  -ForegroundColor Yellow
    $jobs = ( & get-deferred-preservation-jobs-cs.ps1 -Items )
    If ( $jobs.Count -gt 0 ) {
        & invoke-deferred-preservation-jobs-cs.ps1 -Scheduled -Verbose:$Verbose -Debug:$Debug
    }
    Else {
        "" | Write-Host
        ( "OK: Currently no deferred preservation jobs pending ({0})" -f ( Get-Date ) ) | Write-Host
        "" | Write-Host
    }
} While ( & read-yesfromhost-cs.ps1 -Prompt "Repeat the check for deferred preservation jobs?" -Timeout:( 24 * 60 * 60 ) )

$CloseYN = ( & read-yesfromhost-cs.ps1 -Prompt:"OK to close the launcher window here?" -Timeout:30 )
If ( -Not $CloseYN ) {
    $ok = ( Read-Host -Prompt "Press ENTER when ready to close" )
}

