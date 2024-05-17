Param(
    [Parameter(ValueFromPipeline=$true)] $Package,
    [string] $Output="",
    [switch] $Bagged,
    [switch] $Unbagged,
    [switch] $Mirrored,
    [switch] $Unmirrored,
    [switch] $Zipped,
    [switch] $Unzipped,
    [switch] $InCloud,
    [switch] $NotInCloud,
    [switch] $FullName=$false,
    $Timestamp=$null,
    $Context=$null
)

Begin {

    $Verbose = ( $MyInvocation.BoundParameters["Verbose"].IsPresent )
    $Verbose = $( If ( $Verbose -eq $null ) { $false } Else { $Verbose } )
    $Debug = ( $MyInvocation.BoundParameters["Debug"].IsPresent )
    $Debug = $( If ( $Debug -eq $null ) { $false } Else { $Debug } )

    # Internal Dependencies - Modules
    $global:gWritePackagesReportCSCmd = $MyInvocation.MyCommand

        $modSource = ( $global:gWritePackagesReportCSCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )

    Function Get-ScriptPath {
    Param ( $Command, $File=$null )

        $Source = ( $Command.Source | Get-Item -Force )
        $Path = ( $Source.Directory | Get-Item -Force )

        If ( $File -ne $null ) {
            $Path = ($Path.FullName | Join-Path -ChildPath $File)
        }

        $Path
    }

    $bVerboseModules = ( $Debug -eq $true )
    $bForceModules = ( ( $Debug -eq $true ) -or ( $psISE ) )

    Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( $modPath.FullName | Join-Path -ChildPath "ColdStorageInteraction.psm1" )
    Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
    Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )

    $ExitCode = 0
}

Process {
    
    $CheckBagged = $Package.CSPackageCheckedBagged
    $CheckMirrored = $Package.CSPackageCheckedMirrored
    $CheckZipped = $Package.CSPackageCheckedZipped
    $CheckCloud = $Package.CSPackageCheckedCloud

    $bResult = ( $Package -ne $null )
    If ( $CheckBagged ) {
        If ( $Bagged ) {
            $bResult = ( $bResult -and $Package.CSPackageBagged )
        }
        If ( $Unbagged ) {
            $bResult = ( $bResult -and ( -Not $Package.CSPackageBagged ) )
        }
    }

    If ( $CheckMirrored ) {
        $bIsMirrored = $Package.CSPackageMirrored
        $sMirrorLocation = $Package.CSPackageMirrorLocation

        If ( $Mirrored ) {
            $bResult = ( $bResult -and $bIsMirrored )
        }
        If ( $Unmirrored ) {
            $bResult = ( $bResult -and ( -Not $bIsMirrored ) )
        }
    }

    If ( $CheckZipped ) {
        $bIsZipped = ( $Package.CSPackageZip.Count -gt 0 )
        If ( $Zipped ) {
            $bResult = ( $bResult -and $bIsZipped )
        }
        If ( $Unzipped ) {
            $bResult = ( $bResult -and ( -Not $bIsZipped ) )
        }
    }

    If ( $CheckCloud ) {
        $sZippedFile = $( If ( $Package.CSPackageZip.Count -gt 0 ) { $Package.CSPackageZip[0].Name } Else { "" } )
        $bIsInCloud = ( $Package.CloudCopy -and $sZippedFile )

        If ( $InCloud ) {
            $bResult = ( $bResult -and $bIsInCloud )
        }
        If ( $NotInCloud ) {
            $bResult = ( $bResult -and ( -Not $bIsInCloud ) )
        }
    }

    $bResult
    If ( -Not $bResult ) {
        $ExitCode = 1
    }
}

End {
    Exit $ExitCode
}
