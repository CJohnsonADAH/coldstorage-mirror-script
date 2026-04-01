Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    $Algorithm='md5',
    [switch] $Force=$false
)

Begin {
    $ExitCode = 0

    $global:gAddChecksumSidecarCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gAddChecksumSidecarCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )

    Function Get-ChecksumSidecarContainers {
    Param( [Parameter(ValueFromPipeline=$true)] $o, $Algorithm )

        Begin { }

        Process {
            If ( $Algorithm -ne '*' ) {
                $oSide = ( $o | get-checksumsidecar-cs.ps1 -Algorithm:"*" -Resolve ) ; $gcsExit = $LASTEXITCODE
            }
            Else {
                $gcsExit = -1 ; $oSide = @( )
            }

            If ( ( $gcsExit -eq 0 ) -and (( $oSide | Measure-Object ).Count -gt 0 ) ) {
                $Containers = @( $oSide |% { $_ | Get-ItemFileSystemParent } )
                $Containers = ( $Containers | Sort-Object -Property FullName -Descending -Unique | Select-Object -First:1 )
                $Containers |%{ 
                    "[{0}] CONTAINER FROM EXISTING SIDECAR: {1} (from {2})" -f ( Get-CSDebugContext -Function:$MyInvocation ), $_.FullName, ( $oSide | Select-Object -First:1 ) | Write-Verbose
                }
            }
            Else {
                $Parent = ( $o | Get-ItemFileSystemParent )
                $ContainerNames = ( Get-BaggedCopyContainerSubdirectories )
            
                $Containers = ( $ContainerNames |% { $Parent.FullName | Join-Path -ChildPath $_ } )
                [Array]::Reverse( $Containers )
            }

            $Containers|  Write-Output
        }

        End { }

    }

}

Process {

    If ( $Algorithm -ne '*' ) {
        $o = ( $Item | Get-FileObject )

        If ( $o ) {

            If ( Test-Path -LiteralPath:$o.FullName -PathType Leaf ) {
            
                $Name = $o.Name

                # Determine an appropriate container.
                $Containers = ( $o | Get-ChecksumSidecarContainers -Algorithm:$Algorithm )
                $Containers | Select-Object -First:1 |% {

                    If ( $_ -ne $null ) {
                        $CandidateContainer = $_
                        If ( -Not ( Test-Path -LiteralPath:$CandidateContainer ) ) {
                            $CandidateContainerItem = ( New-Item -ItemType:Directory -Path:$CandidateContainer )
                        }
                        
                        $CandidateName = ( "{0}.{1}" -f ( $Name -replace '[\[\]]','_' ), $Algorithm )
                        $Candidate = ( $CandidateContainer | Join-Path -ChildPath $CandidateName )

                        "[{0}] SIDECAR CANDIDATE: {1}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $Candidate | Write-Verbose
                        $Hash = ( Get-FileHash -LiteralPath:$o.FullName -Algorithm:$Algorithm )

                        If ( $Hash ) {
                            $Checksum = $Hash.Hash.ToLower()
                            $PayloadPath = ( "{0}/{1}" -f "data", $Name )

                            If ( ( -Not ( Test-Path -LiteralPath:$Candidate ) ) -or $Force ) {
                                "{0}  {1}" -f $Checksum, $PayloadPath | Out-File -LiteralPath:$Candidate -Encoding:utf8
                            }
                        }
                    }

                }

            }
            Else {
                "[{0}] Test-Path -LiteralPath:'{1}' -PathType Leaf failed; I don't know what to do!" -f ( Get-CSDebugContext -Function:$MyInvocation ), $o.FullName | Write-Error
            }

        }
        Else {

                "[{0}] {1} | Get-FileObject failed; I don't know what to do!" -f ( Get-CSDebugContext -Function:$MyInvocation ), $Item | Write-Error

        }
    }
    Else {

        "[{0}] {1}: Wildcard algorithm '{2}' not permitted" -f ( Get-CSDebugContext -Function:$MyInvocation ), $Item, $Algorithm | Write-Error

    }

}

End {
    Exit $ExitCode
}
