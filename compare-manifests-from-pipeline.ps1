Param(
    $To=$null,
    $Algorithm=$null
)

Function Merge-Hashtables {
Param ( [Parameter(ValueFromPipeline=$true)] $Table )

    Begin {
        $Output = @{ }
    }

    Process {
        If ( $Table -is [hashtable] ) {
            $Output = $Output + ( $Table )
        }
    }

    End {
        $Output
    }
}

$Input |% {
    $LeftText = $_
    $RightText = $To
    
    $Lines = ( $LeftText -split "[`r`n]+" |% { "$_" -replace '(^\s+|\s+$)','' } |? { $_.Length -gt 0 } )
    $CounterLines = ( $RightText -split "[`r`n]+" |% { "$_" -replace '(^\s+|\s+$)','' } |? { $_.Length -gt 0 } )

    $LeftManifest = ( $Lines |% { $Hash,$Name = ( "$_" -split "\s+",2 ) ; @{ $Name=$Hash } } | Merge-Hashtables )
    $RightManifest = ( $CounterLines |% { $Hash,$Name = ( "$_" -split "\s+",2 ) ; @{ $Name=$Hash } } | Merge-Hashtables )

    $LeftManifest.Keys |% {
        $Key = $_
        $Left = $LeftManifest[ $Key ]

        If ( $RightManifest.ContainsKey( $Key ) ) {
            
            $Right = $RightManifest[ $Key ]

            If ( $Left -ne $Right ) {

                ( "{0}`t{1}" -f $Left,$Key ) | Write-Host -ForegroundColor Red
                ( "{0}`t{1}" -f $Right,$Key ) | Write-Host -ForegroundColor Green

            }

        }
        Else {

            ( "{0}`t{1}" -f $Left,$Key ) | Write-Host -ForegroundColor Red
            ( "-" ) | Write-Host -ForegroundColor Green

        }

    }

    $RightManifest.Keys |% {
        $Key = $_

        If ( -Not $LeftManifest.ContainsKey( $Key ) ) {
            $Right = $RightManifest[ $Key ]

            ( "-" ) | Write-Host -ForegroundColor Red
            ( "{0}`t{1}" -f $Right,$Key ) | Write-Host -ForegroundColor Green

        }
    }
}