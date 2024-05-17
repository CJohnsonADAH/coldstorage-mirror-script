Param(
    $Items
)

$global:gColdStorageCompareToZipCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gColdStorageCompareToZipCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath "ColdStorageZipArchives.psm1" )

$Packages = ( & coldstorage packages -Items $Items -Zipped -Mirrored )
$Packages |% {
    $Location = $_.FullName

    If ( $_.CSPackageZip ) {
        $ZipPath = ( $_.CSPackageZip.FullName )
        $ZipManifests = ( & expand-filefromarchive.ps1 -Archive:$ZipPath -FileName:'manifest-*.txt' -Metadata -Content -Raw )
        
        $aZipManifests = @{ }
        While ( $ZipManifests.Count -gt 0 ) {
            $pairZipManifests = ( $ZipManifests | Select-Object -First 2 )
            $ZipManifests = ( $ZipManifests | select-Object -Skip 2 )
            
            $File, $Text = $pairZipManifests
            $Name = $File.Name
            $aZipManifests[ $Name ] = $Text
        }
        $aZipManifests.Keys |% {
            
            $ManifestText = $aZipManifests[ $_ ]
            $CounterManifest = ( Join-Path $Location $_ )

            If ( Test-Path -LiteralPath $CounterManifest ) {
                
                $CounterText = ( Get-Content -LiteralPath $CounterManifest -Raw )
                $ManifestText | compare-manifests-from-pipeline.ps1 -To:( $CounterText )

            }
            
        }

    }
    Else {
        ( "NO ZIP?! {0}" -f $_.FullName ) | Write-Warning
    }

}


