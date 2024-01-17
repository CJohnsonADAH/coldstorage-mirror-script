<#
.SYNOPSIS
ADAHColdStorage Digital Preservation Packages reporting script
@version 2021.0617

.PARAMETER Diff
coldstorage mirror -Diff compares the contents of files and mirrors the new versions of files whose content has changed. Worse performance, more correct results.

.PARAMETER Batch
coldstorage mirror -Batch formats output for log files and channels it to easily redirectable stdout, error and warning output streams. Ideal for tasks run from Task Scheduler.

.DESCRIPTION
coldstorage mirror: Sync files to or from the ColdStorage server.
coldstorage bag: Package files into BagIt-formatted preservation packages
coldstorage zip: Zip preservation packages into cloud storage-formatted archival units
coldstorage to: send a preservation package or an archival unit to external preservation sites (cloud, drop, ...)
coldstorage vs: compare the packages preserved locally to those stored on an external preservation site (cloud, drop, etc.)
coldstorage check: Check for new preservation items in a repository to be packaged, and check the status of already-processed preservation packages
coldstorage stats: Compile statistics on the preservation packages in a repository
coldstorage packages: Output a report on the preservation packages in a repository
coldstorage validate: Validate BagIt-formatted preservation packages or cloud storage-formatted archival units
#>

Using Module ".\ColdStorageProgress.psm1"

param (
    [Parameter(Position=0)] [string] $Verb,
    [switch] $Development = $false,
    [switch] $Production = $false,
    [switch] $Help = $false,
    [switch] $Quiet = $false,
	[switch] $Batch = $false,
    [switch] $Interactive = $false,
    [switch] $Repository = $true,
    [switch] $Items = $false,
    [switch] $Recurse = $false,
    [switch] $At = $false,
    [switch] $NoScan = $false,
    [switch] $NoValidate = $false,
    [switch] $Force = $false,
    [switch] $FullName = $false,
    [switch] $Bagged = $false,
    [switch] $Unbagged = $false,
    [switch] $Zipped = $false,
    [switch] $Unzipped = $false,
    [switch] $Mirrored = $false,
    [switch] $NotMirrored = $false,
    [switch] $InCloud = $false,
    [switch] $NotInCloud = $false,
    [switch] $Only = $false,
    [switch] $PassThru = $false,
    [switch] $Report = $false,
    [switch] $ReportOnly = $false,
    [switch] $Dependencies = $false,
    $Props = $null,
    [String] $Output = "-",
    [switch] $Posted = $false,
    [String[]] $Side = "local,cloud",
    [String[]] $Name = @(),
    [String] $LogLevel=0,
    [switch] $Dev = $false,
    [switch] $Bork = $false,
    #[switch] $Verbose = $false,
    #[switch] $Debug = $false,
    [switch] $WhatIf = $false,
    [switch] $Version = $false,
    [string] $From,
    [string] $To,
    [Parameter(ValueFromRemainingArguments=$true, Position=1)] $Words,
    [Parameter(ValueFromPipeline=$true)] $Piped
)
$RipeDays = 7

$Verbose = ( $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent )
$Verbose = $( If ( $Verbose -eq $null ) { $false } Else { $Verbose } )
$Debug = ( $PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent )
$Debug = $( If ( $Debug -eq $null ) { $false } Else { $Debug } )

$global:gBucketObjects = @{ }

Function Test-CSDevelopmentBranchDir {
Param ( [Parameter(ValueFromPipeline=$true)] $Item=$null )

    Process {
        ( $Item.Name -like "*-development" )
    }

}
Function Get-CSProductionBranchDirName {
Param ( [Parameter(ValueFromPipeline=$true)] $Item=$null )

    Process {
        $Item.Parent.FullName | Join-Path -ChildPath ( $Item.Name -replace "-development$", "" )
    }

}
Function Get-CSDevelopmentBranchDirName {
Param ( [Parameter(ValueFromPipeline=$true)] $Item=$null )

    Process {
        $Item.Parent.FullName | Join-Path -ChildPath ( "{0}-development" -f ( $Item.Name -replace "-development$","" ) )
    }

}

Function Get-CSProductionBranchDir {
Param ( $File=$null )

    $ScriptPath = Get-Item -Force -LiteralPath ( Split-Path -Parent $PSCommandPath )
    $ScriptPath = $( If ($ScriptPath | Test-CSDevelopmentBranchDir) { $ScriptPath | Get-CSProductionBranchDirName } Else { $ScriptPath.FullName } )

    If ( $File -ne $null ) {
        ( Get-Item -Force -LiteralPath ( $ScriptPath | Join-Path -ChildPath $File ) )
    }
    Else {
        ( Get-Item -Force -LiteralPath ( $ScriptPath ) )
    }

}

