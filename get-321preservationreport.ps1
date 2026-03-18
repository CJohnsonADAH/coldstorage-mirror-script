Param (
    $N=10000,
    $Output='text/plain',
    [switch] $Full=$false,
    [switch] $Attn=$false,
    [switch] $Summary=$false,
    [switch] $Bags=$false,
    [switch] $WSFA=$false,
    [switch] $Flat=$false,
    $Log=$null,
    $AttnLog=$null
)

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

Function Write-Attn {
Param( [Parameter(ValueFromPipeline=$true)] $Line )

    Begin { }

    Process {
        $_ | Write-Host -ForegroundColor:Yellow -BackgroundColor:Black
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


Function Get-321PRLocationSlug {
Param( [Parameter(ValueFromPipeline=$true)] $Location )

    Begin { }

    Process {
        $LiteralPath = ( Get-FileLiteralPath -File:$Location )
        $FileObject = ( Get-FileObject -File:$LiteralPath )

        $Repo = ( $FileObject | Get-FileRepositoryLocation )
        If ( $Repo ) {
            $RepoPrefix = ( $FileObject | Get-FileRepositoryPrefix )

            Push-Location $Repo.FullName
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

Function Add-321PackageDataMirrorCopy {
Param( [Parameter(ValueFromPipeline=$true)] $Package, $Location=$null, [switch] $PassThru=$false )

    Begin { }

    Process {
        $bMirrored = $false
        $oMirrorCopy = $null
        $sMirrorLocation = $null
        If ( ( $Location -ne $null ) -and ( $Location.Length -gt 0 ) ) {
            $sMirrorLocation = $Location
            If ( Test-Path -LiteralPath:$Location ) {
                $oMirrorCopy = ( Get-Item -LiteralPath:$Location -Force )
                $sMirrorLocation = $oMirrorCopy.FullName
                $bMirrored = $true
            }
        }

        $Package | Add-Member -MemberType:NoteProperty -Name:CSPackageCheckedMirrored -Value:$true -Force
        $Package | Add-Member -MemberType:NoteProperty -Name:CSPackageMirrored -Value:$bMirrored -Force
        $Package | Add-Member -MemberType:NoteProperty -Name:CSPackageMirrorCopy -Value:$oMirrorCopy -Force
        $Package | Add-Member -MemberType:NoteProperty -Name:CSPackageMirrorLocation -Value:$sMirrorLocation -Force
        
        If ( $PassThru ) {
            $Package | Write-Output
        }
    }

    End { }
}

Function Get-321PRPackage {
Param( [Parameter(ValueFromPipeline=$true)] $AttnRecord )

    Begin { }

    Process {
        If ( ( $_.File -ne $null ) -and ( $_.File.Length -gt 0 ) ) {
            $Item = ( Get-Item -LiteralPath:$_.File -Force )
            $Package = ( $Item | Get-ItemPackage -At )
        
            If ( $_.Mirror.Length -gt 0 ) {
                $Mirror = ( Get-Item -LiteralPath:$_.Mirror -Force )
            }
            Else {
                $Mirror = $null
            }
            If ( $_.Zip.Length -gt 0 ) {
                $Zip = ( Get-Item -LiteralPath:$_.Zip -Force )
            }
            Else {
                $Zip = $null
            }
            If ( $_.Cloud.Length -gt 0 ) {
                If ( $_.Cloud -match '^s3://' ) {
                    $s3 = [uri] $_.Cloud
                    $CloudHash = [Ordered] @{ "Key"=( $s3.AbsolutePath -replace '^/+','' ) ; "StorageClass"="DEEP_ARCHIVE"; "Bucket"=$s3.IdnHost }
                }
                Else {
                    $CloudHash = ( $_.Cloud | ConvertFrom-HttpDataString )
                }
                $Cloud = [PSCustomObject] $CloudHash

            }
            Else {
                $Cloud = $null
            }

            $Package | Add-321PackageDataMirrorCopy -Location:$Mirror.FullName
            $Package | Add-ItemPackageZipData -Zip:$Zip
            $Package | Add-ItemPackageCloudCopyData -CloudCopy:$Cloud
            $Package | Write-Output
        }
    }

    End { }

}


#############################################################################################################
## EXECUTION ################################################################################################
#############################################################################################################

$t0 = ( Get-Date ) 

If ( $Log -eq $null ) {
    $Props = ( Get-Location | Get-FileRepositoryProps )
    $LogContainer = $Props.SourceLocation
    $LogSlug = 'get-321preservationreport-{0}.log.txt'
    $PathSlug = ( Get-Location | Get-321PRLocationSlug )
    $LogSlug = ( $LogSlug -f ( $PathSlug ) )
    $Log = ( Join-Path $LogContainer -ChildPath $LogSlug )
}
If ( $AttnLog -eq $null ) {
    $Props = ( Get-Location | Get-FileRepositoryProps )
    $AttnLogContainer = $Props.SourceLocation
    $AttnLogSlug = 'get-321preservationreport-{0}-ATTN-*.log.txt'
    $AttnPathSlug = ( Get-Location | Get-321PRLocationSlug )
    $AttnLogSlug = ( $AttnLogSlug -f ( $AttnPathSlug ), ( $t0.ToString('yyyyMMddHHmmss') ) )
    $AttnLog = ( Join-Path $AttnLogContainer -ChildPath $AttnLogSlug )
}

If ( Test-Path -LiteralPath:$Log -PathType:Leaf ) {
    $oLog = ( Get-Item -LiteralPath:$Log -Force )
    $Rpt = ( Get-Content -LiteralPath:$oLog.FullName | ConvertFrom-Csv | Select-Object -Last:1 |% {
        $Dict = [ordered] @{ }
        $_.PSObject.Properties |% {
            $Dict[ $_.Name ] = $_.Value
        }
        $Dict | Write-Output
    } )
    "REPORTED: {0} - {1} ({2})" -f $Rpt[ "START" ], $Rpt[ "END" ], ( [DateTime]::Parse( $Rpt[ "END" ] ) - [DateTime]::Parse( $Rpt[ "START" ] ) ) | Write-Host -ForegroundColor:Cyan
    $Rpt | Write-321PreservationPackagesSummaryReport
    "" | Write-Host
}
Else {
    "START: {0}" -f $t0 | Write-Host -ForegroundColor Cyan
}
Push-Location -LiteralPath:$AttnLogContainer
If ( Test-Path -Path:$AttnLogSlug -PathType:Leaf ) {
    $oLog = ( Get-Item -Path:$AttnLogSlug -Force | Sort-Object -Property LastWriteTime -Descending | Select-Object -First:1 )

    $AttnObjects = ( Get-Content -LiteralPath:$oLog.FullName | ConvertFrom-Csv )
    $AttnLog = [ordered] @{ }
    If ( $Attn -and $Full ) {
        $AttnLog['ALL'] = $AttnObjects
    }
    ElseIf ( $Attn -and $Summary ) {
        $AttnLog = $null
    }
    ElseIf ( $Attn ) {
        $nAttn = ( $AttnObjects | Measure-Object ).Count
        If ( $nAttn -le 10 ) {
            $AttnLog['ALL'] = $AttnObjects
        }
        Else {
            $AttnLog['PRE'] = ( "- {0:N0} preservation packages need attention -" -f $nAttn )
            $AttnLog['START'] = ( $AttnObjects | Select-Object -First:10 )
            $AttnLog['DELIM'] = '[...]'
            $AttnLog['END'] = ( $AttnObjects | Select-Object -Last:10 )
        }
    }

    If ( $AttnLog -ne $null ) {
        $AttnLog.Keys |% {
            If ( $AttnLog[ $_ ] -is [string] ) {
                $AttnLog[ $_ ] | Write-Attn
            }
            Else {
                $AttnLog[ $_ ] |% {

                    $p = ( $_ | Get-321PRPackage )
                    If ( $p -ne $null ) {
                        $oContext = ( $p | Get-FileRepositoryLocation )
                        "ATTN: {0}" -f ( $p | write-packages-report-cs.ps1 -Context:$oContext.FullName ) | Write-Attn
                    }
                }
            }
        }
    }
}
Pop-Location

Exit 255

$Location = ( Get-Item -LiteralPath . -Force )

If ( $Flat ) {
    $out = ( Get-ChildItem -Directory |? { $_.Name -notlike '.*' } |? { $_.Name -notin @( 'ZIP' ) } )
}
ElseIf ( $WSFA ) {
    $out = ( Get-ChildItem -Directory |? { $_.Name -notlike '.*' } |? { $_.Name -notin @( 'ZIP' ) } |% { Get-ChildItem $_.FullName -Directory } )
}
Else {
    $out = ( Get-ChildItem -Directory -Recurse -Force |? { $_.Name -notlike '.*' } |? { $_.Name -notin @( 'ZIP' ) } |? {
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
$packs['~'] = ( $packages |? { Write-Progress ( $_ | write-packages-report-cs.ps1 ) ;
    ( ( -Not ( $_ | test-cs-package-is.ps1 -Mirrored ) ) -or ( -Not ( $_.CSPackageZip.Count -gt 0 ) ) -or ( -Not ( $_.CloudCopy -ne $null ) ) )
} )

$packs['~m'] = ( $packs['~'] |? { Write-Progress ( $_ | write-packages-report-cs.ps1 ) ; -Not ( $_ | test-cs-package-is.ps1 -Mirrored ) } )
$packs['~z'] = ( $packs['~'] |? { Write-Progress ( $_ | write-packages-report-cs.ps1 ) ; -Not ( $_.CSPackageZip.Count -gt 0 ) } )
$packs['~c'] = ( $packs['~'] |? { Write-Progress ( $_ | write-packages-report-cs.ps1 ) ; -Not ( $_.CloudCopy -ne $null ) } )

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
    "TOTAL: {0:N0}" -f $Rpt["PACKAGES"]

    "MIRRORED", "ZIPPED","CLOUD" |% {
        "{0}: {1:N0} / {2:N0} ({3:N2}% complete, {4:N0} remaining)" -f $_, $Rpt[ $_ ], $Rpt["PACKAGES"], (100.0*$Rpt[ $_ ]/$Rpt["PACKAGES"]), ( $Rpt[ "PACKAGES" ] - $Rpt[ $_ ] )
    }

    $AttnRpt = $null
    If ( $Attn ) {
        $AttnRpt = @( )
        $packs['~'] |% {
            If ( -Not $Summary ) {
                ( "ATTN: {0}" -f ( $_ | write-packages-report-cs.ps1 ) ) | Write-Host -ForegroundColor Yellow
            }
            
            $RepoLocation = ( $_ | Get-FileRepositoryLocation )
            If ( $RepoLocation ) {
                Push-Locaiton $RepoLocation.FullName
                $RelPath = ( Resolve-Path $_.FullName -Relative )
                $RepoPrefix = ( '$({0})' -f ( $_ | Get-FileRepositoryPrefix ) )
                $RelPath = ( $RelPath -replace '^.',$RepoPrefix )
                Pop-Location
            }
            Else {
                $RelPath = ( Resolve-Path $_.FullName -Relative )
            }

            $aAttn = [ordered] @{ "Path"=$RelPath ; "File"=$_.FullName ; "Repository"=$Repo }

            If ( $_.CSPackageMirrorCopy ) {
                $aAttn[ 'Mirror' ] = $_.CSPackageMirrorCopy.FullName
            }
            Else {
                $aAttn[ 'Mirror' ] = ""
            }
            If ( $_.CSPackageZip ) {
                $aAttn[ 'Zip' ] = $_.CSPackageZip.FullName
            }
            Else {
                $aAttn[ 'Zip' ] = ""
            }
            If ( $_.CSPackageCloudCopy ) {
                $aAttn[ 'Cloud' ] = ( 's3://{0}/{1}' -f $_.CSPackageCloudCopy.Bucket, $_.CSPackageCloudCopy.Key )
            }
            Else {
                $aAttn[ 'Cloud' ] = ""
            }
            $AttnRpt = @( $AttnRpt ) + @( [PSCustomObject] $aAttn )
        }
        If ( $Summary ) {
            $AttnCount = ( $packs['~'] | Measure-Object ).Count
            "ATTN: {0:N0} / {1:N0} ({2:N2}% complete)" -f $AttnCount, $Rpt[ "PACKAGES" ], ( 100.0* ( $Rpt[ "PACKAGES" ] - $AttnCount ) / $Rpt[ "PACKAGES" ] )
        }

    }

}
"DONE: {0} ({1})" -f $tN, ($tN - $t0) | Write-Host -ForegroundColor Cyan

If ( Test-Path -LiteralPath $Log -PathType Leaf ) {
    $SkipCsvLines=1
}
Else {
    $SkipCsvLines=0
}
$Lines = ( $oRpt | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip:$SkipCsvLines )
$Lines | Out-File -Encoding utf8 -Append -LiteralPath $Log

"LOG: {0}" -f $Log | Write-Host -ForegroundColor Cyan

If ( Test-Path -LiteralPath $AttnLog -PathType Leaf ) {
    $SkipCsvLines=1
}
Else {
    $SkipCsvLines=0
}
If ( $AttnRpt -ne $null ) {
    $Lines = ( $AttnRpt | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip:$SkipCsvLines )
    $Lines | Out-File -Encoding utf8 -Append -LiteralPath $AttnLog
}

"ATTN LOG: {0}" -f $AttnLog | Write-Host -ForegroundColor Cyan