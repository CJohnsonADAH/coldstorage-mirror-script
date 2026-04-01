Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    [switch] $Force=$false
)

Begin {
    $ExitCode = 0

    $global:gAddChecksumSidecarTagCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gAddChecksumSidecarTagCmd.Source | Get-Item -Force )
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

    Function Get-ChecksumSidecarAlgorithmsFromFileNames {
    Param( [Parameter(ValueFromPipeline=$true)] $Sidecar, $File, [switch] $Hashtable=$false )

        Begin {
            If ( $Hashtable ) {
                $Output = @{ }
            }
        }

        Process {
            $o = ( $Sidecar | Get-FileObject )

            $FileName = ( $File.Name -replace '[\[\]]','_' )
            $reFileName = ( '^({0})' -f [Regex]::Escape( $FileName ) )

            $Suffix = ( $o.Name -replace $reFileName,'' )
            $Algorithm = ( $Suffix -split '[.]' |? { $_.Length -gt 0 } )
            
            If ( $Hashtable ) {
                If ( -Not $Output.ContainsKey( $Algorithm ) ) {
                    $Output[ $Algorithm ] = @( )
                }
                $Output[ $Algorithm ] = @( $Output[ $Algorithm ] ) + @( $o )
            }
            Else {
                $Algorithm | Write-Output
            }

        }

        End {
            If ( $Hashtable ) {

                $Output | Write-Output

            }
        }
    }
}

Process {

    $o = ( $Item | Get-FileObject )

    If ( $o ) {

        If ( Test-Path -LiteralPath:$o.FullName -PathType Leaf ) {
            
            $Name = $o.Name

            # Get sidecar files, and hashing algorithms (from the sidecar files)
            $Sidecars = ( $o | get-checksumsidecar-cs.ps1 -Algorithm:"*" -Resolve )
            $AlgorithmSidecars = ( $Sidecars | Get-ChecksumSidecarAlgorithmsFromFileNames -File:$o -Hashtable )
            $Algorithms = $AlgorithmSidecars.Keys
            
            # Get the name of a prospective bag container directory
            $LastWriteTime = ( $Sidecars | Get-FileObject |% { $_.LastWriteTime } | Sort-Object -Descending | Select-Object -First:1 )
            $BagName = ( $Item | Get-PathToBaggedCopyOfLooseFile -Timestamp:$LastWriteTime )
            "[{0}] BAG NAME: {1}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $BagName | Write-Verbose

            $Repository = ( $Item | Get-FileRepositoryLocation )
            Push-Location -LiteralPath:$Repository.FullName
            $RelLocation = ( Resolve-Path -LiteralPath:$Item.FullName -Relative )
            Pop-Location

            # Determine an appropriate JSON file name in the appropriate container
            $Containers = ( $o | Get-321LooseFileChecksumSidecarsContainer -Detect -Create -Output:"object" )
            
            $Containers | Select-Object -First:1 |% {

                If ( $_ -ne $null ) {
                    $CandidateContainer = $_
                    If ( -Not ( Test-Path -LiteralPath:$CandidateContainer ) ) {
                        $CandidateContainerItem = ( New-Item -ItemType:Directory -Path:$CandidateContainer )
                    }
                    
                    $TagFile = ( $o | Get-ItemPackageMetadataFilePath )

                    "[{0}] SIDECAR TAG FILE: {1}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $TagFile | Write-Verbose
                    $MetaFile = ( $o | Get-ItemPackageMetadataFile )
                    If ( -Not $MetaFile ) {
                        $MetaFile = ( $o | New-ItemPackageMetadataFile )
                    }

                    $o | Add-ItemPackageMetadata -Name:"Bag-Directory" -Value:$BagName -Force
                    $o | Add-ItemPackageMetadata -Name:"Repository" -Value:$Repository.FullName -Force
                    $o | Add-ItemPackageMetadata -Name:"Location" -Value:$RelLocation -Force

                    $TagManifest = @{ }
                    $Sidecars |% {
                        $Sidecar = ( $_ | Get-FileObject )
                        $Algorithms |% {
                            $Algorithm = $_
                            $Hash = ( Get-FileHash -LiteralPath:$Sidecar.FullName -Algorithm:$Algorithm )

                            If ( $Hash ) {
                                If ( -Not $TagManifest.ContainsKey( $Sidecar.Name  ) ) {
                                    $TagManifest[ $Sidecar.Name  ] = @{ }
                                }
                                If ( -Not $TagManifest[ $Sidecar.Name  ].ContainsKey( $Algorithm ) ) {
                                    $TagManifest[ $Sidecar.Name  ][ $Algorithm ] = @( )
                                }

                                $TagManifest[ $Sidecar.Name ][ $Algorithm  ] += @( $Hash.Hash.ToLower() )

                                #"{0}  {1}  {2}" -f $Algorithm, $Checksum, $Sidecar.Name | Out-File -LiteralPath:$TagFile -Encoding:utf8 -Append

                            }
                        }
                    }

                    $o | Add-ItemPackageMetadata -Name:"Bag-TagManifests" -Value:$TagManifest -Force

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

End {
    Exit $ExitCode
}