Function Get-CSDevelopmentBranchDir {
Param ( $File=$null )

    $ScriptPath = Get-Item -Force -LiteralPath ( Split-Path -Parent $PSCommandPath )
    $ScriptPath = $( If ($ScriptPath | Test-CSDevelopmentBranchDir) { $ScriptPath.FullName } Else { $ScriptPath | Get-CSDevelopmentBranchDirName } )

    If ( $File -ne $null ) {
        ( Get-Item -Force -LiteralPath ( $ScriptPath | Join-Path -ChildPath $File ) )
    }
    Else {
        ( Get-Item -Force -LiteralPath ( $ScriptPath ) )
    }

}

# Do we need to hand off control to an alternate branch of the script?
If ( $Development -or $Production ) {
    $ps1 = $( If ($Development) { ( Get-CSDevelopmentBranchDir -File ( Split-Path -Leaf $PSCommandPath ) ) } Else { ( Get-CSProductionBranchDir -File ( Split-Path -Leaf $PSCommandPath ) ) } )
    $Branch = $( If ( $Development ) { "Development" } Else { "Production" } )
    If ( $ps1 ) {

        $aParameters = $MyInvocation.BoundParameters
        $aParameters[$Branch] = $False
        Write-Warning ( "[{0}] Invoking the {1} branch {2}" -f  $MyInvocation.MyCommand.Name, $Branch, $ps1.FullName )
        & ( "{0}" -f $ps1.FullName ) @aParameters
       
    }
    Else {
        Write-Warning ( "[{0}] Could not find {1} branch for {2}" -f $MyInvocation.MyCommand.Name, $Branch, $PSCommandPath )
    }
    Exit
}

Function ColdStorage-Script-Dir {
Param ( $File=$null )

    $ScriptPath = ( Split-Path -Parent $PSCommandPath )
    
    If ( $File -ne $null ) {
        $Item = ( Get-Item -Force -LiteralPath "${ScriptPath}\${File}" )
    }
    Else {
        $Item = ( Get-Item -Force -LiteralPath $ScriptPath )
    }

    $Item
}

# External Dependencies - Modules
Import-Module -Verbose:$false BitsTransfer
Import-Module -Verbose:$false Posh-SSH

# Internal Dependencies - Modules
$bVerboseModules = ( $Debug -eq $true )
$bForceModules = ( ( $Debug -eq $true ) -or ( $psISE ) )

Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStorageInteraction.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStorageSettings.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStorageFiles.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStorageRepositoryLocations.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStoragePackagingConventions.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStorageScanFilesOK.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStorageBagItDirectories.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStorageBaggedChildItems.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStorageStats.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStorageZipArchives.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStorageToCloudStorage.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "ColdStorageToADPNet.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( ColdStorage-Script-Dir -File "LockssPluginProperties.psm1" )

$global:gCSScriptName = $MyInvocation.MyCommand
$global:gCSScriptPath = $MyInvocation.MyCommand.Definition

If ( $global:gScriptContextName -eq $null ) {
    $global:gScriptContextName = $global:gCSScriptName
}

$ColdStorageER = "\\ADAHColdStorage\ADAHDATA\ElectronicRecords"
$ColdStorageDA = "\\ADAHColdStorage\ADAHDATA\Digitization"

Function Get-CurrentLine {
    $MyInvocation.ScriptLineNumber
}

Function Get-CSGPCommandWithVerb {
    $global:gCSGPCommandWithVerb
}

#############################################################################################################
## COMMAND FUNCTIONS ########################################################################################
#############################################################################################################

Function Do-Make-Bagged-ChildItem-Map {
Param( $LiteralPath=$null, $Path=$null, [switch] $Zipped=$false, [switch] $Only=$false )

    Get-BaggedChildItem -LiteralPath $LiteralPath -Path $Path -Zipped:${Zipped} | % {
        $_.FullName
    }
}

