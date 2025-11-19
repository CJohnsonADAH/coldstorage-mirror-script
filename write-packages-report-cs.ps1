Param(
    [Parameter(ValueFromPipeline=$true)] $Package,
    [string] $Output="",
    [switch] $FullName=$false,
    $Timestamp=$null,
    $Context=$null
)

Begin {

    $Verbose = ( $MyInvocation.BoundParameters["Verbose"].IsPresent )
    $Verbose = $( If ( $Verbose -eq $null ) { $false } Else { $Verbose } )
    $Debug = ( $MyInvocation.BoundParameters["Debug"].IsPresent )
    $Debug = $( If ( $Debug -eq $null ) { $false } Else { $Debug } )

    # Internal Dependencies - Modules
    $global:gWritePackagesReportCSCmd = $MyInvocation.MyCommand

        $modSource = ( $global:gWritePackagesReportCSCmd.Source | Get-Item -Force )
        $modPath = ( $modSource.Directory | Get-Item -Force )

    Function Get-ScriptPath {
    Param ( $Command, $File=$null )

        $Source = ( $Command.Source | Get-Item -Force )
        $Path = ( $Source.Directory | Get-Item -Force )

        If ( $File -ne $null ) {
            $Path = ($Path.FullName | Join-Path -ChildPath $File)
        }

        $Path
    }

    $bVerboseModules = ( $Debug -eq $true )
    $bForceModules = ( ( $Debug -eq $true ) -or ( $psISE ) )

    Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( $modPath.FullName | Join-Path -ChildPath "ColdStorageInteraction.psm1" )
    Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( $modPath.FullName | Join-Path -ChildPath "ColdStorageSettings.psm1" )
    Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( $modPath.FullName | Join-Path -ChildPath "ColdStorageFiles.psm1" )
    Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( $modPath.FullName | Join-Path -ChildPath "ColdStoragePackagingConventions.psm1" )

    Function Select-CSFileInfo {
    Param( [Parameter(ValueFromPipeline=$true)] $File, [switch] $FullName, [switch] $ReturnObject )

        Begin { }

        Process {
            If ( $ReturnObject) {
                $File
            }
            ElseIf ( $FullName ) {
                $File.FullName
            }
            Else {
                $File.Name
            }
        }

        End { }
    }

    $global:gJsonOutBuffer = @()
    Function Write-CSPackagesReportJsonOutput {
    Param (
        [Parameter(ValueFromPipeline=$true)] $Object,
        [switch] $Flush=$false
    )

        Begin { }

        Process {
            If ( ( -Not $Flush ) -or ( $Object -ne $null ) ) {
                $global:gJsonOutBuffer += , $Object
            }
        }

        End {
            If ( $Flush ) {
                $global:gJsonOutBuffer | ConvertTo-Json | Write-Output
                $global:gJsonOutBuffer = @()
            }
        }
    }

    Function Write-ColdStoragePackagesReport {
    Param (
        [Parameter(ValueFromPipeline=$true)] $Package,
        [string] $Output="",
        [switch] $FullName=$false,
        [switch] $Subsequent=$false,
        $Timestamp=$null,
        $Context

    )

        Begin {
            If ( $Timestamp -eq $null ) {
                $Timestamp = ( Get-Date )
            }
            $sDate = ( Get-Date $Timestamp -Format "MM-dd-yyyy" )
        }

        Process {
        
            $CheckBagged = $Package.CSPackageCheckedBagged
            $CheckMirrored = $Package.CSPackageCheckedMirrored
            $CheckZipped = $Package.CSPackageCheckedZipped
            $CheckCloud = $Package.CSPackageCheckedCloud

            $oContext = ( Get-FileObject $Context )

            Push-Location -LiteralPath ( $oContext | Get-ItemFileSystemLocation ).FullName

            $sFullName = $Package.FullName
        
            $sRelName = ( Resolve-Path -Relative -LiteralPath $Package.FullName )
            $sTheName = $( If ( $FullName ) { $sFullName } Else { $sRelName } )

            $nBaggedFlag = $( If ( $Package.CSPackageBagged ) { 1 } Else { 0 } )
            $sBaggedFlag = $( If ( $Package.CSPackageBagged ) { "BAGGED" } Else { "unbagged" } )
            If ( $CheckZipped ) {
                $sZippedFlag = $( If ( $Package.CSPackageZip.Count -gt 0 ) { "ZIPPED" } Else { "unzipped" } )
                $nZippedFlag = $( If ( $Package.CSPackageZip.Count -gt 0 ) { 1 } Else { 0 } )
                $sZippedFile = $( If ( $Package.CSPackageZip.Count -gt 0 ) { $Package.CSPackageZip[0].Name } Else { "" } )
            }
            Else {
                $sZippedFlag = $null
                $sZippedFile = $null
            }
            $nContents = ( $Package.CSPackageContents )
            $sContents = ( "{0:N0} file{1}" -f $nContents, $( If ( $nContents -ne 1 ) { "s" } Else { "" } ))
            $nFileSize = ( $Package.CSPackageFileSize )
            $sFileSize = ( "{0:N0}" -f $Package.CSPackageFileSize )
            $sFileSizeReadable = ( "{0}" -f ( $Package.CSPackageFileSize | Format-BytesHumanReadable ) )
            $sBagFile = $( If ( $Package.CSPackageBagLocation ) { $Package.CSPackageBagLocation.FullName | Resolve-Path -Relative } Else { "" } )
            $sBaggedLocation = $( If ( $Package.CSPackageBagLocation -and ( $Package.CSPackageBagLocation.FullName -ne $Package.FullName ) ) { ( " # bag: {0}" -f ( $Package.CSPackageBagLocation.FullName | Resolve-PathRelativeTo -Base $Package.FullName ) ) } Else { "" } )

            Pop-Location

            If ( $CheckMirrored ) {
                $nMirroredFlag = $Package.CSPackageMirrored
                $sMirroredFlag = $( If ( $nMirroredFlag ) { "MIRRORED" } Else { "unmirrored" } )
                $sMirrorLocation = $Package.CSPackageMirrorLocation
            }

            $oCloudCopy = $null
            $sCloudCopyFlag = $null
            $nCloudCopyFlag = $null

            If ( $CheckCloud ) {

                If ( $Package.CloudCopy -and $sZippedFile ) {
                    $bCloudCopy = $true
                    $oCloudCopy = $Package.CloudCopy
                    $nCloudCopyFlag = 1
                    $sCloudCopyFlag = "CLOUD"
                }
                Else {
                    $bCloudCopy = $false
                    $oCloudCopy = $null
                    $nCloudCopyFlag = 0
                    $sCloudCopyFlag = "local"
                }

            }

            $o = [PSCustomObject] @{
                "Date"=( $sDate )
                "Name"=( $sTheName )
                "Bag"=( $sBaggedFlag )
                "BagFile"=( $sBagFile )
                "Bagged"=( $nBaggedFlag )
                "ZipFile"=( $sZippedFile )
                "Zipped"=( $nZippedFlag )
                "InZip"=( $sZippedFlag )
                "Mirrored"=( $nMirroredFlag )
                "MirrorLocation"=( $sMirrorLocation )
                "InMirror"=( $sMirroredFlag )
                "CloudFile"=( $oCloudCopy | Get-CloudStorageURI )
                "CloudTimestamp"=( $oCloudCopy | Get-CloudStorageTimestamp )
                "InCloud"=( $nCloudCopyFlag )
                "Clouded"=( $sCloudCopyFlag )
                "Files"=( $nContents )
                "Contents"=( $sContents )
                "Bytes"=( $nFileSize )
                "Size"=( $sFileSizeReadable )
                "Context"=( $oContext.FullName )
            }

            If ( $sZippedFlag -eq $null ) {
                $o.PSObject.Properties.Remove("ZipFile")
                $o.PSObject.Properties.Remove("Zipped")
                $o.PSObject.Properties.Remove("InZip")
            }
            If ( $sCloudCopyFlag -eq $null ) {
                $o.PSObject.Properties.Remove("CloudFile")
                $o.PSObject.Properties.Remove("CloudTimestamp")
                $o.PSObject.Properties.Remove("CloudBacked")
                $o.PSObject.Properties.Remove("Clouded")
            }

            If ( ("CSV","JSON") -ieq $Output ) {
                # Fields not used in CSV columns/JSON fields
                $o.PSObject.Properties.Remove("Bag")
                $o.PSObject.Properties.Remove("InZip")
                $o.PSObject.Properties.Remove("Clouded")

                # Output
                Switch ( $Output ) {
                    "JSON" { $o | Write-CSPackagesReportJsonOutput }
                    "CSV" { $o | ConvertTo-CSV -NoTypeInformation | Select-Object -Skip:$( If ($Subsequent) { 1 } Else { 0 } ) }
                }
            }
            ElseIf ( @( "OBJECT" ) -ieq $Output ) {
                $o | Write-Output
            }
            ElseIf ( @( "ITEM" ) -ieq $Output ) {
                $Package | Write-Output
            }
            Else {

                # Fields formatted for text report
                $sRptBagged = ( " ({0})" -f $o.Bag )
                $sRptZipped = $( If ( $o.Zipped -ne $null ) { ( " ({0})" -f $o.InZip ) } Else { "" } )
                $sRptMirrored = $( If ( $o.Mirrored -ne $null ) { ( " ({0})" -f $o.InMirror ) } Else { "" } )
                $sRptCloud = $( If ( $o.Clouded -ne $null ) { ( " ({0})" -f $o.Clouded ) } Else { "" } )

                # Output
                ( "{0}{1}{2}{3}{4}, {5}, {6}{7}" -f $o.Name,$sRptBagged,$sRptZipped,$sRptMirrored,$sRptCloud,$o.Contents,$o.Size,$sBaggedLocation )
            
            }

        }

        End { }
    }

    $Subsequent = $false

    $dTimestamp = $Timestamp
    If ( $Timestamp -eq $null ) {
        $dTimestamp = ( Get-Date )
    }

}

Process {
    $Package | Write-ColdStoragePackagesReport -Output:$Output -Timestamp:$dTimestamp -Context:$Context -Subsequent:$Subsequent
    $Subsequent = $true

}

End {
    If ( $global:gJsonOutBuffer ) {
        Write-CSPackagesReportJsonOutput -Flush
    }
}


