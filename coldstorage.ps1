<#
.SYNOPSIS
ADAHColdStorage Digital Preservation maintenance and utility script with multiple subcommands.
@version 2024.0117

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
    [switch] $Help = $false,
    [switch] $Quiet = $false,
    [switch] $Diff = $false,
    [switch] $SizesOnly = $false,
	[switch] $Batch = $false,
    [switch] $Interactive = $false,
    [switch] $Repository = $true,
    [switch] $Items = $false,
    [switch] $Recurse = $false,
    [switch] $At = $false,
    [switch] $NoScan = $false,
    [switch] $NoValidate = $false,
    [switch] $Bucket = $false,
    [switch] $Make = $false,
    [switch] $Halt = $false, 
    [switch] $Bundle = $false,
    [switch] $Manifest = $false,
    [switch] $Force = $false,
    [switch] $FullName = $false,
    [String[]] $Is = @(),
    [String[]] $IsNot = @(),
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
    [string] $For,
    [string] $From,
    [string] $To,
    [switch] $Reverse = $false,
    [switch] $RoboCopy = $false,
    [switch] $Progress = $false,
    [switch] $Scheduled = $false,
    $Context = $null,
    [Parameter(ValueFromRemainingArguments=$true, Position=1)] $Words,
    [Parameter(ValueFromPipeline=$true)] $Piped
)
$RipeDays = 7

$Verbose = ( $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent )
$Verbose = $( If ( $Verbose -eq $null ) { $false } Else { $Verbose } )
$Debug = ( $PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent )
$Debug = $( If ( $Debug -eq $null ) { $false } Else { $Debug } )

$global:gBucketObjects = @{ }

    Function Get-CSScriptDirectory {
    Param ( $File=$null )
        $ScriptPath = ( Split-Path -Parent $PSCommandPath )
        If ( $File -ne $null ) { $ScriptPath = ( Join-Path "${ScriptPath}" -ChildPath "${File}" ) }
        ( Get-Item -Force -LiteralPath "${ScriptPath}" )
    }

# External Dependencies - Modules
Import-Module -Verbose:$false BitsTransfer
Import-Module -Verbose:$false Posh-SSH

# Internal Dependencies - Modules
$bVerboseModules = ( $Debug -eq $true )
$bForceModules = ( ( $Debug -eq $true ) -or ( $psISE ) )

Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageData.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageInteraction.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageSettings.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageFiles.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageMirrorFunctions.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageRepositoryLocations.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStoragePackagingConventions.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageScanFilesOK.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageBagItDirectories.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageBaggedChildItems.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageStats.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageZipArchives.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageToCloudStorage.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "ColdStorageToADPNet.psm1" )
Import-Module -Verbose:$bVerboseModules -Force:$bForceModules $( Get-CSScriptDirectory -File "LockssPluginProperties.psm1" )

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

Function Get-CommandWithVerb {
    $global:gCSCommandWithVerb
}

#############################################################################################################
## SETTINGS: PATHS, ETC. ####################################################################################
#############################################################################################################

Function Invoke-TestDependencies {
Param ( [switch] $Bork=$false )

    Get-ExeForPython | Ping-Dependency -Name:"Python" -Bork:$Bork | Write-Output
    Get-ExeFor7z | Ping-Dependency -Name:"7z" -Test:"i" -Process:{ Param( $Line ); $Line | Where-Object { ( $_.Trim() ).Length -gt 0 } | Select-Object -First 1 } -Bork:$Bork | Write-Output
    Get-ExeForClamAV | Ping-Dependency -Name:"ClamAV" -Bork:$Bork | Write-Output
    Get-ExeForAWSCLI | Ping-Dependency -Name:"AWS-CLI" -Bork:$Bork | Write-Output

    "Posh-SSH" | Ping-DependencyModule -Bork:$Bork | Write-Output

}

Function ColdStorage-Command-Line {
Param( [Parameter(ValueFromPipeline=$true)] $Parameter, $Default )

Begin { $N = 0 }

Process {
    If ( $Parameter ) {
        $N = ( $N + 1 )
        $Parameter
    }
}

End {
    If ( $N -lt 1 ) {
        $Default | ForEach {
            $_
        }
    }
}

}

#############################################################################################################
## BagIt PACKAGING CONVENTIONS ##############################################################################
#############################################################################################################

Function Out-BagItFormattedDirectory {
<#
.SYNOPSIS
Invoke the BagIt.py external script to bag a preservation package

.DESCRIPTION
Given a directory of digital content, enclose it within a BagIt-formatted package.
Formerly known as: Do-Bag-Directory

.PARAMETER DIRNAME
Specifies the directory to enclose in a BagIt-formatted package.

.PARAMETER PassThru
If present, output the location of the BagIt-formatted package into the pipeline after completing the bagging.

.PARAMETER Progress
If provided, provides a [CSProgressMessenger] object to manage progress and logging output from the process.
#>

    [CmdletBinding()]

Param( [Parameter(ValueFromPipeline=$true)] $DIRNAME, [switch] $PassThru=$false, $Progress=$null )

    Begin { }

    Process {
    
        $BagDir = $( If ( $DIRNAME -is [String] ) { $DIRNAME } Else { Get-FileObject($DIRNAME) |% { $_.FullName } } )

        Push-Location ( $BagDir )

        Get-SystemArtifactItems -LiteralPath "." | Remove-Item -Force -Verbose:$Verbose

        "PS ${PWD}> bagit.py ." | Write-Verbose
    
        If ( $Progress ) {
            $Progress.Update( ( "Bagging {0}" -f $BagDir ), 0, ( "OK-BagIt: {0}" -f $BagDir ) )
        }

        $BagItPy = ( Get-PathToBagIt | Join-Path -ChildPath "bagit.py" )
	    $Python = Get-ExeForPython

        # Execute bagit.py under python interpreter; capture stderr output and send it to $Progress if we have that
        $Output = ( & $( Get-ExeForPython ) "${BagItPy}" . 2>&1 |% { "$_" -replace "[`r`n]","" } |% { If ( $Progress ) { $Progress.Update( ( "Bagging {0}: {1}" -f $BagDir,"$_" ), 0, $null ) } ; "$_" } )
        $NotOK = $LASTEXITCODE

        If ( $NotOK -gt 0 ) {
            "ERR-BagIt: returned ${NotOK}" | Write-Verbose
            $Output | Write-Error
        }
        Else {
            
            # Send the bagit.py console output to Verbose stream
            $Output 2>&1 |% { "$_" -replace "[`r`n]","" } |% { If ( $Progress ) { $Progress.Update( ( "Bagging {0}: {1}" -f $BagDir,"$_" ), 0, $null ) } ; $_ | Write-Verbose }
            
            # If requested, pass thru the successfully bagged directory to Output stream
            If ( $PassThru ) {
                Get-FileObject -File $BagDir | Write-Output
            }
            ElseIf ( $Progress ) {
                $Progress.Update( ( "Bagged {0}" -f $BagDir ), ( "OK-BagIt: {0}" -f $BagDir ) )
            }


        }

        Pop-Location
    }

    End { }
}

