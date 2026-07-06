Param(
    [Parameter(ValueFromPipeline=$true)] $Item
)

Begin {
    $ExitCode = 0
    
    $global:gGet321PackageCloudCopyCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gGet321PackageCloudCopyCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageToCloudStorage.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageZipArchives.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageInteraction.psm1" )

}

Process {

    # Not found, until proven found
    $Found = $false
        
    $package = ( $Item | Get-ItemPackage -At -CheckZipped )
    If ( $package.CSPackageZip ) {
        $package.CSPackageZip |% {
            $Container = ( $_ | Get-ItemFileSystemParent )
            $json = ( $package | Get-ZippedBagsWildcardOfUnzippedBag -AllPossible |% {
                If ( $_ -like '*.json' ) {
                    Push-Location -LiteralPath:$Container.FullName
                    Get-ChildItem $_ -File -Force
                    Pop-Location
                }
            } )
            If ( $json.Count -gt 0 ) {
                $json |% {
                    $cached = ( Get-Content -LiteralPath:$_.FullName | ConvertFrom-Json )
                    If ( $cached | Get-Member -Name:Contents ) {
                        $cachedContents = ( $cached.Contents )
                    }
                    Else {
                        $cachedContents = ( $cached )
                    }

                    $cachedContents | Write-Output
                    $Found = $true
                }
            }
        }
    }

    If ( -Not $Found ) {
        $ExitCode = 1
    }

}

End {
    Exit $ExitCode
}
