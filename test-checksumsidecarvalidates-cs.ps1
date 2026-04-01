Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    $Algorithm='*',
    [switch] $Force=$false
)

Begin {
    $ExitCode = 0

    $global:gChecksumSidecarCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gChecksumSidecarCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )

    Function Test-ChecksumsValidate {
    Param( [Parameter(ValueFromPipeline=$true)] $Hash )

        Begin { }

        Process {
            "Checking {0} Algorithm: {1} vs. [{2}]" -f $Hash[ "Algorithm" ], $Hash[ "Computed" ], ( $Hash[ "Recorded" ] -join ", " ) | Write-Verbose
            ( $Hash[ "Computed" ] -iin $Hash[ "Recorded" ] ) | Write-Output
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
            $reFileName = ( '^({0})' -f [Regex]::Escape( $File.Name ) )
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

    Function ConvertFrom-TagFileText {
    Param( [Parameter(ValueFromPipeline=$true)] $Item )

        Begin { }

        Process {
            $Output = @{ }

            $BagContainer = $null
            $Checksums = @{ }

            $o = ( $Item | Get-FileObject )
            $Text = ( Get-Content -LiteralPath:$o.FullName )
            $Text |% {
                If ( $_ -match '^[#]\s*(\S.*\S)' ) {
                    $BagContainer = $Matches[1]
                }
                Else {
                    $Algorithm, $Hash, $FileName = ( $_ -split '\s+',3 )
                    
                    If ( -Not $Checksums.ContainsKey( $FileName ) ) {
                        $Checksums[ $FileName ] = @{ }
                    }
                    If ( -Not $Checksums[ $FileName ].ContainsKey( $Algorithm ) ) {
                        $Checksums[ $FileName ][ $Algorithm ] = @( )
                    }
                    $Checksums[ $FileName ][ $Algorithm ] += @( $Hash )
                }
            }

            $Output[ "BagContainer" ] = $BagContainer
            $Output[ "Checksums" ] = $Checksums
            
            $Output | Write-Output
        }

        End { }
    }

}

Process {

    $o = ( $Item | Get-FileObject )

    If ( $o ) {

        If ( Test-Path -LiteralPath:$o.FullName -PathType Leaf ) {
            
            $Name = $o.Name

            # Get a list of all known sidecars for the specified algorithm(s)
            $ConfirmSidecars = @{ }
            $TagFile = ( $o | get-checksumsidecar-cs.ps1 -Algorithm:"tag" -Resolve ) ; $gcsExit = $LASTEXITCODE
            If ( ( $gcsExit -eq 0 ) -and ( $TagFile ) ) {
                "[{0}] Tag file: {1}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $TagFile | Write-Verbose
                $ConfirmSidecars = ( $TagFile | ConvertFrom-TagFileText )
            }

            $Sidecars = ( $o | get-checksumsidecar-cs.ps1 -Algorithm:$Algorithm -Resolve ) ; $gcsExit = $LASTEXITCODE
            If ( $gcsExit -eq 0 ) {
                $SidecarsTable = ( $Sidecars | Get-ChecksumSidecarAlgorithmsFromFileNames -File:$o -Hashtable )

                $Algorithms = ( $SidecarsTable.Keys )
                
                $Checksums = @{ }
                $Algorithms |% {
                    $Algorithm = $_

                    $ComputedHash = ( Get-FileHash -LiteralPath:$o.FullName -Algorithm:$Algorithm )
                    $Checksums[ $Algorithm ] = @{ "Algorithm"=$ComputedHash.Algorithm ; "Computed"=$ComputedHash.Hash.ToLower() }
                    
                    $Records = ( $SidecarsTable[ $_ ] )
                    $Records |% {
                        $RecordFile = $_

                        $TagChecksums = @{ }
                        If ( $ConfirmSidecars.ContainsKey( 'Checksums' ) ) {
                            If ( $ConfirmSidecars[ 'Checksums' ].ContainsKey( $RecordFile.Name ) ) {
                                $ConfirmSidecars[ 'Checksums' ][ $RecordFile.Name ].Keys |% {
                                    $TagAlgorithm = $_
                                    $ConfirmSidecars[ 'Checksums' ][ $RecordFile.Name ][ $TagAlgorithm ] |% {
                                        $TagChecksum = $_
                                        $TagHash = ( Get-FileHash -LiteralPath:$RecordFile.FullNAme -Algorithm:$TagAlgorithm )

                                        $TagChecksums[ $TagAlgorithm ] = @{ "Algorithm"=$TagAlgorithm ; "Computed"=$TagHash.Hash ; "Recorded"=@( $TagChecksum ) }
                                    }
                                }
                            }
                        }

                        $SidecarOK = $true
                        $TagChecksums.Keys |% {
                            $SidecarOK = ( $SidecarOK -and ( $TagChecksums[ $_ ] | Test-ChecksumsValidate ) )
                        }
                        
                        If ( $SidecarOK ) {

                            Get-Content -LiteralPath:$_.FullName |% {

                                $Checksum, $PayloadPath = ( $_ -split '\s+',2 )

                                If ( -Not ( $Checksums.ContainsKey( $Algorithm ) ) ) {
                                    $Checksums[ $Algorithm ] = @{ "Algorithm"=$Algorithm ; "Recorded"=@( ) }
                                }
                                If ( -Not ( $Checksums[ $Algorithm ].ContainsKey( "Recorded" ) ) ) {
                                    $Checksums[ $Algorithm ][ "Recorded" ] = @( )
                                }
                                $Checksums[ $Algorithm ][ "Recorded" ] += @( $Checksum )

                            }
                        }
                        Else {
                            "[{0}] SIDECAR FAILED CHECKSUM TEST: {1}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $_.FullName | Write-Warning
                            If ( -Not ( $Checksums.ContainsKey( $Algorithm ) ) ) {
                                $Checksums[ $Algorithm ] = @{ "Algorithm"=$Algorithm ; "Recorded"=@( ) }
                            }
                            If ( -Not ( $Checksums[ $Algorithm ].ContainsKey( "Recorded" ) ) ) {
                                $Checksums[ $Algorithm ][ "Recorded" ] = @( )
                            }
                            $Checksums[ $Algorithm ][ "Recorded" ] += @( "-" )
                        }

                    }
                }

                $Output = $true
                $Checksums.Keys |% {

                    $OK = ( $Checksums[ $_ ] | Test-ChecksumsValidate )
                    $Output = ( $Output -and $OK )

                }

                $Output | Write-Output
                If ( $Output ) {
                    $ExitCode = 0
                }
                Else {
                    $ExitCode = 1
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
