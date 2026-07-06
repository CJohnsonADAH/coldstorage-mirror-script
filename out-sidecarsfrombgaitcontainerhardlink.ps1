Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    [switch] $Quiet=$false,
    [switch] $PassThru=$false
)

Begin {
    $ExitCode = 0

    $global:gOutSidecarsFromBagitContainerHardlinkCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gOutSidecarsFromBagitContainerHardlinkCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )

    Function Out-SidecarsFromBagItContainerHardlink {
    Param (
        [Parameter(ValueFromPipeline=$true)] $Package
    )
    
        Begin { }

        Process {
            
            $Manifests = ( $Package.CSPackageBagLocation | & get-bagitmanifestfiles.ps1 -Payload )
            $Manifests
            $TagManifests = ( $Package.CSPackageBagLocation | & get-bagitmanifestfiles.ps1 -Tag )
            $TagManifests | Write-Host -ForegroundColor:DarkYellow
            $PackageJson = ( $Package | Get-ItemPackageMetadataFile )
            $PackageJson

        }

        End { }
    
    }

}

Process {
    If ( $Item | Get-FileObject ) {

        $p = ( $Item | Get-ItemPackage -At -Force )

        If ( $p | test-cs-package-is.ps1 -Bagged ) {
            
            If ( $p | Test-LooseFile ) {

                If ( $p | test-cs-package-is.ps1 -Sidecars ) {
                    
                    "[{0}] '{1}' ALREADY has sidecar files." -f ( CSDbg ), $p.FullName | Write-Warning
                    $ExitCode = 4

                }
                ElseIf ( -Not ( $p | test-cs-package-is.ps1 -BagItFormatted ) ) {
                    
                    "[{0}] '{1}' has a preservation package but does not appear to be bagged." -f ( CSDbg ), $p.FullName | Write-Warning
                    $ExitCode = 5
            
                }
                Else {

                    "BAGGED LOOSEY: {0} -> {1}" -f $p.FullName, $p.CSPackageBagLocation
                    $p | Out-SidecarsFromBagItContainerHardlink

                }

            }
            Else {

                "[{0}] '{1}' does not appear to be a singleton-file package." -f ( CSDbg ), $p.FullName | Write-Warning
                $ExitCode = 3
            
            }

        }
        Else {
            If ( $p.FullName ) {
                $itemName = $p.FullName
            }
            Else {
                $itemName = ( $Item | Get-FileObject ).FullName
            }
            "[{0}] '{1}' does not appear to have a bagged preservation package." -f ( CSDbg ), $itemName | Write-Warning
            $ExitCode = 2
        }
    }
    Else {
        "[{0}] '{1}' does not appear to be a file-system object." -f ( CSDbg ), $Item | Write-Warning
        $ExitCode = 1
    }

}

End {
    Exit $ExitCode
}