Function Invoke-ColdStorageCheckFile {

    [CmdletBinding()]

param (
    [Switch]
    $Quiet,

    [String]
    $Exclude="^$",

    [ScriptBlock]
    $OnBagged={ Param($File, $Payload, $BagDir, $Quiet); $PayloadPath = $Payload.FullName; Write-BaggedItemNoticeMessage -File $File -Item:$File -Message " = ${PayloadPath}" -Line ( Get-CurrentLine ) -Zip -Verbose -Quiet:$Quiet },

    [ScriptBlock]
    $OnDiff={ Param($File, $Payload, $Quiet); Write-Warning ( "DIFF: {0}, {1}" -f ( $File,$Payload ) ) },

    [ScriptBlock]
    $OnUnbagged={ Param($File, $Quiet); Write-UnbaggedItemNoticeMessage -File $File -Line ( Get-CurrentLine ) -Quiet:$Quiet },

    [ScriptBlock]
    $OnZipped={ Param($File, $Quiet); $FilePath = $File.FullName; If ( -Not $Quiet )  { Write-Verbose "ZIP: ${FilePath}" } },

    $Progress=$null,

    [Parameter(ValueFromPipeline=$true)]
    $File
)

    Begin {
        if ( $Exclude.Length -eq 0 ) {
            $Exclude = "^$"
        }

    }

    Process {
        
        $Parent = $File.Directory
        Push-Location $Parent

        $FileName = $File.Name
        $FilePath = $File.FullName
        $CardBag = ( $File | Get-PathToBaggedCopyOfLooseFile -Wildcard )

        If ( $Progress -ne $null ) {
            $Progress.Activity = ( "{0}: {1}" -f ( $Progress.Activity -replace ": [^:]+$","" ), $File.CheckedSpace )
            $Progress.Update( ( "Check FILE: {0} ... {1}" -f $File.Directory.Name, $File.Name ), 10, 100 )
        }

        $BagPayload = $null
        If ( Test-ZippedBag($File) ) {
            $BagPayload = $File
            $OnZipped.Invoke($File, $Quiet)
        }
        Else {
            ( $Bag = Get-BaggedCopyOfLooseFile -File $File ) | Select-BagItPayload |% {
                $BagPayload = $_
                
                If ( -Not ( Test-DifferentFileContent -From $File -To $BagPayload ) ) {
                    $OnBagged.Invoke($File, $BagPayload, $Bag, $Quiet)
                }
                Else {
                    $OnDiff.Invoke($File, $BagPayload, $Quiet )
                }
            }
        }

        if ( -Not $BagPayload ) {
            $OnUnbagged.Invoke($File, $Quiet)
        }

        Pop-Location

    }

    End {
        if ( -Not $Quiet ) {
            Write-BleepBloop
        }
    }

}

Function Invoke-ColdStorageCheckFolder {

    [CmdletBinding()]

param (
    [Switch]
    $Quiet,

    [Switch]
    $Batch=$false,

    [String]
    $Exclude="^$",

    $Progress=$null,

    [Parameter(ValueFromPipeline=$true)]
    $File
)

    Begin {
        if ( $Exclude.Length -eq 0 ) {
            $Exclude = "^$"
        }
    }

    Process {
        $Anchor = $PWD

        $DirName = Get-FileLiteralPath -File $File
        $BaseName = $File.Name

        If ( $Progress -ne $null ) {
            $Progress.Activity = ( "{0}: {1}" -f ( $Progress.Activity -replace ": [^:]+$","" ), $File.CheckedSpace )
            $Progress.Update( ( "Check DIR: {0} ... {0}" -f ( $File.Parent, $BaseName ) ), 60, 100 )
        }

        If ( $File | Test-ColdStoragePropsDirectory ) {
        # Is this a props directory?

            # NOOP

        }
        ElseIf ( Test-ERInstanceDirectory($File) ) {
        # Is this an ER Instance directory?
            
            Push-Location $DirName

            If ( -not ( $BaseName -match $Exclude ) ) {

                if ( Test-BagItFormattedDirectory($File) ) {
                    Write-BaggedItemNoticeMessage -File $File -Item:$File -Zip -Quiet:$Quiet -Line ( Get-CurrentLine )

                } else {
                    Write-UnbaggedItemNoticeMessage -File $File -Quiet:$Quiet -Line ( Get-CurrentLine )
                }
            }
            Else {
                Write-BaggedItemNoticeMessage -Status "SKIPPED" -File $File -Item:$File -Quiet:$Quiet -Line ( Get-CurrentLine )
            }

            Pop-Location

        }
        ElseIf ( Test-BagItFormattedDirectory($File) ) {
            Write-BaggedItemNoticeMessage -File:$File -Item:$File -Zip -Quiet:$Quiet -Verbose -Line ( Get-CurrentLine )
        }
        ElseIf ( Test-IndexedDirectory($File) ) {
            Write-UnbaggedItemNoticeMessage -File $File -Message "indexed directory" -Quiet:$Quiet -Line ( Get-CurrentLine )
        }
        Else {

            Push-Location $DirName
            
            Get-ChildItem -File | Add-Member -NotePropertyName "CheckedSpace" -NotePropertyValue ( $File.CheckedSpace ) -PassThru | Invoke-ColdStorageCheckFile -Progress:$Progress -Quiet:$Quiet
            Get-ChildItem -Directory |? { -Not ( $_ | Test-BaggedCopyOfLooseFile ) } | Add-Member -NotePropertyName "CheckedSpace" -NotePropertyValue ( $File.CheckedSpace ) -PassThru | Invoke-ColdStorageCheckFolder -Progress:$Progress -Quiet:$Quiet

            Pop-Location

        }
    }

    End {
        if ( $Quiet -eq $false ) {
            Write-BleepBloop
        }
    }
}

