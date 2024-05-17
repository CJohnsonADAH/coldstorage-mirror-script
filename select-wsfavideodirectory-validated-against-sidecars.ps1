 $Input |? {
    Push-Location $_.FullName
    Write-Progress $_.FullName
    
    Dir -File |% {
        $_ | test-wsfavideofile-against-sidecar.ps1
    }
    Dir -Directory |% {
        Dir $_.FullName |? { $_.Name -notlike '*.dpx' } | test-wsfavideofile-against-sidecar.ps1
    }
    Pop-Location
}