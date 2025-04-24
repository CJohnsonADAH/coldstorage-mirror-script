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

    $ExitCode = 0
}

Process {
    If ( $_ -ne $null ) {
        $oItem = ( $Item | Get-FileObject )
        If ( $oItem ) {
            $oItem | Get-ItemPackage -At:$At -Ascend:$Ascend -Force:$Force -CheckZipped:$CheckZipped -CheckMirrored:$CheckMirrored -CheckCloud:$CheckCloud
        }
    }
}

End {
    Exit $ExitCode
}