Function Out-BaggedPackage {
<#
.SYNOPSIS
Enclose a preservation package of digital content into a BagIt-formatted preservation package.

.DESCRIPTION
Given a loose file or a directory of digital content, enclose that within a BagIt-formatted preservation package following ADAHColdStorage packaging conventions.

If the input is a directory, the output will be a directory in the same location containing BagIt manifest files and the original content enclosed in a payload directory called "data".

If the input is a loose file, the output will be a BagIt-formatted directory located within the same parent container, containing a copy of the loose file enclosed in a payload directory called "data".

Formerly known as: Do-Bag-Loose-File

.PARAMETER LiteralPath
Specifies the loose file or the directory to enclose within a BagIt-formatted package.

.PARAMETER PassThru
If present, output the location of the BagIt-formatted package into the pipeline after completing the bagging.

.PARAMETER Progress
If provided, provides a [CSProgressMessenger] object to manage progress and logging output from the process.
#>

    [CmdletBinding()]

Param( [Parameter(ValueFromPipeline=$true)] $LiteralPath, [switch] $PassThru=$false, $Progress=$null )

    Begin { $cmd = ( Get-CommandWithVerb ) }

    Process {
        If ( -Not $LiteralPath ) {
            Return
        }

        $Item = Get-FileObject($LiteralPath)

        # If this is a single (loose) file, then we will create a parallel counterpart directory
        If ( Test-Path -LiteralPath $Item.FullName -PathType Leaf ) {

            Push-Location $Item.DirectoryName

            $OriginalFileName = $Item.Name
            $OriginalFullName = $Item.FullName
            $FileName = ( $Item | Get-PathToBaggedCopyOfLooseFile )

            $BagDir = ( Get-Location | Join-Path -ChildPath "${FileName}" )
            If ( -Not ( Test-Path -LiteralPath $BagDir ) ) {
                $oBagDir = ( New-Item -Type Directory -Path $BagDir )
                $BagDir = $( If ( $oBagDir ) { $oBagDir.FullName } Else { $null } )
            }

            If ( Test-Path -LiteralPath $BagDir -PathType Container ) {
                
                # Move the loose file into its containing counterpart directory. We'll re-link it to its old directory later.
                Move-Item -LiteralPath $Item -Destination $BagDir

                # Now rewrite the counterpart directory as a BagIt-formatted preservation package
                $BagDir | Out-BagItFormattedDirectory -PassThru:$PassThru -Progress:$Progress
                If ( $LastExitCode -eq 0 ) {

                    # If all went well, then hardlink a reference at the loose file's old location to the new BagIt directory payload
                    $DataDir = ( "${BagDir}" | Join-Path -ChildPath "data" )
                    $Payload = ( "${DataDir}" | Join-Path -ChildPath "${OriginalFileName}" )
                    If ( Test-Path -LiteralPath "${Payload}" ) {
                        
                        New-Item -ItemType HardLink -Path "${OriginalFullName}" -Target "${Payload}" | %{ "[$cmd] Bagged ${BagDir}, created link to payload: $_" | Write-Verbose }
	        
                        # Set file attributes to ReadOnly -- bagged copies should remain immutable
                        Set-ItemProperty -LiteralPath "${OriginalFullName}" -Name IsReadOnly -Value $true
                        Set-ItemProperty -LiteralPath "${Payload}" -Name IsReadOnly -Value $true

                    }
                    Else {
                        ( "[$cmd] BagIt process completed OK, but ${cmd} could not locate BagIt payload: '{0}'" -f "${Payload}" ) | Write-Error
                    }

                }

            }
            Else {
                ( "[$cmd] Could not create or locate counterpart directory for BagIt to operate on: '{0}'" -f "${BagDir}" ) | Write-Error
            }

            Pop-Location

        }

        # If this is a directory, then we run BagIt directly over the directory.
        ElseIf ( Test-Path -LiteralPath $Item.FullName -PathType Container ) {
            $LiteralPath | Out-BagItFormattedDirectory -Verbose:$Verbose -PassThru:$PassThru -Progress:$Progress
        }

        Else {
            ( "[$cmd] Preservation package not found: '{0}'" -f $LiteralPath ) | Write-Warning
        }
    }

    End { }

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

# Do-Mirror-Repositories
Function Sync-MirroredRepositories ($Pairs=$null, $DiffLevel=1, [switch] $Batch=$false, [switch] $Force=$false, [switch] $Reverse=$false, [switch] $NoScan=$false, [switch] $RoboCopy=$false, [switch] $Scheduled=$false ) {

    $Context = Get-CommandWithVerb
    $mirrors = ( Get-ColdStorageRepositories )

    $Pairs = ($Pairs | % { If ( $_.Length -gt 0 ) { $_ -split "," } })

    if ( $Pairs.Count -lt 1 ) {
        $Pairs = $mirrors.Keys
    }

    $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
    $Progress.Open( "Mirroring between ADAHFS servers and ColdStorage", ( "{0} {1}" -f $Pairs.Count, ( "location" | Get-PluralizedText($Pairs.Count) ) ), $Pairs.Count )
    
    $Pairs | ForEach {
        $Pair = $_

        If ( $mirrors.ContainsKey($Pair) ) {
            $locations = $mirrors[$Pair]

            $slug = $locations[0]

            If ( -Not $Reverse ) {
                $iSrc = 2
                $iDest = 1
            }
            Else {
                $iSrc = 1
                $iDest = 2
            }
            $src = (Get-Item -Force -LiteralPath $locations[$iSrc] | Get-LocalPathFromUNC ).FullName
            $dest = (Get-Item -Force -LiteralPath $locations[$iDest] | Get-LocalPathFromUNC ).FullName

            $Progress.Update(("Location: {0}" -f $Pair), 0) 
            Sync-MirroredFiles -From "${src}" -To "${dest}" -DiffLevel $DiffLevel -Batch:$Batch -Force:$Force -NoScan:$NoScan -RoboCopy:$RoboCopy -Scheduled:$Scheduled
            $Progress.Update(("Location: {0}" -f $Pair)) 
        }
        Else {
            $recurseInto = @( )
            $mirrors.Keys | ForEach {
                $subPair = $_
                $locations = $mirrors[$subPair]
                $slug = $locations[0]
                $src = $locations[2]
                $dest = $locations[1]

                If ( $slug -eq $Pair ) {
                    $recurseInto += @( $subPair )
                }
            }
            If ( $recurseInto.Count -gt 0 ) {
                Sync-MirroredRepositories -Pairs $recurseInto -DiffLevel $DiffLevel -Batch:$Batch -Reverse:$Reverse -NoScan:$NoScan -RoboCopy:$RoboCopy -Scheduled:$Scheduled
            }
            Else {
                ( "[{0}] No such repository: {1}." -f $Context,$Pair ) | Write-Warning 
            }
        } # If
    }

    $Progress.Complete()
}

Function Redo-CSBagPackage {

    [Cmdletbinding()]

Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $PassThru=$false )

    Begin { }

    Process {
        $Payload = ( $File | Select-BagItPayloadDirectory )
        $Bag = ( $Payload.Parent )

        $oManifest = ( $Bag | New-BagItManifestContainer )
        $OldManifest = $oManifest.FullName

        Get-ChildItem -LiteralPath $Bag.FullName |? { ( $_.Name -ne $Payload.Name ) } |? { -Not ( $_.Name -match "^bagged-[0-9]+$" ) } |% {
            $Src = $_.FullName
            If ( Test-Path -LiteralPath $OldManifest ) {
                $Dest = ( "${OldManifest}" | Join-Path -ChildPath $_.Name )
            }
            Else {
                $Dest = ( $Src + "~" )
            }

            Move-Item $Src -Destination $Dest -Verbose
        }

        $RebagData = ( $Bag.FullName | Join-Path -ChildPath ( ( "rebag-data-{0}" -f ( Get-Date -UFormat "%s" ) ) -replace "[^A-Za-z0-9]+","-" ) )

        # Avoid name collision with data child directory when we pop out contents
        Move-Item $Payload -Destination $RebagData -Verbose
        $RebagData | Out-BagItFormattedDirectory -Progress:$Progress

        # Pop out contents
        Get-ChildItem -LiteralPath $RebagData |% {
            Move-Item $_.FullName -Destination $Bag.FullName -Verbose
        }

        # Get rid of temporary data container
        Remove-Item $RebagData

        $Bag.FullName | Write-Verbose
        If ( $PassThru ) {
            $Bag | Write-Output
        }
    }

    End { }

}

# @package coldstorage bag
Function Select-CSPackagesToBag {
Param( [Parameter(ValueFromPipeline=$true)] $File, [Switch] $Quiet, [String] $Exclude, $Message=$null, $Line )

    Begin {
        If ( $Exclude.Length -eq 0 ) {
            $Exclude = "^$"
        }

        $FullMessages = @( $null, $null )
        If ( $Message ) {
            $FullMessages = @(
                ( "{0}. Scan it, bag it and tag it." -f $Message )
                ( "{0} -- already bagged." -f $Message )
                ( "{0} -- EXCLUDED by rule." -f $Message )
            )
        }

    }

    Process {
        
        If ( -Not ( $BaseName -match $Exclude ) ) {
            $sPath = Get-FileLiteralPath($File)
            $bToBag = $true
            If ( Test-Path -LiteralPath $sPath -PathType Container ) {
                $bHasBag = Test-BagItFormattedDirectory($File)
            }
            Else {
                $bHasBag = ( -Not ( Test-UnbaggedLooseFile($File) ) )
            }
            
            If ( $bHasBag ) {
                Write-BaggedItemNoticeMessage -File:$File -Item:$File -Message:($FullMessages[1]) -Verbose:( -Not $Quiet ) -Quiet -Line:$Line
            }
            Else {
                Write-UnbaggedItemNoticeMessage -File:$File -Message:($FullMessages[0]) -Quiet -Verbose:( -Not $Quiet ) -Line:$Line
                $File | Write-Output
            }

        }
        Else {
            Write-BaggedItemNoticeMessage -Status:"SKIPPED" -File:$File -Item:$File -Message:($FullMessages[2]) -Quiet -Verbose:( -Not $Quiet ) -Line:$Line
        }


    }

    End { }

}

