Param(
    [Parameter(ValueFromPipeline=$true)] $Location,
    [Parameter(Position=0)] [ScriptBlock] $Job={ },
    [switch] $Original=$false,
    [switch] $ColdStorage=$false,
    [switch] $Forward=$false,
    [switch] $Reflection=$false
)

Begin {
    $ExitCode = 0

    $global:gInvokeInMirrorLocationCmd = $MyInvocation.MyCommand

        $modSource = ( $global:gInvokeInMirrorLocationCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageData.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" )

}

Process {
    If ( $Location -eq $null ) {
        $here = ( Get-Item -LiteralPath:. -Force )
    }
    Else {
        $here = ( $Location | Get-FileObject )
    }

    If ( $here ) {
        Push-Location -LiteralPath:$here.FullName

        & set-location-to-mirror-cs.ps1 -LiteralPath:$here.FullName -Original:$Original -ColdStorage:$ColdStorage -Reflection:$Reflection -Push -Quiet ; $SLTMExitCode = $LASTEXITCODE

        If ( $SLTMExitCode -eq 0 ) {

            & $Job
            
            & set-location-to-mirror-cs.ps1 -Pop -Quiet

        }
        Else {
            "[{0}] Could not find mirror location: '{1}'" -f ( Get-CSDebugContext ), "${Location}" | Write-Error
            $ExitCode = $SLTMExitCode
        }

        Pop-Location
    }
    Else {
        "[{0}] Could not find base location: '{1}'" -f ( Get-CSDebugContext ), "${Location}" | Write-Error
        $ExitCode = 2
    }

}

End {
    Exit $ExitCode
}