Function Get-CSItemValidation {

Param ( [Parameter(ValueFromPipeline=$true)] $Item, [switch] $Summary=$true, [switch] $PassThru=$false )

Begin {
    $nChecked = 0
    $nValidated = 0
}

Process {
    $Item | Get-Item -Force | %{
        $sLiteralPath = Get-FileLiteralPath -File $_

        $Validated = $null
        If ( Test-BagItFormattedDirectory -File $sLiteralPath ) {
            $Validated = ( Test-CSBaggedPackageValidates -DIRNAME $_ -Verbose:$Verbose  )
            $ValidationMethod = "BagIt"
        }
        ElseIf ( Test-ZippedBag -LiteralPath $sLiteralPath ) {
            $Validated = ( $_ | Test-ZippedBagIntegrity  )
            $ValidationMethod = "ZIP/MD5"
        }

        $nChecked = $nChecked + 1
        $nValidated = $nValidated + $Validated.Count

        If ( $PassThru ) {
            If ( $Validated.Count -gt 0 ) {
                $_ | Add-Member -MemberType NoteProperty -Name CSItemValidated -Value $Validated -PassThru | Add-Member -MemberType NoteProperty -Name CSItemValidationMethod -Value $ValidationMethod -PassThru
            }
            Else {
                $Validated | Write-Warning
            }
        }
        Else {
            $Validated # > stdout
        }
    }
}

End {

    $sSummaryOut = "Validation: ${nValidated} / ${nChecked} validated OK."
    If ( $Summary ) {
        
        If ( $PassThru ) {
            $sSummaryOut | Write-Warning
        }
        Else {
            $sSummaryOut | Write-Output
        }
    }
    ElseIf ( $nChecked -gt $nValidated ) {
        $sSummaryOut | Write-Warning
    }

}

}

Function Invoke-ColdStorageDirectoryCheck {
Param ($Pair, $From, $To, [switch] $Batch=$false)

    Push-Location $From

    $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
    $Progress.Open( ( "Checking {0}" -f $From ), "Files" )
    $Progress.Update( "Files", 1, 100 )

    Get-ChildItem -File | Add-Member -NotePropertyName "CheckedSpace" -NotePropertyValue $From -PassThru | Invoke-ColdStorageCheckFile -Progress:$Progress -Quiet:$Quiet

    $Progress.Update( "Directories", 51, 100 )

    Get-ChildItem -Directory |? { -Not ( $_ | Test-BaggedCopyOfLooseFile ) } | Add-Member -NotePropertyName "CheckedSpace" -NotePropertyValue $From -PassThru | Invoke-ColdStorageCheckFolder -Progress:$Progress -Quiet:$Quiet -Exclude $null

    $Progress.Completed()

    Pop-Location

}

Function Invoke-ColdStorageItemCheck {
Param ( [Parameter(ValueFromPipeline=$true)] $Item )

    Begin { }

    Process {
        $File = Get-FileObject($Item)
        If ( $File ) {
            $Pair = ($Item | Get-FileRepositoryName)
            Invoke-ColdStorageDirectoryCheck -Pair:$Pair -From:$File.FullName -To:$File.FullName -Batch:$Batch
        }
        Else {
            ( "[{0}] Item Not Found: {1}" -f ( Get-CommandWithVerb ), $Item ) | Write-Warning
        }
    }

    End { }

}


Function Invoke-ColdStorageRepositoryCheck {
Param ( $Pairs=$null )

    $mirrors = ( Get-ColdStorageRepositories )

    if ( $Pairs.Count -lt 1 ) {
        $Pairs = $mirrors.Keys
    }

    $i = 0
    $N = $Pairs.Count
    $Pairs | ForEach {
        $Pair = $_
        if ( $mirrors.ContainsKey($Pair) ) {
            $locations = $mirrors[$Pair]

            $slug = $locations[0]
            $src = $locations[2]
            $dest = $locations[1]

            Invoke-ColdStorageDirectoryCheck -Pair "${Pair}" -From "${src}" -To "${dest}"
        } else {
            $recurseInto = @( )
            $mirrors.Keys | ForEach {
                $subPair = $_
                $locations = $mirrors[$subPair]
                $slug = $locations[0]
                $src = $locations[2]
                $dest = $locations[1]
        
                if ( $slug -eq $Pair ) {
                    $recurseInto += @( $subPair )
                }
            }

            If ( $recurseInto.Count -gt 0 ) {
                Invoke-ColdStorageRepositoryCheck -Pairs $recurseInto
            }
        } # if

        $i = $i + 1
    }

}