# Out-BagItFormattedDirectoryWhenCleared: invoke a malware scanner (ClamAV) to clear preservation packages, then a bagger (BagIt.py) to bag them
# Formerly known as: Do-Clear-And-Bag
# @package coldstorage bag
Function Out-BagItFormattedDirectoryWhenCleared {

    [Cmdletbinding()]

param (
    [Switch]
    $Quiet,

    [String]
    $Exclude="^$",

    [Switch]
    $Rebag=$false,

    [String[]]
    $Skip=@( ),

    [switch]
    $Force=$false,

    [switch]
    $Bundle=$false,

    [switch]
    $Manifest=$false,

    [switch]
    $PassThru=$false,

    [switch]
    $Batch=$false,

    [Parameter(ValueFromPipeline=$true)]
    $File
)

    Begin {
        if ( $Exclude.Length -eq 0 ) {
            $Exclude = "^$"
        }

        $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
        $Progress.Open( "{0}" -f $global:gCSCommandWithVerb, "Bagging preservation packages" )

    }

    Process {
        $Anchor = $PWD

        $DirName = $File.FullName
        $BaseName = $File.Name

        If ( -Not $File ) {
            ( "[Out-BagItFormattedDirectoryWhenCleared:{0}] File object is empty" -f ( Get-CurrentLine ) ) | Write-Warning
        }
        ElseIf ( $DirName -eq $null ) {
            ( "[Out-BagItFormattedDirectoryWhenCleared:{0}] DirName string is null" -f ( Get-CurrentLine ) ) | Write-Warning
        }
        Else {
            If ( $Bundle ) {
                If ( Test-Path -LiteralPath $DirName -PathType Container ) {
                    If ( -Not ( Test-BagItFormattedDirectory($File) ) ) {
                        If ( -Not ( Test-IndexedDirectory($File) ) ) {
                            $DirName | Add-IndexHTML -RelativeHref
                        }
                    }
                }
            }

            If ( Test-BagItFormattedDirectory($File) ) {

                Write-BaggedItemNoticeMessage -File $File -Item:$File -Message "BagIt formatted directory" -Verbose -Line ( Get-CurrentLine )

                If ( $Rebag ) {
                    $File | Redo-CSBagPackage -PassThru:$PassThru
                }

            }
            ElseIf ( Test-ERInstanceDirectory($File) ) {

                Push-Location $DirName
                $File | Select-CSPackagesToBag -Quiet:$Quiet -Exclude:$Exclude -Line:( Get-CurrentLine ) | Select-CSPackagesOKOrApproved -Quiet:$Quiet -Force:$Force -Rebag:$Rebag -Skip:$Skip | Out-BagItFormattedDirectory -Progress:$Progress
                Pop-Location

                If ( $PassThru ) {
                    If ( Test-BagItFormattedDirectory($File) ) {
                        $File | Write-Output
                    }
                }

            }
            ElseIf ( Test-IndexedDirectory($File) ) {

                $File | Select-CSPackagesToBag -Quiet:$Quiet -Exclude:$Exclude -Message:"indexed directory" -Line:( Get-CurrentLine ) | Select-CSPackagesOKOrApproved -Quiet:$Quiet -Force:$Force -Rebag:$Rebag -Skip:$Skip | Out-BaggedPackage -Progress:$Progress
            
                If ( $PassThru ) {
                    If ( Test-BagItFormattedDirectory($File) ) {
                        $File | Write-Output
                    }
                }

            }
            Else {

                Get-ChildItem -File -LiteralPath $File.FullName |% {
                
                    $ChildItem = $_
                    $ChildItem | Select-CSPackagesToBag -Quiet:$Quiet -Exclude:$Exclude -Message:"loose file" -Line:( Get-CurrentLine ) | Select-CSPackagesOKOrApproved -Quiet:$Quiet -Force:$Force -Rebag:$Rebag -Skip:$Skip | Out-BaggedPackage -Progress:$Progress

                    If ( $PassThru ) {
                        $ChildItem | Get-BaggedCopyOfLooseFile | Write-Output
                    }
                }

            }

            If ( $Manifest ) {
                If ( Test-Path -LiteralPath $DirName -PathType Container ) {
                    If ( Test-BagItFormattedDirectory( $File )  ) {

                        $Location = ( Get-Item -LiteralPath $File )
                        $sTitle = ( $Location | Get-ADPNetAUTitle )
                        If ( -Not $sTitle ) {
                            $sTitle = ( Read-Host -Prompt "AU Title [${Location}]" )
                        }

                        Add-LOCKSSManifestHTML -Directory $File -Title $sTitle -Force:$Force
                    }
                }
            }

        }
    }

    End {
        $Progress.Complete()
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
            $Validated = ( Test-CSBaggedPackageValidates -DIRNAME $_ -Verbose:$Verbose -NoLog )
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
    If ( $Summary ) {
        $sSummaryOut = "Validation: ${nValidated} / ${nChecked} validated OK."
        
        If ( $PassThru ) {
            $sSummaryOut | Write-Warning
        }
        Else {
            $sSummaryOut | Write-Output
        }
    }
}

}

# Invoke-BagChildDirectories: Given a parent directory (typically a repository root), loop through each child directory and do a clear-and-bag
# Formerly known as: Do-Bag-Repo-Dirs
Function Invoke-BagChildDirectories ($Pair, $From, $To, $Skip=@(), [switch] $Force=$false, [switch] $Bundle=$false, [switch] $Manifest=$false, [switch] $PassThru=$false, [switch] $Batch=$false) {
    Push-Location $From
    Get-ChildItem -Directory | Out-BagItFormattedDirectoryWhenCleared -Quiet -Exclude $null -Skip:$Skip -Force:$Force -Bundle:$Bundle -Manifest:$Manifest -PassThru:$PassThru -Batch:$Batch
    Pop-Location
}

# Invoke-ColdStorageRepositoryBag
# Formerly known as: Do-Bag
function Invoke-ColdStorageRepositoryBag ($Pairs=$null, $Skip=@(), [switch] $Force=$false, [switch] $Bundle=$false, [switch] $Manifest=$false, [switch] $PassThru=$false, [switch] $Batch=$false) {

    If ( $Pairs -eq "_" ) {
        Get-ChildItem -Path . -Directory |% { ( "PS> {0} bag -Items '{1}' {2}" -f $global:gCSScriptName,$_.FullName,$( If ($Bundle) { "-Bundle" } Else { "" } ) ) | Write-Verbose ; & "${global:gCSScriptPath}" bag -Items $_.FullName -Skip:$Skip -Force:$Force -Bundle:$Bundle -PassThru:$PassThru -Batch:$Batch }
        Get-ChildItem -Path . -File |% { ( "PS> {0} bag -Items '{1}'" -f $global:gCSScriptName,$_.FullName ) | Write-Verbose ; & "${global:gCSScriptPath}" bag -Items $_.FullName -Skip:$Skip -Force:$Force -Bundle:$false -PassThru:$PassThru -Batch:$Batch }
    }
    Else {

    $mirrors = ( Get-ColdStorageRepositories )

    if ( $Pairs.Count -lt 1 ) {
        $Pairs = $mirrors.Keys
    }

    $i = 0
    $N = $Pairs.Count
    $Pairs | ForEach {
        $Pair = $_
        $locations = $mirrors[$Pair]

        $slug = $locations[0]
        $src = $locations[2]
        $dest = $locations[1]

        Invoke-BagChildDirectories -Pair "${Pair}" -From "${src}" -To "${dest}" -Skip:$Skip -Force:$Force -Bundle:$Bundle -Manifest:$Manifest -PassThru:$PassThru -Batch:$Batch
        $i = $i + 1
    }

    }
}

