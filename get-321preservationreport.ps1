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
Import-Module -Verbose:$false  $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )

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
    $Rpt | Write-321PreservationPackagesSummaryReport | Write-Host
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
        If ( $AttnSelect -is [ScriptBlock] ) {
            $AttnObjects = ( $AttnObjects | &$AttnSelect )
        }

        $nAttn = ( $AttnObjects | Measure-Object ).Count
        
        If ( $Output -ne 'text/plain' ) {
                $AttnLog['ALL'] = $AttnObjects
        }
        ElseIf ( $nAttn -le 10 ) {
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
                        If ( $Output -eq 'text/plain' ) {
                            $oContext = ( $p | Get-FileRepositoryLocation )
                            "ATTN: {0}" -f ( $p | write-packages-report-cs.ps1 -Context:$oContext.FullName ) | Write-Attn
                        }
                        ElseIf ( $Output -eq 'object' ) {
                            $p | Write-Output
                        }
                        Else {
                            $oContext = ( $p | Get-FileRepositoryLocation )
                            "ATTN: {0}" -f ( $p | write-packages-report-cs.ps1 -Context:$oContext.FullName ) | Write-Attn
                        }
                    }
                }
            }
        }
    }
}
Pop-Location

