Param(
    [Parameter(ValueFromPipeline=$true)] $Item=$null,
	[switch] $At=$false,
    [switch] $Ascend=$false,
	[switch] $Force=$false,
	[switch] $Bagged=$false,
    [switch] $CheckZipped=$false,
    [switch] $CheckMirrored=$false,
    [switch] $CheckCloud=$false,
    [switch] $ShowWarnings=$false
)

Begin {
    $global:gColdStorageGetItemPackageCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gColdStorageGetItemPackageCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )
    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageStats.psm1" )
    Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageToCloudStorage.psm1" )

    $ExitCode = 0
}

Process {
    If ( $_ -ne $null ) {
        $Orig = $_
        $oItem = ( $Item | Get-FileObject )
        If ( $oItem ) {
            $oPackage = ( $oItem | Get-ItemPackage -At:$At -Ascend:$Ascend -Force:$Force -CheckZipped:$CheckZipped -CheckMirrored:$CheckMirrored -CheckCloud:$CheckCloud )
            If ( $Orig -is [Object] ) {
                $Orig | Get-Member -MemberType NoteProperty -Name CS* |% {
                    $PropName = $_.Name
                    If ( -Not ( $oPackage | Get-Member -MemberType NoteProperty -Name:$_.Name ) ) {
                        $oPackage | Add-Member -MemberType:$_.MemberType -Name:$_.Name -Value:$Orig.${PropName}
                    }
                }
            }
            $oPackage
        }
    }
}

End {
    Exit $ExitCode
}
