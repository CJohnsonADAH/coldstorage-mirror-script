<#
.SYNOPSIS
ADAHColdStorage Digital Preservation Packages compression script
@version 2022.0901

.PARAMETER Skip
coldstorage zip -Skip allows you to bypass potentially time-consuming steps in the process, like clamav scans, bagit validation, and zip checksum validation. Usually you shouldn't. They're important.

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

Param (
    [switch] $Development = $false,
    [switch] $Production = $false,
    [switch] $Help = $false,
    [switch] $Quiet = $false,
	[switch] $Batch = $false,
    [switch] $Interactive = $false,
    [String[]] $Skip = @(), 
    [switch] $Recurse = $false,
    [switch] $Force = $false,
    [switch] $PassThru = $false,
    [switch] $Dev = $false,
    [switch] $Bork = $false,
    [switch] $WhatIf = $false,
    [switch] $Version = $false,
    [Parameter(ValueFromRemainingArguments=$true, Position=0)] $Words,
    [Parameter(ValueFromPipeline=$true)] $Piped
)

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

Function Compress-CSBaggedPackage {
Param( [Parameter(ValueFromPipeline=$true)] $File, $Batch = $false, [String[]] $Skip=@() )

Begin { }

Process {
    
    $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
    $Progress.Open( ( "Processing {0}" -f "${sArchive}" ), "Validating bagged preservation package", 5 )

    If ( Test-BagItFormattedDirectory -File $File ) {
        $oFile = Get-FileObject -File $File
        $sFile = Get-FileLiteralPath -File $File

        $Validated = ( Test-CSBaggedPackageValidates -DIRNAME $sFile -Skip:$Skip )

        $Progress.Update( "Validated bagged preservation package" )
        
        If ( $Validated | Test-CSOutputForValidationErrors | Test-ShallWeContinue ) {

            $oZip = ( Get-ZippedBagOfUnzippedBag -File $oFile )

            $Result = $null

            If ( $oZip.Count -gt 0 ) {
                $asArchiveHashed = ( $oZip | Sort-Object -Property LastWriteTime -Descending |% { $oZip.FullName } )
                $sArchiveHashed = ( $asArchiveHashed | Select-Object -First 1 )
                $Result = [PSCustomObject] @{ "Bag"=$sFile; "Zip"=$sArchiveHashed; "Zips"=$asArchiveHashed; "New"=$false; "Validated"=$Validated; "Compressed"=$null }
                $Progress.Update( "Located archive with MD5 Checksum", 2 )
            }
            Else {
                $Progress.Update( "Compressing archive" )

                $oRepository = ( $oFile | Get-ZippedBagsContainer )
                $sRepository = $oRepository.FullName

                $ts = $( Date -UFormat "%Y%m%d%H%M%S" )
                $sZipPrefix = ( Get-ZippedBagNamePrefix -File $oFile )

                $sZipName = "${sZipPrefix}_z${ts}"

                If ( $sRepository ) {
                    $sArchive = ( $sRepository | Join-Path -ChildPath "${sZipName}.zip" )

                    $CompressResult = ( $sFile | Compress-ArchiveWith7z -WhatIf:$WhatIf -DestinationPath ${sArchive} )

                    $Progress.Update( "Computing MD5 checksum" )
                    If ( -Not $WhatIf ) {
                        $md5 = $( Get-FileHash -LiteralPath "${sArchive}" -Algorithm MD5 ).Hash.ToLower()
                    }
                    Else {
                        $stream = [System.IO.MemoryStream]::new()
                        $writer = [System.IO.StreamWriter]::new($stream)
                        $writer.write($sArchive)
                        $writer.Flush()
                        $stream.Position = 0
                        $md5 = $( Get-FileHash -InputStream $stream ).Hash.ToLower()
                    }

                    $sZipHashedName = "${sZipName}_md5_${md5}"
                    $sArchiveHashed = ( $sRepository | Join-Path -ChildPath "${sZipHashedName}.zip" )

                    If ( -Not $WhatIf ) {
                        Move-Item -WhatIf:$WhatIf -LiteralPath $sArchive -Destination $sArchiveHashed
                    }

                    $Result = [PSCustomObject] @{ "Bag"=$sFile; "Zip"="${sArchiveHashed}"; "New"=$true; "Validated-Bag"=$Validated; "Compressed"=$CompressResult }
                }
                Else {
                    ( "[Compress-CSBaggedPackage] Could not determine destination container for path: '{0}'" -f $oFile.FullName ) | Write-Warning
                }

            }
            
            $Progress.Update( "Testing zip file integrity" )

            If ( $Result -ne $null ) {
                $Result | Add-Member -MemberType NoteProperty -Name "Validated-Zip" -Value ( Test-ZippedBagIntegrity -File $sArchiveHashed -Skip:$Skip )
                $Result | Write-Output
            }

        }
    }
    Else {
        $sFile = $File.FullName
        Write-Warning "${sFile} is not a BagIt-formatted directory."
    }

    $Progress.Complete()

}

End { }

}


Function Get-PluralizedText {
Param ( [Parameter(Position=0)] $N, [Parameter(ValueFromPipeline=$true)] $Singular, $Plural="{0}s" )

    Begin { }

    Process {
        $Pluralized = $( $Plural -f $Singular )
        If ( $N -eq 1 ) {
            $Singular
        }
        Else {
            $Pluralized
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
    $allObjects |% {
        $sFile = Get-FileLiteralPath -File $_
        If ( Test-BagItFormattedDirectory -File $sFile ) {
            $_ | Compress-CSBaggedPackage -Skip:$Skip
        }
        ElseIf ( Test-LooseFile -File $_ ) {
            $oBag = ( Get-BaggedCopyOfLooseFile -File $_ )
            If ($oBag) {
                $oBag | Compress-CSBaggedPackage -Skip:$Skip
            }
            Else {
                Write-Warning "${sFile} is a loose file not a BagIt-formatted directory."
            }
        }
        Else {
            $_ | Get-Item -Force |% { Get-BaggedChildItem -LiteralPath $_.FullName } | Compress-CSBaggedPackage -Skip:$Skip
        }
    }
}