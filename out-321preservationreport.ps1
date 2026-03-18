Param (
    [Parameter(ValueFromPipeline=$true)] $Item,
    $N=10000,
    $Output='text/plain',
    [switch] $Bags=$false,
    [switch] $WSFA=$false,
    [switch] $Flat=$false,
    $Log=$null,
    [switch] $Attn=$false,
    $AttnLog=$null,
    [switch] $Summary=$false
)


Begin {

    $ExitCode = 0

#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

    $global:g321PreservationReportCmd = $MyInvocation.MyCommand

        $modSource = ( $global:g321PreservationReportCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )

    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageData.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageRepositoryLocations.psm1" )
    Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStorageBagItDirectories.psm1" )

#############################################################################################################
## FUNCTIONS ################################################################################################
#############################################################################################################

    Function Get-321PRLocationSlug {
    Param( [Parameter(ValueFromPipeline=$true)] $Location )

        Begin { }

        Process {
            $LiteralPath = ( Get-FileLiteralPath -File:$Location )
            $FileObject = ( Get-FileObject -File:$LiteralPath )

            $Repo = ( $FileObject | Get-FileRepositoryLocation )
            If ( $Repo ) {
                $RepoPrefix = ( $FileObject | Get-FileRepositoryPrefix )

                Push-Location -LiteralPath:$Repo.FullName
                $RelPath = ( Resolve-Path $LiteralPath -Relative )
                Pop-Location

                $RelPath = ( Join-Path $RepoPrefix -ChildPath $RelPath )
            }
            Else {
                $RelPath = $LiteralPath
            }

            ( $RelPath -replace '[^A-Za-z0-9]+','' ) | Write-Output
            
        }

        End { }
    }

    Function Get-321PRLogFilePath {
    Param( [Parameter(ValueFromPipeline=$true)] $Location, $Container=$null, $Template="get-321preservationreport-{0}.log.txt" )

        Begin {
            $t0 = ( Get-Date )
        }

        Process {
            $sContainer = $Container
            If ( $Container -eq $null ) {
                $Props = ( $Location | Get-FileRepositoryProps )
                If ( $Props.SourceLocation -ne $null ) {
                    $sContainer = $Props.SourceLocation
                }
            }

            $SlugFromPath = ( $Location | Get-321PRLocationSlug )
            $LogFileName = ( $Template -f $SlugFromPath, $t0.ToString('yyyyMMddHHmmss') )
            ( Join-Path $sContainer -ChildPath $LogFileName ) | Write-Output
        }

        End { }

    }

    Function Write-321PreservationPackagesSummaryReport {
    Param( [Parameter(ValueFromPipeline=$true)] $Rpt )

        Begin {
            $Footnotes = @{ "CLOUD"="ZIPPED" }
        }

        Process {
            "COPY-1:`t{0:N0} total" -f $Rpt["PACKAGES"]

            $I = 1
            "MIRRORED", "CLOUD" |% {
                $I = $I + 1
                $Pct = ( 100.0 * $Rpt[ $_ ] / $Rpt["PACKAGES"] )
            
                $Label = ( "COPY-{0:N0}" -f $I  )
                $Ratio = ( "{0:N0} / {1:N0} {2} ({3:N2}% complete, {4:N0} to go)" -f $Rpt[ $_ ], $Rpt["PACKAGES"], $_.ToLower(), $Pct, ( $Rpt[ "PACKAGES" ] - $Rpt[ $_ ] ) )

                $Footnote = $null
                If ( $Footnotes.ContainsKey( $_ ) ) {
                    $Footnotes[ $_ ] |% {
                        $Pct = ( 100.0 * $Rpt[ $_ ] / $Rpt["PACKAGES"] )
                        $Adj = $_.ToLower()
                        $Footnote = ( "[{0:N0}/{1:N0}, {2:N2}% {3}]" -f $Rpt[ $_ ], $Rpt[ "PACKAGES" ], $Pct, $Adj, ( $Rpt[ "PACKAGES" ] - $Rpt[ $_ ] ) )
                    }
                }

                If ( $Footnote ) {
                    "{0}:`t{1}`t{2}" -f $Label, $Ratio, $Footnote | Write-Output
                }
                Else {
                    "{0}:`t{1}" -f $Label, $Ratio | Write-Output
                }
            }
        }

        End { }

    }


}