Function Invoke-ColdStorageValidate ($Pairs=$null, [switch] $Verbose=$false, [switch] $Zipped=$false, [switch] $Batch=$false) {
    $mirrors = ( Get-ColdStorageRepositories )

    If ( $Pairs.Count -lt 1 ) {
        $Pairs = $mirrors.Keys
    }

    $i = 0
    $N = $Pairs.Count
    $Pairs | ForEach {
        $Pair = $_
        if ( $mirrors.ContainsKey($Pair) ) {
            $locations = $mirrors[$Pair]

            $slug = $locations[0]
            $src = $locations[2]
            $dest = $locations[1]

            $MapFile = ( "${src}" | Join-Path -ChildPath "validate-bags.map.txt" )
            $BookmarkFile = ( "${src}" | Join-Path -ChildPath "validate-bags.bookmark.txt" )

            If ( -Not ( Test-Path -LiteralPath $MapFile ) ) {
                Do-Make-Bagged-ChildItem-Map $src -Zipped:$Zipped > $MapFile
            }
            
            If ( -Not ( Test-Path -LiteralPath $BookmarkFile ) ) {
                $BagRange = @( Get-Content $MapFile -First 1 )
                $BagRange += $BagRange[0]
                $BagRange > $BookmarkFile
            }
            Else {
                $BagRange = ( Get-Content $BookmarkFile )
            }

            $CompletedMap = $false
            $EnteredRange = $false
            $ExitedRange = $false

            $MapLines = Get-Content $MapFile
            $nTotal = $MapLines.Count
            $nGlanced = 0
            $nChecked = 0
            $nValidated = 0

            $sValidatingCount = "Validating {0:N0} BagIt Directories{1} in {2}"
            $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
            $Progress.Open( ( $sValidatingCount -f $nTotal, "", $Pair ), "...", $nTotal )
            $MapLines | % {
                $nGlanced = $nGlanced + 1
                $BagPathLeaf = (Split-Path -Leaf $_)
                $Progress.Update( ( "#{0:N0}. Considering: {1}" -f ($Progress.I + 1),$BagPathLeaf ) )

                If ( -Not $EnteredRange ) {
                    $EnteredRange = ( $BagRange[0] -eq $_ )
                }
                
                If ( $EnteredRange ) {
                    If ( -Not $ExitedRange ) {
                        $ExitedRange = ( $BagRange[1] -eq $_ )
                    }

                    If ( $ExitedRange ) {

                        $BagRange[1] = $_
                        $BagRange > $BookmarkFile
                                
                        $BagPath = Get-FileLiteralPath -File $_
                        $Progress.Update( ( "#{0:N0}. Validating: {1}" -f $Progress.I, $BagPathLeaf ), 0 )

                        $Validated = ( $BagPath | Get-CSItemValidation -Verbose:$Verbose -Summary:$false )
                        
                        $nChecked = $nChecked + 1
                        $nValidated = $nValidated + $Validated.Count

                        $Progress.Activity = ( $sValidatingCount -f $nTotal, ( " [{0:N0}/{1:N0}]" -f $nValidated,$nChecked ), $Pair )

                        $Validated | Write-Output
                    }

                }
            }
            $Progress.Completed()

            "${nValidated}/${nChecked} BagIt packages validated OK." | Write-Output

            $nValidationFailed = ($nChecked - $nValidated)
            If ( $nValidationFailed -gt 0 ) {
                Write-Warning "${nValidationFailed}/${nChecked} BagIt packages failed validation!" # > stdwarn
            }
            $CompletedMap = $true

            If ( $CompletedMap ) {
                Remove-Item -LiteralPath $MapFile -Verbose:$Verbose
                Remove-Item -LiteralPath $BookmarkFile -Verbose:$Verbose
            }

        } else {
            $recurseInto = @( )
            $mirrors.Keys | ForEach {
                $subPair = $_
                $locations = $mirrors[$subPair]
                $slug = $locations[0]
                $src = $locations[2]
                $dest = $locations[1]
        
                if ( $slug -eq $Pair ) {
                    $recurseInto += @( $subPair )
                }
            }
            If ( $recurseInto.Count -gt 0 ) {
                Invoke-ColdStorageValidate -Pairs $recurseInto -Verbose:$Verbose -Zipped:$Zipped
            }
        } # if

        $i = $i + 1
    }

}

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

Function Write-ColdStoragePackagesReport {
Param (
    [Parameter(ValueFromPipeline=$true)] $Package,
    [switch] $Report=$false,
    [string] $Output="",
    [switch] $FullName=$false,
    [switch] $CheckZipped=$false,
    [switch] $CheckMirrored=$false,
    [switch] $CheckCloud=$false,
    $Timestamp,
    $Context

)

    Begin { $Subsequent = $false; $sDate = ( Get-Date $Timestamp -Format "MM-dd-yyyy" ); $aBucketListings = @{}; $jsonOut = @() }

    Process {

        $oContext = ( Get-FileObject $Context )

        Push-Location ( $oContext | Get-ItemFileSystemLocation ).FullName

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

        If ( $Report ) {

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
                    "JSON" { $jsonOut += , $o }
                    "CSV" { $o | ConvertTo-CSV -NoTypeInformation | Select-Object -Skip:$( If ($Subsequent) { 1 } Else { 0 } ) }
                }
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
        Else {
            
            $o = $_
            #If ( $oCloudCopy -ne $null ) {
            #    $o | Add-Member -MemberType NoteProperty -Name CloudCopy -Value $oCloudCopy -Force
            #}

            $o | Select-CSFileInfo -FullName:$FullName -ReturnObject:(-Not $FullName)
        }

        $Subsequent = $true

    }

    End { If ( $jsonOut ) { $jsonOut | ConvertTo-Json } }
}

