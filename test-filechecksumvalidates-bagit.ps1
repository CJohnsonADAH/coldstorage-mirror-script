Param(
    $Algorithm='MD5'
)

Function Get-BIFileChecksumItem {
Param( [Parameter(ValueFromPipeline=$true)] $Item )

    Begin { }

    Process {
        If ( $Item -is [hashtable] ) {
            "HASH!!!" | Write-Warning

            $oItem = ( Get-Item -LiteralPath:( $Item[ 'File' ] ) -Force -ErrorAction:SilentlyContinue )
            $oItem | Add-Member -MemberType NoteProperty -Name Hash -Value:( $Item[ 'Checksum' ] ) -Force
        }
        ElseIf ( $Item | Get-Member -Name:Hash ) {

            If ( $Item | Get-Member -Name:FullName ) {

                $oItem = $Item

            }
            ElseIf ( $Item | Get-Member -Name:Path ) {

                $oItem = ( Get-Item -LiteralPath:( $Item.Path ) -Force -ErrorAction:SilentlyContinue )
                $oItem | Add-Member -MemberType NoteProperty -Name Hash -Value:( $Item.Hash ) -Force

            }


        }

        If ( $oItem ) {
            $oItem.FullName
            $oItem.Hash
        }

    }

    End {
    }

}

Function Test-BIFileChecksumValidates {
Param( [Parameter(ValueFromPipeline=$true)] $Item, $Algorithm='MD5' )

    Begin { }

    Process {
        $FilePath, $Checksum = ( Get-BIFileChecksumItem $Item )

        $RecordedHash = $Checksum

        $ComputedSum = ( Get-FileHash -LiteralPath:$FilePath -Algorithm:$Algorithm )
        
        "COMPUTED: {0}" -f $ComputedSum.Hash | Write-Warning
        "RECORDED: {0}" -f $RecordedHash | Write-Warning

        $ComputedSum.Hash -ieq $RecordedHash
    }

    End {
    }

}

$Input | Test-BIFileChecksumValidates -Algorithm:$Algorithm
