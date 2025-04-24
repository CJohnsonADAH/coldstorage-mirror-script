Param(
    [Parameter(ValueFromPipeline=$true)] $Item,
    [switch] $PassThru=$false
)

Begin {
    $ExitCode = 0
}

Process {
    $ItemCode = 0

    $Package = ( $Item | & coldstorage-get-packages.ps1 -Items -At -Bagged -Zipped )
    If ( $Package ) {
        $ZipContainer = ( $Package | & coldstorage-zip-packages.ps1 get -Items -Container )
        $SupersededPath = ( Join-Path $ZipContainer.FullName -ChildPath "Superseded" )
        $SupersededContainer = $null

        $Package.CSPackageZip |% {
            If ( $_ -ne $null ) {
                If ( -Not ( Test-Path -LiteralPath $SupersededPath -PathType Container ) ) {
                    $SupersededContainer = ( New-Item -ItemType Directory -Path $SupersededPath )
                }
                Else {
                    $SupersededContainer = ( Get-Item -LiteralPath $SupersededPath -Force )
                }

                If ( $SupersededContainer -ne $null ) {
            
                    Move-Item $_.FullName -Destination $SupersededContainer.FullName -Verbose

                }
            }
        }

        If ( ( $ItemCode -eq 0 ) -and $PassThru ) {
            $Package
        }

    }

    $ExitCode = $ExitCode + $ItemCode

}

End {
    Exit $ExitCode
}