Function Select-ColdStoragePackagesToReport {
Param (
    [Parameter(ValueFromPipeline=$true)] $Package,
    [switch] $Bagged,
    [switch] $Zipped,
    [switch] $Unbagged,
    [switch] $Unzipped,
    [switch] $Mirrored,
    [switch] $NotMirrored,
    [switch] $InCloud,
    [switch] $NotInCloud,
    [switch] $Only
)

    Begin { }

    Process {
        $BaggedOnly = ( $Bagged -and $Only )
        $ZippedOnly = ( $Zipped -and $Only )
        $MirroredOnly = ( $Mirrored -and $Only )
        $InCloudOnly = ( $InCloud -and $Only )

        $ok = @( )
        If ( $BaggedOnly ) {
            $ok += , ( $Package.CSPackageBagged )
        }
        If ( $Unbagged ) {
            $ok += , ( -Not ( $Package.CSPackageBagged ) )
        }
        If ( $ZippedOnly ) {
            $ok += , ( -Not ( -Not ( $Package.CSPackageZip ) ) )
        }
        If ( $Unzipped ) {
            $ok += , ( -Not ( $Package.CSPackageZip ) )    
        }
        If ( $MirroredOnly ) {
            $ok += , ( -Not ( -Not ( $Package.CSPackageMirrored ) ) )
        }
        If ( $NotMirrored ) {
            $ok += , ( -Not ( $Package.CSPackageMirrored ) )
        }
        If ( $InCloudOnly ) {
            $ok += , ( -Not ( -Not ( $Package.CloudCopy ) ) )
        }
        If ( $NotInCloud ) {
            $ok += , ( -Not ( $Package.CloudCopy ) )
        }

        $mTests = ( $ok | Measure-Object -Sum )
        If ( $mTests.Count -eq $mTests.Sum ) {
            $_
        }
    }

    End { }
}

Function Invoke-ColdStoragePackagesReport {
Param (
    [Parameter(ValueFromPipeline=$true)] $Location,
    [switch] $Recurse,
    [switch] $ShowWarnings,
    [switch] $Bagged,
    [switch] $Unbagged,
    [switch] $Zipped,
    [switch] $Unzipped,
    [switch] $Mirrored,
    [switch] $NotMirrored,
    [switch] $InCloud,
    [switch] $NotInCloud,
    [switch] $Only,
    [switch] $FullName,
    [switch] $Report,
    [switch] $At,
    [string] $Output
)

    Begin { $CurDate = ( Get-Date ) }

    Process {
        $CheckZipped = ( $Unzipped -or $Zipped -or $InCloud -or $NotInCloud )
        $CheckMirrored = ( $Mirrored -or $NotMirrored )
        $CheckCloud = ( $InCloud -or $NotInCloud )

        $Location | Get-ChildItemPackages -Recurse:$Recurse -At:$At -ShowWarnings:$ShowWarnings -CheckZipped:$CheckZipped -CheckMirrored:$CheckMirrored -CheckCloud:$CheckCloud |
            Select-ColdStoragePackagesToReport -Bagged:$Bagged -Zipped:$Zipped -Unbagged:$Unbagged -Unzipped:$Unzipped -Mirrored:$Mirrored -NotMirrored:$NotMirrored -InCloud:$InCloud -NotInCloud:$NotInCloud -Only:$Only |
            Write-ColdStoragePackagesReport -Report:$Report -Output:$Output -CheckZipped:$CheckZipped -CheckMirrored:$CheckMirrored -CheckCloud:$CheckCloud -FullName:$FullName -Context:$Location -Timestamp:$CurDate
    }

    End { }

}

# formerly known as: Do-Write-Usage
Function Get-CSUsageNotes {
Param ($cmd)

    $mirrors = ( Get-ColdStorageRepositories )

    $Pairs = ( $mirrors.Keys -Join "|" )
    $PairedCmds = ("bag", "zip", "validate")
    $ItemsCmds = ("to cloud", "to adpnet")
    "Usage: `t$cmd mirror [-Batch] [-Diff] [$Pairs]" | Write-Output
    $PairedCmds |% {
        $verb = $_
        "       `t${cmd} ${verb} [$Pairs]" | Write-Output
    }
    $ItemsCmds |% {
        $verb = $_
        "       `t${cmd} ${verb} [-Diff] [-Batch] -Items PATH1 [PATH2]..." | Write-Output
    }
    "       `t${cmd} -?" | Write-Output
    "       `t`tfor detailed documentation" | Write-Output
}

