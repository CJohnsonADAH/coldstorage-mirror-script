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
                    
                    $OK | Write-Output
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