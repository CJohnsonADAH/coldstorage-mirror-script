Param (
    [Parameter(ValueFromPipeline=$true)] $Item,
    $N=$null,
    $Output='text/plain',
    $Header="~~~",
    $Footer="~~~",
    [switch] $Bags=$false,
    [switch] $WSFA=$false,
    [switch] $Flat=$false,
    $Log=$null,
    [switch] $Attn=$false,
    $AttnLog=$null,
    [switch] $Summary=$false,
    [switch] $Profile=$false
)


Begin {

    $ExitCode = 0
    $Process_Loops = 0

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

    Function Write-ProfileProgress {
    Param( [Parameter(ValueFromPipeline)] $Message, $tN, $Log=$null, $Activity="Processing", $Id=067 )

        Begin { }

        Process {
            $Status = ( '[{0}: {1}] {2}' -f ( $tN[-1] - $tN[-2] ), $tN[-1], $Message )
            Write-Progress -Id:$Id -Activity:$Activity -Status:$Status
            If ( $Log -ne $null ) {
                $SkipCsv = 0
                If ( Test-Path -LiteralPath:$Log ) {
                    $SkipCsv = 1
                }
                [PSCustomObject] @{ "t0"=$tN[0]; "tN"=$tN[-1]; "N"=( $tN | Measure-Object ).Count; "Message"=$status } | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip:$SkipCsv | Out-File -Encoding:utf8 -LiteralPath:$Log -Append
            }
        }

        End { }
    
    }

    If ( $Header ) {
        $Header -f ( Get-Date ) | Write-Host -ForegroundColor:Gray
    }

}

#############################################################################################################
## EXECUTION ################################################################################################
#############################################################################################################

