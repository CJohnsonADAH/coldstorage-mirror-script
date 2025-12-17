Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    $Algorithm='MD5'
)

Begin {
    $ExitCode = 0

    $e = ( & coldstorage echo )
}

Process {
    $oItem = ( $Item | get-itempackage-cs.ps1 -At -Force -Bagged )
    
    If ( Test-Path -LiteralPath $oItem.FullName -PathType Leaf ) {
        $oParent = $oItem.Directory
    }
    ElseIf ( Test-Path -LiteralPath $oItem.FullName -PathType Container ) {
        $oParent = $oItem.Parent
    }
    Else {
        $oParent = $null
        $ExitCode = 2    
    }

    If ( $oParent ) {
        $ColdAux = ( $oParent.Root | Join-Path -ChildPath "ADAHCOLD-Auxiliary" )
        $oRepo = ( $oItem | Get-FileRepositoryProps )
        $ColdAuxRepo = ( $ColdAux | Join-Path -ChildPath $oRepo.Repository )
    }

    If ( $oItem | Test-LooseFile ) {
        If ( $oItem.CSPackageBagged ) {
            $oItem.CSPackageBagLocation |% {
                $data = ( $_.FullName | Join-Path -ChildPath "data" )
                $copy = ( $data | Join-Path -ChildPath $oItem.Name )

                $oPayload = ( Get-Item -LiteralPath:$copy -Force )

                If ( $oPayload ) {
                    
                    $SizeMatch = ( $oItem.Length -eq $oPayload.Length )
                    
                    $hashes = ( Get-FileHash -LiteralPath:@( $oItem.FullName, $oPayload.FullName ) -Algorithm:$Algorithm )
                    
                    $HashMatch = ( $hashes[0].Hash -eq $hashes[1].Hash )

                    $OK = ( $SizeMatch -and $HashMatch )
                    
                    If ( $OK ) {
                        If ( $oPayload.LinkType -ne 'HardLink' ) {
                            If ( Test-Path -LiteralPath $oPayload.FullName -PathType Leaf ) {
                                $oPayloadParent = $oPayload.Directory
                            }
                            ElseIf ( Test-Path -LiteralPath $oPayload.FullName -PathType Container ) {
                                $oPayloadParent = $oPayload.Parent
                            }
                            Else {
                                $oPayloadParent = $null
                                $ExitCode = 2    
                            }
                            
                            $ColdAuxLocation = ( Join-Path $ColdAuxRepo -ChildPath ( $oPayloadParent.FullName | Get-CSPackagePathRelativeToRepository ) )
                            If ( $ColdAuxLocation ) {
                                If ( Test-Path -LiteralPath $ColdAuxLocation ) {
                                    $oTrashDestination = ( Get-Item -LiteralPath $ColdAuxLocation -Force )
                                }
                                Else {
                                    $oTrashDestination = ( New-Item -ItemType Directory -Path $ColdAuxLocation -Verbose )
                                }
                            }

                            $PayloadPath = $oPayload.FullName
                            Move-Item -LiteralPath:$PayloadPath -Destination:( $oTrashDestination.FullName ) -Verbose
                            New-Item -ItemType:HardLink -Path:$PayloadPath -Target:$oItem.FullName |% { "link: {0} -> {1}" -f $_.FullName, $oItem.FullName | Write-Host -ForegroundColor Yellow }
                        }
                        Else {
                            "{0}: ({1})=> [{2}]" -f $oPayload.FullName, $oPayload.LinkType, ( $oPayload.Target -join ", " ) | Write-Host -ForegroundColor Yellow
                        }
                    }

                    If ( ( -Not $OK ) -and ( $ExitCode -lt 1 ) ) {
                        $ExitCode = 1
                    }
                }

            }
        }
        Else {
            $oItem | write-packages-report-cs.ps1 | Write-Host -ForegroundColor Yellow
            $ExitCode = 2
        }
    }
    Else {
        $oItem | write-packages-report-cs.ps1 | Write-Host -ForegroundColor Yellow
        $ExitCode = 2
    }
}

End {
    Exit $ExitCode
}