function Invoke-ColdStorageDirectoryCheck {
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

Function Invoke-ColdStorageItemMirror {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [int] $DiffLevel=1, [switch] $Batch, [switch] $Force=$false, [switch] $Reverse=$false, [switch] $NoScan=$false, [switch] $RoboCopy=$false, [switch] $Scheduled=$false, [switch] $WhatIf )

    Begin { }

    Process {
        If ( $File ) {

            $oRepository = ( Get-FileRepositoryLocation -File $File )
            $sRepository = $oRepository.FullName
            $RepositorySlug = ( Get-FileRepositoryName -File $File )

            $Original = ( $File | Get-MirrorMatchedItem -Pair $RepositorySlug -Original -All )
            $Reflection = ( $File | Get-MirrorMatchedItem -Pair $RepositorySlug -Reflection -All )

            If ( -Not $Reverse ) {
                $Src = $Original
                $Dest = $Reflection
            }
            Else {
                $Src = $Reflection
                $Dest = $Original
            }

            ( "REPOSITORY: {0} - SLUG: {0}" -f $sRepository,$RepositorySlug ) | Write-Debug

            $sSrc = ( "${Src}" | ConvertTo-CSFileSystemPath )
            $sDest = ( "${Dest}" | ConvertTo-CSFileSystemPath )
            ( "[coldstorage mirror] {0} --> {1} [DIFF LEVEL: {2:N0}]" -f $sSrc, $sDest, $DiffLevel ) | Write-Host -ForegroundColor Yellow
            
            If ( -Not $WhatIf ) {
                Sync-MirroredFiles -From "${Src}" -To "${Dest}" -DiffLevel:$DiffLevel -Batch:$Batch -Force:$Force -NoScan:$NoScan -RoboCopy:$RoboCopy -Scheduled:$Scheduled
                
                If ( Test-Path -LiteralPath "${Src}" -PathType Leaf ) {
                    $srcPackage = ( $Src | Get-ItemPackage )
                    $bBaggedElsewhere = ( $srcPackage.CSPackageBagLocation -and ( $srcPackage.CSPackageBagLocation.FullName -ne $srcPackage.FullName ) )
                    If ( $bBaggedElsewhere ) {

                        $bDoIt = ( -Not $Only )
                        If ( $Only -and ( -Not $Batch ) ) {
                            $bDoIt = ( read-yesfromhost-cs.ps1 -Prompt ( "MIRROR: Also mirror bagged copy at {0}?" -f $srcPackage.CSPackageBagLocation ) )
                        }

                        If ( $bDoIt ) {
                            $srcPackage.CSPackageBagLocation | Invoke-ColdStorageItemMirror -DiffLevel:$DiffLevel -Batch:$Batch -Force:$Force -Reverse:$Reverse -NoScan:$NoScan -RoboCopy:$RoboCopy -Scheduled:$Scheduled -WhatIf:$WhatIf
                        }
                    }
                }

            }
            Else {
                Write-Host "(WhatIf) Sync-MirroredFiles -From '${Src}' -To '${Dest}' -DiffLevel $DiffLevel -Batch $Batch -Force $Force -NoScan:$NoScan -RoboCopy:$RoboCopy -Scheduled:$Scheduled"
            }

        }
    }

    End { }

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
                $Progress.Update( ( "#{0:N0}. Considering: {1}" -f $Progress.I + 1, $BagPathLeaf ) )

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

Function Invoke-ColdStorageSettings {
Param ( [Parameter(ValueFromPipeline=$true)] $Word, [String] $Output="" )

    Begin { $SettingsMode=$null; $Skip=0 }

    Process {
        If ( $SettingsMode -eq "get" ) {
          
            Get-ColdStorageSettings -Name $Word -Output:$Output -Skip:$Skip
            $Skip=1
        
        }
        ElseIf ( $SettingsMode -ne $null ) {
            ( "[{0}] Unknown method: the script does not have a way to {1} setting {2}." -f $global:gCSCommandWithVerb, $SettingsMode, $Word ) | Write-Warning
        }
        Else {

            $SettingsMode = "get"
            Switch ( $Word ) {

                "get" { $SettingsMode=$Word }
                "set" { $SettingsMode=$Word }
                default { @("get", $Word) | Invoke-ColdStorageSettings -Output:$Output ; $Skip=1 }

            }

        }
    }

    End { }

}

Function Invoke-ColdStorageTo {
Param ( [string] $Destination, $What, [switch] $Items, [switch] $Repository, [switch] $Diff, [switch] $WhatIf, [switch] $Report, [switch] $ReportOnly, [switch] $Halt=$false, [switch] $Batch=$false )

    $Destinations = ("cloud", "drop", "adpnet")

    If ( ( $What -eq "_" ) -and ( -not $Halt ) ) {
        
        $CSGetPackages = $( Get-CSScriptDirectory -File "coldstorage-get-packages.ps1" )
        $Locations = ( "." | & "${CSGetPackages}" -Items -Recurse -Bagged -Zipped -NotInCloud )
        Invoke-ColdStorageTo -Destination:$Destination -What:$Locations -Items -Diff:$Diff -WhatIf:$WhatIf -Report:$Report -ReportOnly:$ReportOnly -Batch:$Batch

    }
    ElseIf ( -Not $Items ) {
        Write-Warning ( "[${global:gScriptContextName}:${Destination}] Not yet implemented for repositories. Try: & coldstorage to ${Destination} -Items [File1] [File2] [...]" )
    }
    ElseIf ( $Destination -eq "cloud" ) {
        If ( $Halt ) {
            $What | Stop-CloudStorageUploads -Batch:$Batch -WhatIf:$WhatIf
        }
        ElseIf ( $Diff ) {
            $Candidates = ( $What | Get-ItemPackageZippedBag -ReturnContainer | Get-CloudStorageListing -Unmatched:$true -Side:("local") -ReturnObject )
            $Candidates | Write-Verbose
            $Candidates | Add-PackageToCloudStorageBucket -WhatIf:${WhatIf}
        }
        Else {
            $What | Add-PackageToCloudStorageBucket -WhatIf:${WhatIf}
        }
    }
    ElseIf ( $Destination -eq "drop" ) {
        $What | Add-ADPNetAUToDropServerStagingDirectory -WhatIf:${WhatIf}

        If ( $Report ) {
            $AU = ( $What | Get-ADPNetAUTable )
            $AU | Write-ADPNetAUReport
            $AU | Write-ADPNetAUUrlRetrievalTest
        }
    }
    ElseIf ( $Destination -eq "adpnet" ) {

        If ( -Not $ReportOnly ) {
            $What | Add-ADPNetAUToDropServerStagingDirectory -WhatIf:${WhatIf}
        }
        
        $AU = ( $What | Get-ADPNetAUTable )
        $AU | Add-ADPNetAUReport -LocalFolder:$What

    }
    Else {
        Write-Warning ( "[${global:gScriptContextName}:${Destination}] Unknown destination. Try: ({0})" -f ( $Destinations -join ", " ) )
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

Function Invoke-ColdStorageInVs {
Param ( [string] $Destination, $What, [switch] $Items=$false, [switch] $Repository=$false, [switch] $Recurse=$false, [switch] $Report=$false, [switch] $Batch=$false, [String] $Output="", [String[]] $Side, [switch] $Unmatched=$false, [switch] $FullName=$false, [string] $From="", [string] $To="", [switch] $PassThru=$false, [switch] $WhatIf=$false )

        $Destinations = ("cloud", "drop", "adpnet")
        Switch ( $Destination ) {
            "cloud" { 
                $aSide = ( $Side |% { $_ -split "," } )
                If ( $Items ) {
                    $aItems = $What
                } Else {
                    $aItems = ( Get-ZippedBagsContainer -Repository:$What )
                }

                $aItems | Get-CloudStorageListing -Unmatched:$Unmatched -Side:($aSide) -Recurse:$true -Context:("{0} {1}" -f $global:gCSCommandWithVerb,$Destination ) -From:$From -To:$To -ReturnObject | Select-CSFileInfo -FullName:$FullName -ReturnObject:$PassThru
            }
            default {
                ( "[{0} {1}] Unknown destination. Try: ({2})" -f ($global:gCSCommandWithVerb, $Destination, ( $Destinations -join ", " )) ) | Write-Warning
            }
        }

}

Function Sync-ClamAVDatabase {
    $ClamAV = Get-PathToClamAV
    $FreshClam = ( $ClamAV | Join-Path -ChildPath "freshclam.exe" )
    
    If ( Test-Path -LiteralPath $FreshClam -PathType Leaf ) {
        & $FreshClam
    }
    Else {
        ( "[{0}] ClamAV update command not found: {1}" -f ( Get-CommandWithVerb ), $FreshClam ) | Write-Error
    }
}

Function Sync-ADPNetPluginsDirectory {
    Write-Verbose "* Opening SSH session to LOCKSS box."
    $SFTP = New-LockssBoxSession 
    $Location = ( Get-ColdStorageSettings -Name "ADPNet-Plugin-Cache" | ConvertTo-ColdStorageSettingsFilePath )

    Write-Verbose "* Transferring copies from LOCKSS box to ${Location}"
    $oLocation = ( Get-Item -LiteralPath $Location -Force )
    Get-ChildItem -LiteralPath $oLocation.FullName |% { Remove-Item -LiteralPath ( $_.FullName ) -Recurse  }
    $oLocation | Sync-ADPNetPluginsPackage -Session:$SFTP

    Write-Verbose "* Closing SSH session to LOCKSS box."
    Remove-SFTPSession $SFTP >$null
}

Function Invoke-ColdStorageRepository {
Param ( [switch] $Items=$false, [switch] $Repository=$false, $Words, [String] $Output="" )

    Begin { }

    Process {
        If ( $Items -Or ( -Not $Repository ) ) {
            $aItems = ( $Words | ColdStorage-Command-Line -Default "${PWD}" )            
        }
        Else {
            $aItems = @( )
            $Words | ForEach {
                $Term = $_
                If ( Test-Path -LiteralPath $Term ) {
                    $aItems += , $Term
                }
                Else {
                    $repo = Get-ColdStorageRepositories -Repository:$Term -Tag
                    If ( $repo.Locations ) {
                        $aItems += , $repo.Locations.ColdStorage
                    }
                }
            }
        }

        $aItems |% {
            $File = Get-FileObject -File $_ 
            [PSCustomObject] @{ FILE=( $File.FullName ); REPOSITORY=($File | Get-FileRepositoryName) }
        } | Out-CSData -Output:$Output
    }

    End { }

}

Function Invoke-ColdStorageSettle {
Param ( $Words, [switch] $Bucket=$false, [switch] $Force=$false, [switch] $Batch=$false, [switch] $Zipped=$false )

    Begin { }

    Process {
        $sLocation, $Remainder = ( $Words )
        $PropsFileName = "props.json"
        $DefaultProps = $null

        If ( ( $sLocation -is [string] ) -and ( $sLocation -eq "_" ) ) {
            & "${global:gCSScriptPath}" bag -Bundle _
            & "${global:gCSScriptPath}" settle here -Bucket | & "${global:gCSScriptPath}" bucket -Make
        }
        Else {

            If ( ( $sLocation -is [string] ) -and ( $sLocation -eq "here" ) ) {
                $oFile = ( Get-Item -Force -LiteralPath $( Get-Location ) )
            }
            Else {
                $oFile = Get-FileObject($sLocation)
            }

            If ( $Bucket ) {
                $sBucket, $Remainder = ( $Remainder )

                If ( -Not $sBucket ) {
                    $DefaultBucket = $oFile.FullName | Get-CloudStorageBucket -Force 
                    $iWhich = $Host.UI.PromptForChoice("${sCommandWithVerb}", "Use default bucket name [${DefaultBucket}]?", @("&Yes", "&No"), 1)
                    If ( $iWhich -eq 0 ) {
                        $sBucket = $DefaultBucket
                    }
                }

                If ( $sBucket ) {
                    $DefaultProps = @{ Bucket="${sBucket}" }
                    $PropsFileName = "aws.json"
                }
                Else {
                    Write-Warning "[$sCommandWithVerb] ${PropsFileName} maybe not created: No bucket name specified."
                }
            }
            Else {
                $sDomain, $sRepository, $sPrefix, $Remainder = ( $Remainder )
                If ( $sDomain ) {
                    $DefaultProps = @{ Domain="${sDomain}"; Repository="${sRepository}"; Prefix="${sPrefix}" }
                }
                Else {
                    Write-Warning "[$sCommandWithVerb] ${PropsFileName} not created - expected: Domain, Repository, Prefix"
                }

            }

            If ( ( $oFile -ne $null ) -and ( $DefaultProps -ne $null ) ) {
                $oFile | Add-CSPropsFile -PassThru -Props:@( $Props, $DefaultProps ) -Name:$PropsFileName -Force:$Force | Where { $Bucket } | Add-ZippedBagsContainer |% {
                    $_ | Write-Output
                    & $global:gCSScriptPath packages -Items . -Zipped -Only -Recurse -PassThru | Get-ItemPackageZippedBag | Move-Item -Destination $_ -Verbose
                }
            }

        }

    }

    End { }

}

Function Add-CSPropsFile {
Param (
    [Parameter(ValueFromPipeline=$true)] $Location,
    [String] $Name="props.json",
    [String] $Format="application/json",
    [Object[]] $Props=$null,
    [switch] $PassThru=$false,
    [switch] $ReturnObject=$false,
    [switch] $ReturnJson=$false,
    [switch] $Force=$false
)

    Begin { }

    Process {
        $oProps = $null
        $Props |% {
            $vProps = $_
            If ( $vProps -ne $null ) {
                If ( -Not ( $oProps -is [Hashtable] ) ) {
                    
                    # Passed in a string - try to interpret as JSON
                    If ( $vProps -is [String] ) {
                        Try {
                            $oProps = ( $vProps | ConvertFrom-Json )
                            $oProps = ( $oProps | Get-TablesMerged )
                        }
                        Catch [System.ArgumentException] {
                            ( "[Add-CSPropsFile] Invalid JSON? '{0}'" -f $vProps ) | Write-Warning
                        }
                    }

                    # Passed in something else, probably Hashtable or object
                    Else {
                        $oProps = ( $vProps | Get-TablesMerged )
                    }
                }
            }
        }

        If ( $oProps -is [Hashtable] ) {
            $outProps = ( $oProps | New-ColdStorageRepositoryDirectoryProps -File:$Location -Force:$Force -FileName:$Name )
        }
        Else {
            ( "[Add-CSPropsFile] No properties provided? Location={0} FileName={1}" -f $Location.FullName, $Name) | Write-Warning
        }

        If ( $PassThru ) {
            $Location
        }

        If ( $outProps ) {
            If ( $ReturnObject ) {
                $oProps
            }
            If ( $ReturnJson ) {
                $outProps
            }
        }

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

# Get-LineStripComments
#
# I used techniques suggested by answers in these threads, but rewritten from scratch for my own purposes:
#
# * Regex to strip line comments from C#: https://stackoverflow.com/questions/3524317/regex-to-strip-line-comments-from-c-sharp/3524689#3524689
# * Use a function in Powershell replace: https://stackoverflow.com/questions/30666101/use-a-function-in-powershell-replace

Function Get-LineStripComments {
Param ( [Parameter(ValueFromPipeline=$true)] $Line )

    Begin { }

    Process {
        
        $reLineComments = "#(?:.*)$"
        $reDoubleQuoteStrings = "([""][^""]*[""])"
        $reSingleQuoteStrings = "(['][^']*['])"
        $reLines = [regex] ( "{0}|{1}|{2}" -f $reLineComments,$reDoubleQuoteStrings,$reSingleQuoteStrings )
        $reAllComment = ( "^{0}" -f $reLineComments )
        
        $reLines.Replace( $Line, [ScriptBlock] {
            Param( $Match )
            If ( $Match[0] -match $reAllComment ) {
                ""
            }
            Else {
                $Match[0]
            }
        } )
    }

    End { }
}

Function Test-CSScriptAllowed {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $As=$null, $From=$null )

    Begin { }

    Process {
        $oLocation = Get-FileObject($From)

        $DealBroke = $false

        If ( Test-Path $oLocation.FullName -PathType Container ) {
            $Relative = ( $File | Resolve-PathRelativeTo -Base $oLocation.FullName )
            $DealBroke = ( $DealBroke -or ( $Relative -like ".\never\*" ) )
            $DealBroke = ( $DealBroke -or ( $Relative -like ".\done\*" ) )
        }

        $Owner = ( Get-Acl $File.FullName | Select-Object Owner )
        
        $DealBroke = ( $DealBroke -or ( $As.Name -ne $Owner.Owner ) )

        ( -Not $DealBroke ) | Write-Output
    }

    End { }
}

Function Test-CSScriptMovable {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $As=$null, $From=$null )

    Begin { }

    Process {
        $oLocation = Get-FileObject($From)

        $DealBroke = $false

        If ( Test-Path $oLocation.FullName -PathType Container ) {
            $Relative = ( $File | Resolve-PathRelativeTo -Base $oLocation.FullName )
            $DealBroke = ( $DealBroke -or ( $Relative -like ".\again\*" ) )
            $DealBroke = ( $DealBroke -or ( $Relative -like ".\never\*" ) )
            $DealBroke = ( $DealBroke -or ( $Relative -like ".\done\*" ) )
        }

        $Owner = ( Get-Acl $File.FullName | Select-Object Owner )
        
        $DealBroke = ( $DealBroke -or ( $As.Name -ne $Owner.Owner ) )

        ( -Not $DealBroke ) | Write-Output
    }

    End { }

}

Function Invoke-CSScriptedSession {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $As=$null, $From=$null, [switch] $Batch )

    Begin {
    }

    Process {
        $oLocation = Get-FileObject($From)

        $Date = ( Get-Date -UFormat "%Y-%m-%d" )
        $DoneDir = ( $oLocation.FullName | Join-Path -ChildPath "done" | Join-Path -ChildPath $Date )

        $ToMove = @( )
        $Lines = @( )    
        
        If ( $File -is [string] ) {
            $oFile = Get-Item -Path $File -Force
        }
        Else {
            $oFile = Get-FileObject($File)
        }

        $oFile |% {
            $Lines += Get-Content $_.FullName
            $ToMove += $oFile
        }

        If ( $Lines.Count -gt 0 ) {
            $LogFile = New-TemporaryFile

            $BoundaryString = ( "script:{0}" -f ( $File.ToString().ToLower() -replace "[^a-z0-9]+","-" ) )
            $t0 = ( Get-Date )
            
            # Preamble: Starting timestamp.
            ( "Date: {0}" -f ( $t0 | Get-Date -UFormat "%c" ) ) | Out-File -Append -LiteralPath ( $LogFile.FullName ) -Encoding utf8
            ( "" ) | Out-File -Append -LiteralPath ( $LogFile.FullName ) -Encoding utf8

            # Loop: Log the command-line, then execute it and log the output.
            $Lines |% {
                $OneLineLog = New-TemporaryFile
            
                $Line = ( $_ | Get-LineStripComments )
                If ( $Line.Trim() ) {
                    $cmdLine = ( $Line.Trim() -replace "^(coldstorage([.]ps1)?\s+)?", ( "{0} " -f $global:gCSScriptPath ) )
                    ( "--{0}" -f $BoundaryString ) | Out-File -Append -LiteralPath ( $LogFile.FullName ) -Encoding utf8
                    ( "PS {0}> {1}" -f $PWD,$cmdLine ) | Out-File -Append -LiteralPath ( $LogFile.FullName ) -Encoding utf8
                    ( "" ) | Out-File -Append -LiteralPath ( $LogFile.FullName ) -Encoding utf8
                    
                    ( "PS {0}> {1}" -f $PWD,$cmdLine ) | Out-File -Append -LiteralPath ( $OneLineLog.FullName ) -Encoding utf8
                    
                    $Timestamp = ( Get-Date -UFormat "%Y%m%d%H%M%S" )
                    
                    $CSWord = ( $cmdLine -split "\s" | Select-Object -Skip 1 | Select-Object -First 1 )
                    $DoneFileBase = ( $CSWord -replace "^[^A-Za-z0-9]+","" )
                    $DoneFile = ( $DoneFileBase -replace "[^A-Za-z0-9]+","-" )
                    $DoneFile = ( "{0}-launched-{1}.txt" -f "${DoneFile}","${Timestamp}" )
                    $DonePath = ( $DoneDir | Join-Path -ChildPath $DoneFile )

                    Move-Item -LiteralPath $OneLineLog.FullName -Destination $DonePath

                    ( "--{0}" -f $BoundaryString ) | Out-File -Append -LiteralPath ( $LogFile.FullName ) -Encoding utf8
                    ( Invoke-Expression "${cmdline}" ) 2>&1 3>&1 4>&1 | Out-File -Append -LiteralPath ( $LogFile.FullName ) -Encoding utf8
                    ( "" ) | Out-File -Append -LiteralPath ( $LogFile.FullName ) -Encoding utf8
                }

            }
            $tN = ( Get-Date )

            # Epilog: Output the time span.
            ( "--{0}--" -f $BoundaryString ) | Out-File -Append -LiteralPath ( $LogFile.FullName ) -Encoding utf8
            Invoke-BatchCommandEpilog -Start:$t0 -End:$tN | Out-File -Append -LiteralPath ( $LogFile.FullName ) -Encoding utf8

            $ToMove |% {
                $movable = $_

                $Timestamp = ( Get-Date -UFormat "%Y%m%d%H%M%S" )

                $DoneFileBase = ( $movable.FullName | Resolve-PathRelativeTo -Base $oLocation.FullName )
                $DoneFileBase = ( $DoneFileBase -replace "^[^A-Za-z0-9]+","" )
                $DoneFile = ( $DoneFileBase -replace "[^A-Za-z0-9]+","-" )
                $DoneFile = ( "{0}-run-{1}.txt" -f "${DoneFile}","${Timestamp}" )

                $DonePath = ( $DoneDir | Join-Path -ChildPath $DoneFile )

                If ( $movable | Test-CSScriptMovable -As:$As -From:$From ) {

                    If ( -Not ( Test-Path -LiteralPath $DoneDir -PathType Container ) ) {
                        $oDoneDir = ( New-Item -ItemType Directory -Path $DoneDir -Force )
                    }

                    Move-Item -LiteralPath $movable.FullName -Destination $DonePath

                }

                $DoneFile = ( $DoneFileBase -replace "[^A-Za-z0-9]+","-" )
                $DoneFile = ( "{0}-run-{1}.log" -f "${DoneFile}","${Timestamp}" )
                $DonePath = ( $DoneDir | Join-Path -ChildPath $DoneFile )
                Write-Warning ( "DONE? {0}" -f $DonePath )
                Move-Item -LiteralPath $LogFile.FullName -Destination $DonePath

                $LogFile = ( Get-Item -LiteralPath $DonePath -Force )

            }

            $LogFile.FullName
        }

    }

    End { }

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
Param ( [Parameter(ValueFromPipeline=$true)] $Item, [switch] $At=$false, [switch] $Recurse=$false, [switch] $PassThru=$false )

    Begin { }

    Process {
        ( "[{0}] CHECK: {1}{2}" -f ( Get-CommandWithVerb ),$Item.FullName,$( If ( $Recurse ) { " (recurse)" } ) ) | Write-Debug
        If ( $Recurse ) {
            $Item | Get-ChildItemPackages -At:$At -Recurse:$Recurse |? { ( ( $PassThru ) -Or ( -Not $_.CSPackageBagged ) ) }
        }
        ElseIf ( $Item -ne $null ) {
            $Item
        }
    }

    End {
    }
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

Function Invoke-CSDescribe {
Param ( [Parameter(ValueFromPipeline=$true)] $Item, [string] $For, [string] $Output, [switch] $PassThru=$false)

    Begin { }

    Process {
        $oPackage = Get-ItemPackage $Item
        If ( $oPackage -ne $null ) {
            Write-Warning ( "DESCRIBE FOR: {0}" -f $For )
            $sRepositoryName = Get-FileRepositoryName $oPackage.FullName
            $oRepositoryLocation = Get-FileRepositoryLocation $oPackage.FullName
            $oContainer = Get-ItemFileSystemLocation $oPackage
            $Description = @{ "RepositoryName"=$sRepositoryName; "Location/Repository"=$oRepositoryLocation.FullName; "FullName"=$oPackage.FullName; "Package"=$oPackage }
            Write-Warning ( $Description | ConvertTo-JSON )
            If ( $PassThru ) {
                $oPackage
            }
        }
    }

    End { }
}

$sCommandWithVerb = ( $MyInvocation.MyCommand |% { "$_" } )
$global:gCSCommandWithVerb = $sCommandWithVerb

If ( $Verbose ) {
    $VerbosePreference = "Continue"
}

if ( $Help -eq $true ) {
    Get-CSUsageNotes -cmd $MyInvocation.MyCommand
}
ElseIf ( $Version ) {
    Get-CSScriptVersion -Verb:$Verb -Words:$Words -Flags:$MyInvocation.BoundParameters | Write-Output
}
Else {

    $t0 = date
    $sCommandWithVerb = "${sCommandWithVerb} ${Verb}"
    $global:gCSCommandWithVerb = $sCommandWithVerb

    If ( $Verb.Length -gt 0 ) {
        $global:gScriptContextName = $sCommandWithVerb
    }

    $allObjects = ( @( $Words | Where { $_ -ne $null } ) + @( $Input | Where { $_ -ne $null } ) )

    If ( $Verb -eq "mirror" ) {
        $DiffLevel = 0
        if ($Diff) {
            $DiffLevel = 2
        }
        if ($SizesOnly) {
            $DiffLevel = 1
        }

        If ( $Items ) {
            $allObjects | Get-FileObject | Invoke-ColdStorageItemMirror -DiffLevel:$DiffLevel -Batch:$Batch -Force:$Force -Reverse:$Reverse -NoScan:$NoScan -RoboCopy:$RoboCopy -Scheduled:$Scheduled -WhatIf:$WhatIf
        }
        Else {
            Sync-MirroredRepositories -Pairs $Words -DiffLevel $DiffLevel -Batch:$Batch -Force:$Force -Reverse:$Reverse -NoScan:$NoScan -RoboCopy:$RoboCopy -Scheduled:$Scheduled
        }
    }
    ElseIf ( $Verb -eq "check" ) {
        If ( $Items ) {
            $allObjects | Invoke-ColdStorageItemCheck
        }
        Else {
            Invoke-ColdStorageRepositoryCheck -Pairs:$Words
        }
    }
    ElseIf ( ("validate") -ieq $Verb ) {
        $Locations = $( If ($Items) { $allObjects | Get-FileLiteralPath } Else { $Words } )
        $CSGetPackages = $( Get-CSScriptDirectory -File "coldstorage-get-packages.ps1" )
        $Locations | & "${CSGetPackages}" "${Verb}" -Items:$Items -Repository:$Repository `
            -Recurse:$Recurse `
            -At:$At `
            -Verbose:$Verbose `
            -Bagged:$Bagged -Unbagged:$Unbagged `
            -Zipped:$Zipped -Unzipped:$Unzipped `
            -Mirrored:$Mirrored -NotMirrored:$NotMirrored `
            -InCloud:$InCloud -NotInCloud:$NotInCloud `
            -Only:$Only `
            -FullName:$FullName `
            -Context:$Context `
            -Report:$Report `
            -Output:$Output `
            -PassThru:$PassThru
    }
    ElseIf ( $Verb -eq "bag" ) {
        $SkipScan = @( )
        If ( $NoScan ) {
            $SkipScan = @( "clamav" )
        }

        If ( $Items ) {
            $allObjects | Get-FileObject |? { $_ -ne $null } | Get-CSPackagesToBag -PassThru:$PassThru -At:$At -Recurse:$Recurse | Out-BagItFormattedDirectoryWhenCleared -Skip:$SkipScan -Force:$Force -Bundle:$Bundle -Manifest:$Manifest -PassThru:$PassThru -Batch:$Batch
        }
        Else {
            Invoke-ColdStorageRepositoryBag -Pairs $Words -Skip:$SkipScan -Force:$Force -Bundle:$Bundle -Manifest:$Manifest -PassThru:$PassThru -Batch:$Batch
        }

    }
    ElseIf ( $Verb -eq "rebag" ) {
        If ( $Items ) {
            $allObjects | Get-FileObject |% { Write-Verbose ( "[$Verb] CHECK: " + $_.FullName ) ; $_ } | Out-BagItFormattedDirectoryWhenCleared -Rebag -PassThru:$PassThru
        }
        Else {
            ( "[{0}] Not currently implemented for repositories. Use: {0} -Items [File1] [File2] ..." -f $sVerbWithCommandName ) | Write-Warning
        }
    }
    ElseIf ( $Verb -eq "unbag" ) {
        If ( $Items ) {
            $allObjects | Get-FileObject | Undo-CSBagPackage -PassThru:$PassThru
        }
        Else {
            ( "[{0}] Not currently implemented for repositories. Use: {0} -Items [File1] [File2] ..." -f $sVerbWithCommandName ) | Write-Warning
        }
    }
    ElseIf ( $Verb -eq "zip" ) {

        $Locations = $( If ($Items) { $allObjects | Get-FileLiteralPath } Else { $Words | Get-ColdStorageLocation -ShowWarnings } )

        $SkipScan = @( )
        If ( $NoScan ) {
            $SkipScan = @( "clamav", "bagit", "zip" )
        }
        $CSZipPackages = $( Get-CSScriptDirectory -File "coldstorage-zip-packages.ps1" )

        $Locations | & "${CSZipPackages}" -Skip:$SkipScan 

    }
    ElseIf ( ("index", "bundle") -ieq $Verb ) {
        $allObjects | ColdStorage-Command-Line -Default "${PWD}" |% { Get-FileLiteralPath $_ } | Add-IndexHTML -RelativeHref -Force:$Force -PassThru:$PassThru -Context:"${global:gCSCommandWithVerb}"
    }
    ElseIf ( $Verb -eq "describe" ) {
        If ( $For ) {
            $ForWhat = $For
            $CSDescribeArguments  = $Words
        }
        Else {
            $Preposition, $MaybeForWhat, $Remainder = $Words
            If ( "for" -eq "${Preposition}" ) {
                $ForWhat = $MaybeForWhat
                $CSDescribeArguments = $Remainder
            }
            Else {
                $ForWhat = $Preposition
                $CSDescribeArguments = $MaybeForWhat, $Remainder
            }
        }
        
        $allObjects = ( @( $CSDescribeArguments | Where { $_ -ne $null } ) + @( $Input | Where { $_ -ne $null } ) )

        $allObjects | Invoke-CSDescribe -For:$ForWhat -Output:$Output -PassThru:$PassThru

    }
    ElseIf ( $Verb -eq "manifest" ) {

        $allObjects | ColdStorage-Command-Line -Default "${PWD}" | ForEach {
            $Location = ( Get-Item -LiteralPath $_ )
            $sTitle = ( $Location | Get-ADPNetAUTitle )
            If ( -Not $sTitle ) {
                $sTitle = ( Read-Host -Prompt "AU Title [${Location}]" )
            }

            If ( $Report ) {
                $_ | Get-LOCKSSManifestHTML -Title $sTitle
            }
            Else {
                Add-LOCKSSManifestHTML -Directory $_ -Title $sTitle -Force:$Force
            }
        }
    }
    ElseIf ( $Verb -eq "bucket" ) {
        $allObjects = ( $allObjects | ColdStorage-Command-Line -Default ( ( Get-Location ).Path ) )

        $asBuckets = ( $allObjects | Get-CloudStorageBucket -Force:$Force )

        If ( ( -Not $Make ) -And ( -Not $Report ) ) {
            $asBuckets | Write-Output
        }

        If ( $Make ) {
            $asBuckets | New-CloudStorageBucket
        }

        If ( $Report ) {
            $asBuckets | Get-CloudStorageBucketProperties
        }

    }
    ElseIf ( $Verb -eq "to" ) {
        $Object, $Remainder = $Words
        $allObjects = ( ( $Remainder + $Input ) | ColdStorage-Command-Line -Default "${PWD}" )
        Invoke-ColdStorageTo -Destination:$Object -What:$allObjects -Items:$Items -Repository:$Repository -Diff:$Diff -Report:$Report -ReportOnly:$ReportOnly -Halt:$Halt -Batch:$Batch -WhatIf:$WhatIf
    }
    ElseIf ( ("cloud", "drop") -ieq $Verb ) {
        $allObjects = ( $allObjects | ColdStorage-Command-Line -Default "${PWD}" )
        Invoke-ColdStorageTo -Destination:$Verb -What:$allObjects -Items:$Items -Repository:$Repository -Diff:$Diff -Report:$Report -ReportOnly:$ReportOnly -Halt:$Halt -Batch:$Batch -WhatIf:$WhatIf
    }
    ElseIf ( ("in","vs") -ieq $Verb ) {
        $Object, $Remainder = $Words
        $allObjects = ( ( $Remainder + $Input ) | ColdStorage-Command-Line -Default "${PWD}" )
        Invoke-ColdStorageInVs -Destination:$Object -What:$allObjects -Items:$Items -Repository:$Repository -Recurse:$Recurse -Report:$Report -FullName:$FullName -Batch:$Batch -Output:$Output -Side:$Side -From:$From -To:$To -Unmatched:( $Verb -ieq "vs" ) -PassThru:$PassThru -WhatIf:$WhatIf
    }
    ElseIf ( $Verb -eq "stats" ) {
        $Words = ( $Words | ColdStorage-Command-Line -Default @("Processed","Unprocessed", "Masters") )
        ( $Words | Get-RepositoryStats -Count:($Words.Count) -Verbose:$Verbose -Batch:$Batch ) | Out-CSData -Output:$Output
    }
    ElseIf ( $Verb -eq "catchup" ) {
        $Locations = $( If ($Items) { $allObjects | Get-FileLiteralPath } Else { $Words | Get-ColdStorageLocation -ShowWarnings } )
        $CSGetPackages = $( Get-CSScriptDirectory -File "coldstorage-get-packages.ps1" )
        $Locations | & "${CSGetPackages}" -Items:$Items -Repository:$Repository -Recurse:$Recurse `
            -Unbagged -Report
        $Locations | & "${CSGetPackages}" -Items:$Items -Repository:$Repository -Recurse:$Recurse `
            -NotMirrored -Report
        $Locations | & "${CSGetPackages}" -Items:$Items -Repository:$Repository -Recurse:$Recurse `
            -Unzipped -Report
        $Locations | & "${CSGetPackages}" -Items:$Items -Repository:$Repository -Recurse:$Recurse `
            -Zipped -NotInCloud -Report
    }
    ElseIf ( $Verb -eq "packages" ) {

        $Locations = $( If ($Items) { $allObjects | Get-FileLiteralPath } Else { $Words | Get-ColdStorageLocation -ShowWarnings } )
        $CSGetPackages = $( Get-CSScriptDirectory -File "coldstorage-get-packages.ps1" )
        $Locations | & "${CSGetPackages}" -Items:$Items -Repository:$Repository `
            -Recurse:$Recurse `
            -At:$At `
            -Verbose:$Verbose `
            -Bagged:$Bagged -Unbagged:$Unbagged `
            -Zipped:$Zipped -Unzipped:$Unzipped `
            -Mirrored:$Mirrored -NotMirrored:$NotMirrored `
            -InCloud:$InCloud -NotInCloud:$NotInCloud `
            -Only:$Only `
            -FullName:$FullName `
            -Context:$Context `
            -Progress:$Progress `
            -Report:$Report `
            -Output:$Output
        
    }
    ElseIf ( $Verb -eq "script" ) {
        If ( -Not $Posted ) {
            $Words | Invoke-CSScriptedSession -Batch:$Batch
        }
        Else {
            $Location = ( Get-ColdStorageSettings -Name "Script-Queue" | ConvertTo-ColdStorageSettingsFilePath )
            $User = [System.Security.Principal.WindowsIdentity]::GetCurrent()
            $Scripts = ( Get-ChildItem -Recurse -LiteralPath "${Location}" |% {
                $File = $_

                If ( Test-Path -LiteralPath $File.FullName -PathType Leaf ) {
                    If ( $File | Test-CSScriptAllowed -As:$User -From:$Location ) { 
                        $File
                    }
                }

            } )
            $Scripts | Invoke-CSScriptedSession -Batch:$Batch -As:$User -From:$Location
        }

    }
    ElseIf ( $Verb -eq "settings" ) {
        $Words | Invoke-ColdStorageSettings -Output:$Output
    }
    ElseIf ( $Verb -eq "test" ) {
        $Object,$Words = $Words

        If ( ( "dependencies" -eq $Object ) -Or $Dependencies ) {
            Invoke-TestDependencies -Bork:${Bork} | Format-Table
        }
        ElseIf ( "zip" -eq $Object ) {
            $Words | ColdStorage-Command-Line -Default "${PWD}" | ForEach {
                $File = Get-FileObject -File $_
                [PSCustomObject] @{ "File"=($File.FullName); "Prefix"=($File | Get-ZippedBagNamePrefix ); "Container"=($File | Get-ZippedBagsContainer).FullName }
            }
        }

    }
    ElseIf ( $Verb -eq "repository" ) {
        Invoke-ColdStorageRepository -Items:$Items -Repository:$Repository -Words:$allObjects -Output:$Output
    }
    ElseIf ( $Verb -eq "zipname" ) {
        $CSGetPackageInformationZipName = $( Get-CSScriptDirectory -File "cs-get-package-information-zip-name.ps1" )
        $allObjects | ColdStorage-Command-Line -Default "${PWD}" | & "${CSGetPackageInformationZipName}" -Debug:$Debug -Verbose:$Verbose
    }
    ElseIf ( $Verb -eq "update" ) {
        $Object, $Words = $Words
        
        Switch ( $Object ) {
            "clamav" { Sync-ClamAVDatabase }
            "plugins" { Sync-ADPNetPluginsDirectory }
            default { Write-Warning "[coldstorage $Verb] Unknown object: $Object" }
        }

    }
    ElseIf ( $Verb -eq "detail" ) {
        $Object, $Words = $Words

        Switch ( $Object ) {
            "plugins" {
                $deets = ( $Words | Get-ADPNetPlugins | Get-ADPNetPluginDetails )
                If ( $Name.Count -gt 0 ) {
                    $aName = ( $Name |% { $_ -split "," } )
                    $aName |% { $deets[$_] }
                }
                Else {
                    $deets
                }
            }
            default { Write-Warning "[coldstorage $Verb] Unknown object: $Object" }
        }
    }
    ElseIf ( $Verb -eq "list" ) {
        $Object, $Words = $Words

        Switch ( $Object ) {
            "plugins" { $Words | Get-ADPNetPlugins }
            "buckets" { $Words | Get-CloudStorageListOfBuckets -Output:$Output -From:$From -To:$To -PassThru:$PassThru -FullName:$FullName }
            default { Write-Warning "[coldstorage $Verb] Unknown object: $Object" }
        }

    }
    ElseIf ( $Verb -eq "has" ) {
        $Object, $Words = $Words

        Switch ( $Object ) {
            "date" { $Input | Select-CSHasDate -From:$From -To:$To -InCloud:$InCloud -NotInCloud:$NotInCloud }
            default { ( "[{0}] Unknown test: has {1}" -f $global:gCSCommandWithVerb,$Object ) | Write-Warning }
        }

    }
    ElseIf ( $Verb -eq "settle" ) {
        Invoke-ColdStorageSettle -Words:$allObjects -Bucket:$Bucket -Force:$Force -Batch:$Batch -Zipped:$Zipped
    }
    ElseIf ( $Verb -eq "bleep" ) {
        Write-BleepBloop
    }
    ElseIf ( $Verb -eq "echo" ) {
        $aFlags = $MyInvocation.BoundParameters
        "Verb", "Words" |% { $Removed = ( $aFlags.Remove($_) ) }

        $oEcho = @{ "FLAGS"=( $MyInvocation.BoundParameters ); "WORDS"=( $Words ); "VERB"=( $Verb ); "PIPED"=( $Input ) }
        [PSCustomObject] $oEcho | Out-CSStream -Stream:$Output
    }
    Else {
        Get-CSUsageNotes -cmd $MyInvocation.MyCommand
    }


    if ( $Batch -and ( -Not $Quiet ) ) {
        $tN = ( Get-Date )
        
        Invoke-BatchCommandEpilog -Start:$t0 -End:$tN
    }
}