#############################################################################################################
## EXECUTION ################################################################################################
#############################################################################################################

Process {

    If ( $Item -eq $null ) {
        $oItem = ( Get-Item -LiteralPath:. -Force )
    }
    Else {
        $oItem = ( $Item | Get-FileObject )
    }

    $t0 = ( Get-Date ) 
    "START: {0} in {1}" -f $t0, $oItem.FullName | Write-Host -ForegroundColor Cyan

    Push-Location -LiteralPath:$oItem.FullName

    $sLog = $Log ; If ( $sLog -eq $null ) { $sLog = ( $oItem | Get-321PRLogFilePath -Template:'get-321preservationreport-{0}.log.txt' ) }
    $sAttnLog = $AttnLog ; If ( $sAttnLog -eq $null ) { $sAttnLog = ( $oItem | Get-321PRLogFilePath -Template:'get-321preservationreport-{0}-ATTN-{1}.log.txt' ) }

    $Location = ( Get-Item -LiteralPath . -Force )

    If ( $Flat ) {
        $out = ( Get-ChildItem -Directory |? { $_.Name -notlike '.*' } |? { $_.Name -notin @( 'ZIP' ) } )
    }
    ElseIf ( $WSFA ) {
        $out = ( Get-ChildItem -Directory |? { $_.Name -notlike '.*' } |? { $_.Name -notin @( 'ZIP' ) } |% { Get-ChildItem $_.FullName -Directory } )
    }
    Else {
        $out = ( Get-ChildItem -Directory -Recurse -Force |? { $_.Name -notlike '.*' } |? { $_.Name -notin @( 'ZIP' ) } |? {
            ( $_.Name -eq 'data' )
        } |% {
            $_.Parent
        } |? {
            ( $_ | Test-BagItFormattedDirectory )
        } |? {
            -Not ( $_ | Test-BagItFormattedDirectoryContent )
        } )
    }

    If ( $N -ne $null ) {
        $out = ( $out | Select-Object -First:$N )
    }

    $packages = ( $out | & get-itempackage-cs.ps1 -CheckMirrored -CheckZipped -CheckCloud )

    $packs = @{}
    $packs['~'] = ( $packages |? { Write-Progress -Id:101 -Activity:"Sorting and collating packages" -Status:( $_ | write-packages-report-cs.ps1 ) ;
        ( ( -Not ( $_ | test-cs-package-is.ps1 -Mirrored ) ) -or ( -Not ( $_.CSPackageZip.Count -gt 0 ) ) -or ( -Not ( $_.CloudCopy -ne $null ) ) )
    } )

    $packs['~m'] = ( $packs['~'] |? { Write-Progress -Id:101 -Activity:"Sorting and collating packages (mirrored copy)" -Status:( $_ | write-packages-report-cs.ps1 ) ; -Not ( $_ | test-cs-package-is.ps1 -Mirrored ) } )
    $packs['~z'] = ( $packs['~'] |? { Write-Progress -Id:101 -Activity:"Sorting and collating packages (zipped copy)" -Status:( $_ | write-packages-report-cs.ps1 ) ; -Not ( $_.CSPackageZip.Count -gt 0 ) } )
    $packs['~c'] = ( $packs['~'] |? { Write-Progress -Id:101 -Activity:"Sorting and collating packages (cloud copy)" -Status:( $_ | write-packages-report-cs.ps1 ) ; -Not ( $_.CloudCopy -ne $null ) } )
    
    Write-Progress -Id:101  -Activity:"Sorting and collating packages" -Status:"Done." -Completed

    $tN = ( Get-Date )

    $Rpt = [ordered] @{
        "LOCATION"=$Location.FullName
        "START"= $t0
        "END"=$tN
        "PACKAGES"=( $packages | Measure-Object ).Count
        "MIRRORED"=( ( $packages | Measure-Object ).Count - ( $packs['~m'] | Measure-Object ).Count )
        "ZIPPED"=( ( $packages | Measure-Object ).Count - ( $packs['~z'] | Measure-Object ).Count )
        "CLOUD"=( ( $packages | Measure-Object ).Count - ( $packs['~c'] | Measure-Object ).Count )
    }

    $oRpt = ( [PSCustomObject] $Rpt )

    If ( $Output -eq 'CSV' ) {
        $oRpt | ConvertTo-Csv -NoTypeInformation
    }
    ElseIf ( $Output -eq 'Object' ) {
        $oRpt | Write-Output
    }
    Else {
        $Rpt | Write-321PreservationPackagesSummaryReport

        $AttnRpt = $null
        If ( $Attn ) {
            $AttnRpt = @( )
            $packs['~'] |% {
                If ( -Not $Summary ) {
                    ( "ATTN: {0}" -f ( $_ | write-packages-report-cs.ps1 ) ) | Write-Host -ForegroundColor Yellow
                }
            
                $RepoLocation = ( $_ | Get-FileRepositoryLocation )
                If ( $RepoLocation ) {
                    Push-Location $RepoLocation.FullName
                    $RelPath = ( Resolve-Path -LiteralPath:$_.FullName -Relative )
                    $RepoPrefix = ( '{0}' -f ( $_ | Get-FileRepositoryPrefix ) )
                    Pop-Location
                }
                Else {
                    $RelPath = ( Resolve-Path $_.FullName -Relative )
                }

                $aAttn = [ordered] @{ "Path"=$RelPath ; "Repository"=$RepoPrefix ; "File"=$_.CSPackageCanonicalLocation }

                If ( $_.CSPackageMirrorCopy ) {
                    $aAttn[ 'Mirror' ] = $_.CSPackageMirrorCopy.FullName
                }
                Else {
                    $aAttn[ 'Mirror' ] = ""
                }
                If ( $_.CSPackageZip ) {
                    $aAttn[ 'Zip' ] = $_.CSPackageZipCanonical.FullName
                }
                Else {
                    $aAttn[ 'Zip' ] = ""
                }
                If ( $_.CSPackageCloudCopy ) {
                    $aAttn[ 'Cloud' ] = ( $_.CSPackageCloudCopy | ConvertTo-HttpDataString )
                    # URI=( 's3://{0}/{1}' -f $_.CSPackageCloudCopy.Bucket, $_.CSPackageCloudCopy.Key )
                }
                Else {
                    $aAttn[ 'Cloud' ] = ""
                }
                $AttnRpt = @( $AttnRpt ) + @( [PSCustomObject] $aAttn )
            }
            If ( $Summary ) {
                $AttnCount = ( $packs['~'] | Measure-Object ).Count
                If ( $AttnCount -gt 0 ) {
                    "ATTN:`t{0:N0} / {1:N0} ({2:N2}% complete)" -f $AttnCount, $Rpt[ "PACKAGES" ], ( 100.0* ( $Rpt[ "PACKAGES" ] - $AttnCount ) / $Rpt[ "PACKAGES" ] )
                }
            }

        }

    }
    "DONE: {0} ({1})" -f $tN, ($tN - $t0) | Write-Host -ForegroundColor Cyan

    If ( Test-Path -LiteralPath $sLog -PathType Leaf ) {
        $SkipCsvLines=1
    }
    Else {
        $SkipCsvLines=0
    }
    $Lines = ( $oRpt | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip:$SkipCsvLines )
    $Lines | Out-File -Encoding utf8 -Append -LiteralPath $sLog

    "LOG: {0}" -f $sLog | Write-Host -ForegroundColor Cyan

    If ( $Attn ) {
        If ( Test-Path -LiteralPath $sAttnLog -PathType Leaf ) {
            $SkipCsvLines=1
        }
        Else {
            $SkipCsvLines=0
        }
        If ( $AttnRpt -ne $null ) {
            $Lines = ( $AttnRpt | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip:$SkipCsvLines )
            $Lines | Out-File -Encoding utf8 -Append -LiteralPath $sAttnLog
        }
        Else {
            $aAttn = [ordered] @{ "Path"=$null ; "Repository"=$null ; "File"=$null ; "Mirror"=$null; "Zip"=$null; "Cloud"=$null }
            $Lines = ( [PSCustomObject] $aAttn | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip:$SkipCsvLines )
            $Lines | Out-File -Encoding utf8 -Append -LiteralPath $sAttnLog
        }

        "ATTN LOG: {0}" -f $sAttnLog | Write-Host -ForegroundColor Cyan
    }

    Pop-Location

}

End {
    Exit $ExitCode
}
