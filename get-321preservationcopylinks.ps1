Param(
    [Parameter(ValueFromPipeline=$true)] $Package,
    $Output='string',
    [switch] $Confirm
)

Begin {
    $ExitCode = 0

    $global:g321PreservationCopyLinksCmd = $MyInvocation.MyCommand

        $modSource = ( $global:g321PreservationCopyLinksCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageData.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageBagItDirectories.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )

    $AWS = ( Get-ExeForAWSCLI )
}

Process {
    $Package321 = ( $Package | & get-itempackage-cs.ps1 -Check321 )

    $Rpt = [ordered] @{ }
    
    $Rpt[ 'Copy-1' ] = $Package321.FullName
    If ( $Package321.CSPackageCanonicalLocation ) {
        $Rpt[ 'Copy-1' ] = $Package321.CSPackageCanonicalLocation
    }

    $Copy2 = $null
    If ( $Package321.CSPackageMirrorCopy ) {
        $Copy2 = $Package321.CSPackageMirrorCopy
        $Rpt[ 'Copy-2'] = $Copy2.FullName
    }

    $s3Uri = $null
    If ( $Package321.CloudCopy ) {
        $s3Uri = ( $Package321 | Get-CloudStorageURI )
        $Rpt[ 'Copy-3' ] = $s3Uri
    }

    $Rpt.Keys |% {
        "{0}: {1}" -f $_.ToUpper(), $Rpt[ $_ ]
    }

    If ( $Confirm ) {
        If ( $Copy2 -ne $null ) {
            "" | Write-Host
            "=== Confirm Mirror Copy ===" | Write-Host -ForegroundColor:Cyan
            $Manifests = @{ }
            If ( $Package321.CSPackageSidecars.Count -gt 0 ) {
                $p = ( $Copy2 | & get-itempackage-cs.ps1 -At -Force )
                $Package321, $p |% {
                    $_ | Get-321LooseFileChecksumSidecarFile |% {
                        If ( -Not ( $Manifests.ContainsKey( $_.Name ) ) ) {
                            $Manifests[ $_.Name ] = @( )
                        }
                        $Manifests[ $_.Name ] += @( $_ )
                    }
                }
            }
            Else {
                $p = ( $Copy2 | & get-itempackage-cs.ps1 -At -Force )
                $Package321, $p |% {
                    $_ | Get-BagItFormattedDirectoryManifests -Output:object |% {
                        If ( -Not ( $Manifests.ContainsKey( $_.Name ) ) ) {
                            $Manifests[ $_.Name ] = @( )
                        }
                        $Manifests[ $_.Name ] += @( $_ )
                    }
                }
            }

            $Manifests.Keys |% {
                $First = ( $Manifests[ $_ ] | Select-Object -First:1 )
                $Rest = ( $Manifests[ $_ ] | Select-Object -Skip:1 )

                $Rest |% {
                    & fc.exe $First.FullName $_.FullName
                }
            }
        }

        If ( $s3Uri -ne $null ) {
            "" | Write-Host
            "=== Confirm AWS Cloud Storage Listing ===" | Write-Host -ForegroundColor:Cyan
            & "${AWS}" s3 ls "${s3Uri}"
        }
    }
}

End {
    Exit $ExitCode
}
