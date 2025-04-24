Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    $Days = 7,
    [switch] $Full=$false
)

Begin { 
}

Process {
    $BagItTxt = ( Join-Path $Item.FullName -ChildPath "bagit.txt" )
    $Data = ( Join-Path $Item.FullName -ChildPath "data" )
    
    $PackageFullName = $Item.FullName
    Write-Progress -Activity "Considering for Preservation" -Status $PackageFullName
    $Logs = ( Join-Path $_.FullName -ChildPath "logs" )

    $Pending = ( ( Test-Path -LiteralPath $BagItTxt -PathType Leaf ) -and ( Test-Path -LiteralPath $Data -PathType Container ) )
    If ( $Pending ) {
        If ( Test-Path -LiteralPath $Logs -PathType Container ) {
            Get-ChildItem -LiteralPath $Logs -Recurse -File |? {
                $OK = ( $_.Name -like 'preservation-*.txt' )
                If ( $Full ) {
                    $OK = ( $OK -and ( $_.Name -notlike '*-FAST.txt' ) )
                }
                $OK
                #Write-Host -ForegroundColor $( If ( $OK ) { "Green" } Else { "Red" } ) $_.Name
            } | Sort-Object -Property LastWriteTime -Descending | Select-Object -First:1 |% {
                Write-Progress -Activity "Considering for Preservaton" -Status ( "{0}: {1}" -f $PackageFullName,$_.FullName )
                $Diff = ( ( Get-Date ) - ( $_.LastWriteTime ) )
                $Pending = ( $Pending -and ( $Diff.Days -gt $Days ) )
            }
        }
    }

    $Pending
}

End {
}
