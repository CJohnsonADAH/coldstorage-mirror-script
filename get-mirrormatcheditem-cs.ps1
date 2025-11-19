Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    $Path=$null,
    $LiteralPath=$null,
    [switch] $Object=$false,
    $Pair=$null,
    $In=@(),
    [switch] $Original=$false,
    [switch] $Reflection=$false,
    [switch] $ColdStorage=$false,
    [switch] $Trashcan=$false,
    [switch] $Self=$false,
    [switch] $Other=$false,
    [switch] $All=$false,
    [switch] $IgnoreBagging=$false,
    [switch] $Passive=$false,
    $Repositories=$null
)

Begin {
    $Verbose = ( $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent )
    $Verbose = $( If ( $Verbose -eq $null ) { $false } Else { $Verbose } )
    $Debug = ( $PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent )
    $Debug = $( If ( $Debug -eq $null ) { $false } Else { $Debug } )

    If ( $Debug ) {
        $DebugPreference = 'Continue'
    }

    $global:gColdStorageTestReadyToBundleCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gColdStorageTestReadyToBundleCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$Verbose -Debug:$Debug -Force:$Debug $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
    Import-Module -Verbose:$Verbose -Debug:$Debug -Force:$Debug $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" )

    $csExitCode = 255
    $results = @( )

    $allObjects = @( )

    If ( $Path -ne $null ) {
        $allObjects = @( $allObjects ) + @( Get-Item -Path:$Path )
    }
    If ( $LiteralPAth -ne $null ) {
        $allObjects = @( $allObjects ) + @( Get-Item -LiteralPath:$LiteralPath )
    }


}

Process {
    If ( $Item -ne $null ) {
        $Item | get-file-cs.ps1 -Object |% {
        
            $result = ( $_ | Get-MirrorMatchedItem -Pair:$Pair -In:$In -Original:$Original -Reflection:$Reflection -ColdStorage:$ColdStorage -Self:$Self -Other:$Other -All:$All -IgnoreBagging:$IgnoreBagging -Passive:$Passive -Repositories:$Repositories -Verbose:$Verbose -Debug:$Debug )
            
            # Get-MirrorMatchedItem returns a string containing a LiteralPath; convert to Item object if desired
            If ( $Object ) {
                If ( ( $result -ne $null ) -and ( $result.Count -gt 0 ) ) {
                    $result = ( Get-Item -LiteralPath $result -Force -ErrorAction SilentlyContinue )
                }
            }
            
            If ( $result ) {
                $result | Write-Output
                $resultcode = 0
            }
            Else {
                $resultcode = 1
            }
            
            $results = @( $results ) + @( $resultcode )
        }
    }
}

End {
    $allObjects |% {
        $Cmd = $MyInvocation.MyCommand.Source
        $_ | & "${Cmd}" -Object:$Object -Pair:$Pair -In:$In -Original:$Original -Reflection:$Reflection -ColdStorage:$ColdStorage -Self:$Self -Other:$Other -All:$All -IgnoreBagging:$IgnoreBagging -Passive:$Passive -Repositories:$Repositories -Verbose:$Verbose -Debug:$Debug
        $results = @( $results ) + @( $LASTEXITCODE )
    }

    If ( $results.Count -gt 0 ) {
        $csExitCode = ( $results | Measure-Object -Sum ).Sum
    }

    Exit $csExitCode
}