Function Get-CSScriptVersion {
Param ( [string] $Verb="", $Words=@( ), $Flags=@{ } )

    $oHelpMe = ( Get-Help ${global:gCSScriptPath} )
    $ver = ( $oHelpMe.Synopsis -split "@" |% { If ( $_ -match '^version\b' ) { $_ } } )
    If ( $ver.Count -gt 0 ) { Write-Output "${global:gCSScriptName} ${ver}" }
    Else { $oHelpMe }

}

Function Invoke-BatchCommandEpilog {
Param ( $Start, $End )

    ( "Completed: {0}" -f $End ) | Write-Output
    ( New-Timespan -Start:$Start -End:$End ) | Write-Output

}

Function Out-CSStream {
Param( [Parameter(ValueFromPipeline=$true)] $Line, [String] $Stream )

    Begin { }

    Process {
        $JsonLines = ( $Line | Get-Member -MemberType NoteProperty |% { $PropName=$_.Name ; ( "{0}={1}" -f ${PropName}, ( $Line.${PropName} | Convertto-Json -Compress ) ) } )
        Switch ( $Stream )
        {
            "Verbose" { $JsonLines | Write-Verbose }
            "Debug" { $JsonLines | Write-Debug }
            "Warning" { $JsonLines | Write-Warning }
            "Error" { $JsonLines | Write-Error }
            default { $Line | Format-Table 'VERB', 'WORDS', 'FLAGS', "PIPED" | Write-Output }

        }
                
    }

    End { }

}

Function Out-CSData {
Param ( [String] $Output="" )

    Switch ( $Output ) {
        "CSV" { $Input | ConvertTo-Csv -NoTypeInformation }
        "JSON" { $Input | ConvertTo-Json }
        default { $Input | Write-Output }
    }

}

Function Get-CSPackagesToBag {
Param ( [Parameter(ValueFromPipeline=$true)] $Item, [switch] $Recurse=$false, [switch] $At=$false, [switch] $PassThru=$false )

    Begin { }

    Process {
        If ( $Recurse ) {
            $Item | Get-ChildItemPackages -Recurse:$Recurse -At:$At |? { ( ( $PassThru ) -Or ( -Not $_.CSPackageBagged ) ) }
        }
        Else {
            $Item
        }
    }

    End {
    }
}

Function Select-CSInCloud {
Param ( [Parameter(ValueFromPipeline=$true)] $Item, [switch] $NotInCloud, [string] $From, [string] $To )

    Begin { }

    Process {
        If ( $Item | Get-Member -Name CloudCopy ) {
        # Is this a preservation package with CloudCopy already added (either filled or nulled)? If so, use that.
            $oPackage = $Item
        }
        Else {
        # If not, then use Get-ItemPackage to get it.
            $oPackage = ( $Item | Get-ItemPackage -CheckZipped -CheckCloud )
        }
        $CloudCopy = $oPackage.CloudCopy

        If ( $NotInCloud ) {
            $bTest = ( $oPackage.CloudCopy -eq $null )
        }
        Else {
            $bTest = ( $oPackage.CloudCopy -ne $null )
        }

        If ( $bTest ) { $oPackage }
    }

    End { }

}

Function Select-CSHasDate {
Param ( [Parameter(ValueFromPipeline=$true)] $Item, [switch] $InCloud, [switch] $NotInCloud, [string] $From, [string] $To )

    Begin { }

    Process {
        If ( $InCloud ) {
            $Item | Select-CSDatedObject -From:$From -To:$To -DatePicker { Process { $_.CloudCopy } } -MemberName:"LastModified"
        }
        Else {
            $Item | Select-CSDatedObject -From:$From -To:$To -MemberName:"LastWriteTime"
        }
    }

    End { }

}

$sCommandWithVerb = ( $MyInvocation.MyCommand |% { "$_" } )
$global:gCSCommandWithVerb = $sCommandWithVerb

If ( $Verbose ) {
    $VerbosePreference = "Continue"
}

