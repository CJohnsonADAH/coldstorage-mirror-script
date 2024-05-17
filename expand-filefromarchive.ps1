Param(
    $Archive,
    $File=$null,
    $FileName=$null,
    $To=$null,
    [switch] $Content=$false,
    [switch] $Metadata=$false,
    [switch] $Raw=$false,
    $MaxDepth=9999
)

Add-Type -Assembly System.IO.Compression.FileSystem

Function Write-ExtractedOutput {
Param( $To )

    If ( $To -eq $null ) {
        $Input | Write-Output
    }
    Else {
        $Input | Out-File $To
    }
}

$sArchive = $Archive
$sFile = $File
If ( $File -ne $null ) {
    $Matching = 'FullName'
}
ElseIf ( $FileName -ne $null ) {
    $sFile = $FileName
    $Matching = 'Name'
}
Else {
    ( "NO FILE TO EXTRACT FROM {0} IN -File OR -FileName" -f $sArchive ) | Write-Error
    Exit 255
}

If ( $sArchive -and ( Test-Path -LiteralPath $sArchive ) ) {

    $resolvedArchive = ( Convert-Path -LiteralPath $sArchive )
    
    $oArchive = [IO.Compression.ZipFile]::OpenRead( $resolvedArchive )
    Try {
        If ( $foundFiles = $oArchive.Entries.Where({ ( ( $_ | Select-Object -ExpandProperty $Matching ) -like $sFile ) -and ( ( $_.FullName -split '/' ).Count -le ( $MaxDepth + 1 ) ) } ) ) {
            $foundFiles |% {
                If ( $Content ) {

                    If ( $Metadata ) {
                        $_ | Write-ExtractedOutput -To:$To
                    }
                    
                    $TempFile = ( New-TemporaryFile )
                    
                    [IO.Compression.ZipFileExtensions]::ExtractToFile( $_, $TempFile, $true ) # overwrite=$true
                    Get-Content -LiteralPath $TempFile -Raw:$Raw | Write-ExtractedOutput -To:$To

                    Remove-Item -LiteralPath $TempFile -Force


                }
                Else {
                    $_ | Write-ExtractedOutput -To:$To
                }
            }
        }
        Else {
            ( "COULD NOT FIND FILE WITHIN ARCHIVE: {0} not in {1}" -f $sFile,$sArchive ) | Write-Error
        }
    }
    Finally {
        If ( $oArchive ) {
            $oArchive.Dispose()
        }
    }

}
Else {
    ( "COULD NOT FIND ARCHIVE: {0}" -f $sArchive ) | Write-Error
}