Process {
    $Process_Loops = $Process_Loops + 1

    If ( $Item -eq $null ) {
        $oItem = ( Get-Item -LiteralPath:. -Force )
    }
    Else {
        $oItem = ( $Item | Get-FileObject )
    }

    If ( $Process_Loops -gt 1 ) {
        "" | Write-Host
    }

    $t0 = ( Get-Date ) ; $tN = @( $t0 )
    "START: {0} in {1}" -f $t0, $oItem.FullName | Write-Host -ForegroundColor Cyan

    Push-Location -LiteralPath:$oItem.FullName

    $sLog = $Log ; If ( $sLog -eq $null ) { $sLog = ( $oItem | Get-321PRLogFilePath -Template:'get-321preservationreport-{0}.log.txt' ) }
    $sAttnLog = $AttnLog ; If ( $sAttnLog -eq $null ) { $sAttnLog = ( $oItem | Get-321PRLogFilePath -Template:'get-321preservationreport-{0}-ATTN-{1}.log.txt' ) }
    
    $sProfileLog = $null
    If ( $Profile ) {
        $sProfileLog = ( $oItem | Get-321PRLogFilePath -Template:'get-321preservationreport-{0}-PROFILE-{1}.log.txt' )
    }

    $Location = ( Get-Item -LiteralPath . -Force )

    If ( $Profile ) {
        $tN += , ( Get-Date )
        'Collecting bagged directories' | Write-ProfileProgress -Log:$sProfileLog -tN:$tN
    }

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
            If ( $Profile ) {
                Write-Progress -Id:068 -Activity:"Screening" -Status:( '[{0}: {1}] Collecting bagged directories: {2}' -f ( (Get-Date) - $tN[-1] ), $tN[-1], $_.FullName )
            }
            -Not ( $_ | Test-BagItFormattedDirectoryContent )
        } )
    }

    If ( $N -ne $null ) {
        $out = ( $out | Select-Object -First:$N )
    }

    If ( $Profile ) {
        $tN += , ( Get-Date )
        $Nout = ( $out | Measure-Object ).Count
        ( '[{0:N0}x] $packages = ( $out | & get-itempackage-cs.ps1 -Check321 -Profile )' -f $Nout ) | Write-ProfileProgress -Log:$sProfileLog -tN:$tN
    }
    
    $packages = ( $out | & get-itempackage-cs.ps1 -Check321 -Profile:$Profile )

    If ( $Profile ) {
        $tN += , ( Get-Date )
        'Sorting and collating: ~' | Write-ProfileProgress -Log:$sProfileLog -tN:$tN
    }

    $packs = @{}
    $packs['~'] = ( $packages |? { Write-Progress -Id:101 -Activity:"Sorting and collating packages" -Status:( $_ | write-packages-report-cs.ps1 ) ;
        ( ( -Not ( $_ | test-cs-package-is.ps1 -Mirrored ) ) -or ( -Not ( $_.CSPackageZip.Count -gt 0 ) ) -or ( -Not ( $_.CloudCopy -ne $null ) ) )
    } )

    If ( $Profile ) {
        $tN += , ( Get-Date )
        'Sorting and collating: ~m' | Write-ProfileProgress -Log:$sProfileLog -tN:$tN
    }

    $packs['~m'] = ( $packs['~'] |? { Write-Progress -Id:101 -Activity:"Sorting and collating packages (mirrored copy)" -Status:( $_ | write-packages-report-cs.ps1 ) ; -Not ( $_ | test-cs-package-is.ps1 -Mirrored ) } )

    If ( $Profile ) {
        $tN += , ( Get-Date )
        'Sorting and collating: ~z' | Write-ProfileProgress -Log:$sProfileLog -tN:$tN
    }

    $packs['~z'] = ( $packs['~'] |? { Write-Progress -Id:101 -Activity:"Sorting and collating packages (zipped copy)" -Status:( $_ | write-packages-report-cs.ps1 ) ; -Not ( $_.CSPackageZip.Count -gt 0 ) } )

    If ( $Profile ) {
        $tN += , ( Get-Date )
        'Sorting and collating: ~c' | Write-ProfileProgress -Log:$sProfileLog -tN:$tN
    }

    $packs['~c'] = ( $packs['~'] |? { Write-Progress -Id:101 -Activity:"Sorting and collating packages (cloud copy)" -Status:( $_ | write-packages-report-cs.ps1 ) ; -Not ( $_.CloudCopy -ne $null ) } )

    If ( $Profile ) {
        $tN += , ( Get-Date )
        'Preparing report' | Write-ProfileProgress -Log:$sProfileLog -tN:$tN
    }
    
    Write-Progress -Id:101  -Activity:"Sorting and collating packages" -Status:"Done." -Completed

    $tN += , ( Get-Date )

    $Rpt = [ordered] @{
        "LOCATION"=$Location.FullName
        "START"= $t0
        "END"=$tN[-1]
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
    If ( $Profile ) {
        $tN += , ( Get-Date )
        'DONE: {0}' -f $oItem.FullName | Write-ProfileProgress -Log:$sProfileLog -tN:$tN
    }
    "DONE: {0} ({1})" -f $tN[-1], ($tN[-1] - $tN[0]) | Write-Host -ForegroundColor Cyan

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
            "ATTN LOG: {0}" -f $sAttnLog | Write-Host -ForegroundColor Cyan
        }
        Else {
            $aAttn = [ordered] @{ "Path"=$null ; "Repository"=$null ; "File"=$null ; "Mirror"=$null; "Zip"=$null; "Cloud"=$null }
            $Lines = ( [PSCustomObject] $aAttn | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip:$SkipCsvLines )
            $Lines | Out-File -Encoding utf8 -Append -LiteralPath $sAttnLog
        }

    }
    If ( $Profile ) {
        "PROFILE LOG: {0}" -f $sProfileLog | Write-Host -ForegroundColor Yellow
    }

    Pop-Location

}

End {
    If ( $Footer ) {
        $Footer -f ( Get-Date ), $ExitCode  | Write-Host -ForegroundColor:Gray
    }

    Exit $ExitCode
}