If ( $Help -eq $true ) {
    Get-CSUsageNotes -cmd $MyInvocation.MyCommand
}
ElseIf ( $Version ) {
    Get-CSScriptVersion -Verb:$Verb -Words:$Words -Flags:$MyInvocation.BoundParameters | Write-Output
}
Else {
    $t0 = date
    $sCommandWithVerb = "${sCommandWithVerb} ${Verb}"
    $global:gCSGPCommandWithVerb = $sCommandWithVerb

    If ( $Verb.Length -gt 0 ) {
        $global:gScriptContextName = $sCommandWithVerb
    }

    $allObjects = ( @( $Words | Where { $_ -ne $null } ) + @( $Input | Where { $_ -ne $null } ) )

    If ( $Verb -eq "report" ) {

        $Locations = $( If ($Items) { $allObjects | Get-FileLiteralPath } Else { $Words | Get-ColdStorageLocation -ShowWarnings } )
        $Locations | Invoke-ColdStoragePackagesReport -Recurse:( $Recurse -or ( -Not $Items )) `
            -ShowWarnings:$Verbose `
            -Bagged:$Bagged `
            -Unbagged:$Unbagged `
            -Zipped:$Zipped `
            -Unzipped:$Unzipped `
            -Mirrored:$Mirrored `
            -NotMirrored:$NotMirrored `
            -InCloud:$InCloud `
            -NotInCloud:$NotInCloud `
            -Only:$Only `
            -FullName:$FullName `
            -Report:$true `
            -At:$At `
            -Output:$Output
        
    }
    ElseIf ( $Verb -eq "check" ) {
        If ( $Items ) {
            $allObjects | Invoke-ColdStorageItemCheck
        }
        Else {
            Invoke-ColdStorageRepositoryCheck -Pairs:$Words
        }
    }
    ElseIf ( $Verb -eq "validate" ) {
        If ( $Items ) {
            $allObjects | Get-CSItemValidation -Verbose:$Verbose -Summary:$Report -PassThru:$PassThru
        }
        Else {
            Invoke-ColdStorageValidate -Pairs $allObjects -Verbose:$Verbose -Zipped
        }
    }
    ElseIf ( $Verb -eq "stats" ) {
        $Words = ( $Words | Get-CSCommandLine -Default @("Processed","Unprocessed", "Masters") )
        ( $Words | Get-RepositoryStats -Count:($Words.Count) -Verbose:$Verbose -Batch:$Batch ) | Out-CSData -Output:$Output
    }
    ElseIf ( @("in") -ieq $Verb ) {
        $Object, $Words = $Words
        $allObjects = ( @( $Words |? { $_ -ne $null } ) + @( $Input |? { $_ -ne $null } ) )

        Switch ( $Object ) {
            "cloud" { $allObjects | Select-CSInCloud -NotInCloud:$NotInCloud }
            default { ( "[{0}] Unknown test: {1} {2}" -f $global:gCSCommandWithVerb,$Verb,$Object ) | Write-Warning }
        }
    }
    ElseIf ( @("with") -ieq $Verb ) {
        $Object, $Words = $Words
        $allObjects = ( @( $Words |? { $_ -ne $null } ) + @( $Input |? { $_ -ne $null } ) )

        Switch ( $Object ) {
            "ok" { $allObjects | Select-CSPackagesOK -Verbose:$Verbose -Force }
            "date" { $allObjects | Select-CSHasDate -From:$From -To:$To -InCloud:$InCloud -NotInCloud:$NotInCloud }
            default { ( "[{0}] Unknown test: {1} {2}" -f $global:gCSCommandWithVerb,$Verb,$Object ) | Write-Warning }
        }

    }
    ElseIf ( $Verb -eq "echo" ) {
        $aFlags = $MyInvocation.BoundParameters
        "Verb", "Words" |% { $Removed = ( $aFlags.Remove($_) ) }

        $oEcho = @{ "FLAGS"=( $MyInvocation.BoundParameters ); "WORDS"=( $Words ); "VERB"=( $Verb ); "PIPED"=( $Input ) }
        [PSCustomObject] $oEcho | Out-CSStream -Stream:$Output
    }
    Else {

        $Words = @( $Verb ) + ( $Words )
        $allObjects = ( @( $Words | Where { $_ -ne $null } ) + @( $Input | Where { $_ -ne $null } ) )
        
        $Locations = $( If ($Items) { $allObjects | Get-FileLiteralPath } Else { $allObjects | Get-ColdStorageLocation -ShowWarnings } )
        $Locations = ( $Locations |? { -Not ( -Not ( $_  ) ) } )

        $Locations | Invoke-ColdStoragePackagesReport -Recurse:( $Recurse -or ( -Not $Items )) `
            -ShowWarnings:$Verbose `
            -Bagged:$Bagged -Unbagged:$Unbagged `
            -Zipped:$Zipped -Unzipped:$Unzipped `
            -Mirrored:$Mirrored -NotMirrored:$NotMirrored `
            -InCloud:$InCloud -NotInCloud:$NotInCloud `
            -Only:$Only `
            -FullName:$FullName `
            -Report:$Report `
            -At:$At `
            -Output:$Output
        

    }


    if ( $Batch -and ( -Not $Quiet ) ) {
        $tN = ( Get-Date )
        
        Invoke-BatchCommandEpilog -Start:$t0 -End:$tN
    }
}
