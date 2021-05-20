﻿<#
.SYNOPSIS
ADAHColdStorage Digital Preservation maintenance and utility script with multiple subcommands.
@version 2021.0520

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
    [switch] $Diff = $false,
    [switch] $SizesOnly = $false,
	[switch] $Batch = $false,
    [switch] $Interactive = $false,
    [switch] $Repository = $true,
    [switch] $Items = $false,
    [switch] $Recurse = $false,
    [switch] $NoScan = $false,
    [switch] $NoValidate = $false,
    [switch] $Bucket = $false,
    [switch] $Make = $false,
    [switch] $Halt = $false, 
    [switch] $Bundle = $false,
    [switch] $Force = $false,
    [switch] $FullName = $false,
    [switch] $Unbagged = $false,
    [switch] $Unzipped = $false,
    [switch] $Zipped = $false,
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
    [Parameter(ValueFromRemainingArguments=$true, Position=1)] $Words,
    [Parameter(ValueFromPipeline=$true)] $Piped
)
$RipeDays = 7

$Verbose = ( $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent )
$Debug = ( $PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent )

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
$bVerboseModules = ( $Debug -eq $false )
$bForceModules = ( ( $Debug -eq $false ) -or ( $psISE ) )
$bForceModules = $true

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

Function Did-It-Have-Validation-Errors {
Param ( [Parameter(ValueFromPipeline=$true)] $Message )

Begin { $ExitCode = 0 }

Process {
    If ( -Not ( $Message -match "^OK-" ) ) {
        $ExitCode = $ExitCode + 1
    }
}

End { $ExitCode }

}

Function Test-UserApproved {
Param ( [Parameter(ValueFromPipeline=$true)] $Candidate, [String] $Prompt, [String] $Default="N" )

Begin { }

Process {
    $FormattedPrompt = $Prompt
    If ( $Prompt -match "\{[0-9]\}" ) {
        $FormattedPrompt = ( $Prompt -f $Candidate )
    }

    $ShouldWeContinue = ( Read-Host $FormattedPrompt )
    If ( $ShouldWeContinue -match "^[YyNn].*" ) {
        $ShouldWeContinue = ( $ShouldWeContinue )[0]
    }
    Else {
        $ShouldWeContinue = $Default
    }

    If ( $ShouldWeContinue -eq "Y" ) {
        $Candidate
    }
}

End { }

}

Function Shall-We-Continue {
Param ( [Parameter(ValueFromPipeline=$true)] $Item, [switch] $Force=$false, [Int[]] $OKCodes=@( 0 ) )

Begin { $result = $true }

Process {
    $ExitCode = $null

    If ( $Item | Get-Member -MemberType NoteProperty -Name CSScannedOK ) {
        $ErrorCodes = ( $Item | Get-CSScannedFilesErrorCodes )
    }
    ElseIf ( ( $Item -is [Int] ) -or ( $Item -is [Long] ) -or ( $Item -is [Array] ) ) {
    # Singleton, treat as an ExitCode, with default convention 0=OK, 1..255=Error
        $ErrorCodes = ( $Item |% { $ExitCode=$_ ; $ok = ( $OKCodes -eq $ExitCode ) ; If ( $ok.Count -eq 0 ) { [PSCustomObject] @{ "ExitCode"=$ExitCode; "OK"=$OKCodes } } } )
    }

    $ShouldWeContinue = "Y"
    $ErrorCodes |% {
        $Error = $_
        If ( $Error ) {
            $ExitCode = $Error.ExitCode
            $Tag = $( If ( $Error.Tag ) { "[{0}] " -f $Error.Tag } Else { "" } )
            
            $Mesg = ( "{0}Exit Code {1:N0}" -f $Tag, $ExitCode )
            If ( $result ) {
                If ( $Force ) {
                    ( "{0}; continuing anyway due to -Force flag" -f $Mesg ) | Write-Warning
                    $ShouldWeContinue = "Y"
                }
                Else {
                    $ShouldWeContinue = ( Read-Host ( "{0}. Continue (Y/N)? " -f $Mesg ) )
                }
            }
            Else {
                ( "{0}; stopped due to user input." -f $Mesg ) | Write-Warning
            }

            $result = ( $result -and ( $ShouldWeContinue -eq "Y" ) )
        }
    }
}

End { $result }

}

Function Where-Item-Is-Ripe {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $ReturnObject=$false )

Begin { $timestamp = Get-Date }

Process {
    $oFile = Get-FileObject -File $File
    $span = ( ( $timestamp ) - ( $oFile.CreationTime ) )
    If ( ( $span.Days ) -ge ( $RipeDays ) ) {
        If ( $ReturnObject ) {
            $oFile
        }
        Else {
            $oFile.FullName
        }
    }
}

End { }

}

Function Get-CurrentLine {
    $MyInvocation.ScriptLineNumber
}

# Bleep Bleep Bleep Bleep Bleep Bleep -- BLOOP!
function Do-Bleep-Bloop () {
    #Return

    [console]::beep(659,250) ##E
    [console]::beep(659,250) ##E
    [console]::beep(659,300) ##E
    [console]::beep(523,250) ##C
    [console]::beep(659,250) ##E
    [console]::beep(784,300) ##G
    [console]::beep(392,300) ##g
    [console]::beep(523,275) ## C
    [console]::beep(392,275) ##g
    [console]::beep(330,275) ##e
    [console]::beep(440,250) ##a
    [console]::beep(494,250) ##b
    [console]::beep(466,275) ##a#
    [console]::beep(440,275) ##a
}

Function Get-Command-With-Verb {
    $sCommandWithVerb
}

function Rebase-File {
    [CmdletBinding()]

   param (
    [String]
    $To,

    [Parameter(ValueFromPipeline=$true)]
    $File
   )

   Begin {}

   Process {
    $BaseName = $File.Name
    $Object = $To + "\" + $BaseName
    $Object
   }

   End {}
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
## BagIt DIRECTORIES ########################################################################################
#############################################################################################################


#############################################################################################################
## BagIt PACKAGING CONVENTIONS ##############################################################################
#############################################################################################################

Function Get-BaggedItemNoticeMessage {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $Prefix, $Zip=$false, $Suffix=$null )

    Begin { }

    Process {

    $oFile = ( Get-FileObject($File) | Add-ERInstanceData -PassThru )

    $LogMesg = ""
    If ( $Prefix ) {
        $LogMesg = ( "{0}: {1}" -f $Prefix, $LogMesg ) 
    }

    $ERCode = ( $oFile.CSPackageERMeta.ERCode )

    $FileNameSlug = ( $oFile.Name )
    If ( $ERCode -ne $null ) {
        $FileNameSlug = ( "{0}, {1}" -f $ERCode,$FileNameSlug )
    }
    $LogMesg = ( "{0}{1}" -f $LogMesg,$FileNameSlug )

    If ( $Zip ) {
        $sZip = $oZip.Name
        $LogMesg += " (ZIP=${sZip})"
    }

    If ( $Suffix -ne $null ) {
        If ( $Suffix -notmatch "^\s+" ) {
            $LogMesg += ", "
        }
        
        $LogMesg += $Suffix
    }

    $LogMesg

    }

    End { }

}

Function Write-BaggedItemNoticeMessage {
Param( $File, $Item=$null, $Status=$null, $Message=$null, [switch] $Zip=$false, [switch] $Quiet=$false, [switch] $Verbose=$false, [switch] $ReturnObject=$false, $Line=$null )

    $Prefix = "BAGGED"
    If ( $Status -ne $null ) {
        $Prefix = $Status
    }

    If ( $Zip ) {
        $oZip = ( Get-ZippedBagOfUnzippedBag -File $File )
    }

    If ( $Prefix -like "BAG*" ) {
        If ( $oZip ) {
            $Prefix = "BAG/ZIP"
        }
    }

    If ( ( $Debug ) -and ( $Line -ne $null ) ) {
        $Prefix = "${Prefix}:${Line}"
    }

    $LogMesg = ($File | Get-BaggedItemNoticeMessage -Prefix $Prefix -Zip $Zip -Suffix $Message)

    If ( $Zip -and ( $oZip -eq $null ) ) { # a ZIP package was expected, but was not found.
        Write-Warning $LogMesg
    }
    ElseIf ( $Verbose ) {
        Write-Verbose $LogMesg
    }

    If ( ( $ReturnObject ) -and ( $Status -ne "SKIPPED" ) ) {
        Write-Output $Item
    }
    ElseIf ( $Zip -and ( $oZip -ne $null ) ) {
        # NOOP
    }
    ElseIf ( $Verbose ) {
        # NOOP
    }
    ElseIf ( $Quiet -eq $false ) {
        Write-Output $LogMesg
    }

}

Function Write-Unbagged-Item-Notice {
Param( $File, $Status=$null, $Message=$null, [switch] $Quiet=$false, [switch] $Verbose=$false, $Line=$null )

    $Prefix = "UNBAGGED"
    If ( $Status -ne $null ) {
        $Prefix = $Status
    }
    If ( $Line -ne $null ) {
        $Prefix = "${Prefix}:${Line}"
    }

    $LogMesg = ($File | Get-BaggedItemNoticeMessage -Prefix $Prefix -Suffix $Message)

    If ( $Verbose ) {
        Write-Verbose $LogMesg
    }
    Else {
        Write-Warning $LogMesg
    }

}

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
        $Output = ( & $( Get-ExeForPython ) "${BagItPy}" . 2>&1 )
        $NotOK = $LASTEXITCODE

        If ( $NotOK -gt 0 ) {
            "ERR-BagIt: returned ${NotOK}" | Write-Verbose
            $Output | Write-Error
        }
        Else {
            
            # Send the bagit.py console output to Verbose stream
            $Output 2>&1 |% { "$_" -replace "[`r`n]","" } | Write-Verbose
            
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

    Begin { $cmd = ( Get-Command-With-Verb ) }

    Process {
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

############################################################################################################
## FILE / DIRECTORY COMPARISON FUNCTIONS ###################################################################
############################################################################################################

function Is-Matched-File ($From, $To, $DiffLevel=0) {
    $ToPath = $To
    if ( Get-Member -InputObject $To -name "FullName" -MemberType Properties ) {
        $ToPath = $To.FullName
    }

    $TreatAsMatched = ( Test-Path -LiteralPath "${ToPath}" )
    if ( $TreatAsMatched ) {
        $ObjectFile = (Get-Item -Force -LiteralPath "${ToPath}")
        if ( $DiffLevel -gt 0 ) {
            $TreatAsMatched = -Not ( Test-DifferentFileContent -From $From -To $ObjectFile -DiffLevel $DiffLevel )
        }
    }
    
    $TreatAsMatched
}

function Get-Unmatched-Items {
    [CmdletBinding()]

   param (
    [String]
    $Match,

    [String]
    $Exclude="^$",

    [Int]
    $DiffLevel = 0,

    $Progress=$null,

    [Parameter(ValueFromPipeline=$true)]
    $File
   )

   Begin { }

   Process {
        If ( $Progress -ne $null ) { $Progress.Update( ( "{0}" -f $File.Name ) ) }
        
        If ( -Not ( $File.Name -match $Exclude ) ) { 
            $Object = ($File | Rebase-File -To $Match)
            if ( -Not ( Is-Matched-File -From $File -To $Object -DiffLevel $DiffLevel ) ) {
                $File
            }
        }
   }

   End { }
}

function Get-Matched-Items {
    [CmdletBinding()]

   param (
    [String]
    $Match,

    [Int]
    $DiffLevel = 0,

    $Progress=$null,

    [Parameter(ValueFromPipeline=$true)]
    $File
   )

   Begin {}

   Process {
        If ( $Progress -ne $null ) { $Progress.Update( $File.Name ) }

        $Object = ($File | Rebase-File -To $Match)
        if ( Is-Matched-File -From $File -To $Object -DiffLevel $DiffLevel ) {
            $File
        }
   }

   End {}
}

Function Test-UnmirroredDerivedItem {
Param( [Parameter(ValueFromPipeline=$true)] $File, $LiteralPath=$null, [switch] $MirrorBaggedCopies=$false ) 

Begin { }

Process {
    $result = $false

    $Path = ( Get-FileLiteralPath -File $File )
    $oFile = ( Get-FileObject -File $File )

    If ( $Path ) {
        If ( Test-Path -PathType Container -LiteralPath $Path ) { # Directory

            If ( Test-ZippedBagsContainer -File $Path ) {
                $result = $true        
            }
            ElseIf ( $oFile | Test-ColdStoragePropsDirectory ) {
                $result = $true
            }
            ElseIf ( -Not $MirrorBaggedCopies ) {
                If ( Test-BaggedCopyOfLooseFile -File $oFile ) {
                    $result = $true
                }
            }

        }
        Else { # File

            If ( Test-ZippedBag -LiteralPath $Path ) {
                $result = $true
            }
            ElseIf ( $oFile | Test-ColdStorageRepositoryPropsFile ) {
                $result = $true
            }

        }
    }

    $result

}

End { If ( $LiteralPath.Count -gt 0 ) { $LiteralPath | Test-UnmirroredDerivedItem -LiteralPath:$null -MirrorBaggedCopies:$MirrorBaggedCopies } }

}


#############################################################################################################
## ADPNET DROP SERVER FUNCTIONS #############################################################################
#############################################################################################################


#############################################################################################################
## COMMAND FUNCTIONS ########################################################################################
#############################################################################################################

Function Do-Make-Bagged-ChildItem-Map {
Param( $LiteralPath=$null, $Path=$null, [switch] $Zipped=$false )

    Get-BaggedChildItem -LiteralPath $LiteralPath -Path $Path -Zipped:${Zipped} | % {
        $_.FullName
    }
}

Function Copy-MirroredFile {
Param ( $From, $To, $Direction="over", [switch] $Batch=$false, [switch] $ReadOnly=$false, $Progress=$null )

    $o1 = ( Get-Item -Force -LiteralPath "${From}" )

    If ( $Progress ) {
        $I0 = $Progress.I
        $Progress.Update( ( "Copying: #{0}/{1}. {2}" -f ( ( $Progress.I - $I0 + 1), ( $Progress.N - $I0 + 1), $o1.Name ) ), 0, "${CopyFrom} =>> ${CopyTo}" )
    }
    Else {
        $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
        $Progress.Open( ( "Copying Mirrored File [{0}]" -f ( ( Get-FileSystemLocation $o1 ).FullName | Resolve-Path -Relative ) ),  ( "Copying: {0}" -f ( $o1.Name ) ), 1 )
    }

    If ( $o1.Count -gt 0 ) {
        If ( $Batch ) {
            Copy-Item -LiteralPath "${From}" -Destination "${To}"
        }
        Else {
            Try {
                Start-BitsTransfer -Source "${From}" -Destination "${To}" -Description "${Direction} to ${To}" -DisplayName "Copy from ${From}" -ErrorAction Stop
            }
            Catch {
                "[Copy-MirroredFile] Start-BitsTransfer raised an exception ..." | Write-Error
            }
        }
    }

    If ( -Not ( Test-Path -LiteralPath "${To}" ) ) {
        "[Copy-MirroredFile] ... attempting to fall back to Copy-Item" | Write-Warning
        Copy-Item -LiteralPath "${From}" -Destination "${To}"
    }

    $Progress.Update( ( "Copied: #{0}/{1}. {2}" -f ( ( $Progress.I - $I0 + 1 ), ( $Progress.N - $I0 + 1 ), $o1.Name ) ), 1 )

    If ( $ReadOnly ) {
	    Try {
	    	Set-ItemProperty -Path "$to" -Name IsReadOnly -Value $true
	    }
	    Catch {
		    "[Copy-MirroredFile] setting read-only failed: ${To}" | Write-Error
	    }
    }
}

function Sync-ItemMetadata ($From, $To, $Progress=$null, [switch] $Verbose) {
    
    if (Test-Path -LiteralPath $from) {
        $oFrom = (Get-Item -Force -LiteralPath $from)

        if (Test-Path -LiteralPath $to) {
            $oTo = (Get-Item -Force -LiteralPath $to)

            $altered = $false
            if ($oTo.LastWriteTime -ne $oFrom.LastWriteTime) {
                $oTo.LastWriteTime = $oFrom.LastWriteTime
                $altered = $true
            }
            if ($oTo.CreationTime -ne $oTo.CreationTime) {
                $oTo.CreationTime = $oFrom.CreationTime
                $altered = $true
            }

            $Acl = $null
            $Acl = Get-Acl -LiteralPath $oFrom.FullName
            $oOwner = $Acl.GetOwner([System.Security.Principal.NTAccount])

            $Acl = $null
            $Acl = Get-Acl -LiteralPath $oTo.FullName
            $acl.SetOwner($oOwner)

            If ($altered -or $verbose) {
                If ( $Progress ) {
                    $Progress.Log("meta:${oFrom} => meta:${oTo}")
                }
            }
        }
        else {
            if ($verbose) {
                Write-Error "Destination ${to} does not seem to exist."
            }
        }
    }
    else {
        Write-Error "Source ${from} does not seem to exist."
    }
}

Function Remove-ItemToTrash {
Param ( [Parameter(ValueFromPipeline=$true)] $From)

    Begin { }

    Process {
        $From = Get-FileLiteralPath($From)
        $To = ($From | Get-MirrorMatchedItem -Trashcan -IgnoreBagging)

        ( "Trashcan Path: {0}" -f $To ) | Write-Debug
        ( "[Remove-ItemsToTrash] Move-Item -LiteralPath {0} -Destination {1} -Force" -f $From, $To ) | Write-Verbose

        $TrashContainer = ( $To | Split-Path -Parent )
        If ( -Not ( Test-Path -LiteralPath $TrashContainer ) ) {
            "[Remove-ItemsToTrash] Create destination container: ${TrashContainer}" | Write-Verbose
            $TrashContainer = ( New-Item -ItemType Directory -Path $TrashContainer -Force )
        }

        Move-Item -LiteralPath $From -Destination $To -Force
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

Function Remove-MirroredFilesWhenObsolete {
Param ($From, $To, [switch] $Batch=$false, $Depth=0)

    ( "[mirror] Remove-MirroredFilesWhenObsolete -From:{0} -To:{1} -Batch:{2} -Depth:{3} -ProgressId:{4} -NewProgressId:{5}" -f $From, $To, $Batch, $Depth, $ProgressId, $NewProgressId ) | Write-Debug

    $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )

    $aDirs = Get-ChildItem -LiteralPath "$To"
    $N = $aDirs.Count

    $sFiles = ( "file" | Get-PluralizedText($N) )
    $Progress.Open( "Matching (rm): [${To}]", ( "{0:N0} {1}" -f $N, $sFiles ), $N )

    $aDirs | Get-Unmatched-Items -Match "$From" -DiffLevel 0 -Progress:$Progress | ForEach {

        $BaseName = $_.Name
        $MoveFrom = $_.FullName
        If ( -Not ( $_ | Test-UnmirroredDerivedItem ) ) {
            $MoveFrom | Remove-ItemToTrash
        }
        Else {
            "[mirror:Remove-MirroredFilesWhenObsolete] SKIPPED (UNMIRRORED DERIVED ITEM): [${MoveFrom}]" | Write-Verbose
        }
    }
    $Progress.Complete()

}

Function Sync-MirroredDirectories {
Param ($From, $to, $DiffLevel=1, [switch] $Batch=$false, $Depth=0)
    $aDirs = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aDirs = Get-ChildItem -Directory -LiteralPath "$From"
    }

    $N = $aDirs.Count

    $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )

    $sFiles = ( "file" | Get-PluralizedText($N) )
    $Progress.Open( "Matching (mkdir): [${From}]", ( "{0:N0} {1}" -f $N, $sFiles ), $N )

    $aDirs | Get-Unmatched-Items -Match "${To}" -DiffLevel 0 -Progress:$Progress | ForEach {
        If ( -Not ( $_ | Test-UnmirroredDerivedItem -MirrorBaggedCopies ) ) {
            $CopyFrom = $_.FullName
            $CopyTo = ($_ | Rebase-File -To "${To}")

            Write-Output "${CopyFrom}\\ =>> ${CopyTo}\\"
            Copy-Item -LiteralPath "${CopyFrom}" -Destination "${CopyTo}"
        }
    }
    $Progress.Complete()
}

Function Copy-MirroredFiles {
Param ($From, $To, [switch] $Batch=$false, $DiffLevel=1, $Depth=0, $Progress=$null)

    $aFiles = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aFiles = ( Get-ChildItem -File -LiteralPath "$From" )
    }
    $N = $aFiles.Count

    $newProgress = $false
    If ( $Progress -eq $null ) {
        $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
        $newProgress = $true
    }


    $sFiles = ( "file" | Get-PluralizedText($N) )
    If ( $newProgress ) {
        $matchingProgress = $Progress
    }
    Else {
        $matchingProgress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
    }
    
    $matchingProgress.Open( "Matching Files (cp) [${From} => ${To}]", ( "{0:N0} {1}" -f $N, $sFiles ), $N )
    $aFiles = ( $aFiles | Get-Unmatched-Items -Exclude "Thumbs[.]db" -Match "${To}" -DiffLevel $DiffLevel -Progress:$matchingProgress )
    $N = $aFiles.Count
    $matchingProgress.Complete()

    If ( $newProgress ) {
        $Progress.Open( ( "Copying Unmatched {0} [{1} => {2}]" -f $sFiles, $From, $To ), ( "{0:N0} {1}" -f $N, $sFiles ), $N )
    }
    Else {
        $Progress.InsertSegment( $N )
        $Progress.Redraw()    
    }

    $aFiles | ForEach {
        $BaseName = $_.Name
        $CopyFrom = $_.FullName
        $CopyTo = ($_ | Rebase-File -To "${To}")
        
        If ( -Not ( $_ | Test-UnmirroredDerivedItem -MirrorBaggedCopies ) ) {
            Copy-MirroredFile -From:${CopyFrom} -To:${CopyTo} -Batch:${Batch} -Progress:${Progress}
        }

    }
    $Progress.Complete()
}

Function Sync-Metadata {
Param( $From, $To, $Progress=$null, [switch] $Batch=$false )

    $aFiles = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aFiles = ( Get-ChildItem -LiteralPath "$From" | Get-Matched-Items -Match "${To}" -DiffLevel 0 )
    }
    $N = $aFiles.Count
    $sFiles = ( "file" | Get-PluralizedText($N) )

    If ( $Progress -eq $null ) {
        $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
        $Progress.Open( "Synchronizing metadata [${From}]", ( "{0:N0} {1}" -f $N, $sFiles ), $N )
    }
    Else {
        $Progress.InsertSegment( $N + 1 )
        $Progress.Update( ( "Synchronizing metadata: {0:N0} {1} [${From}]" -f $N, $sFiles ) )
    }

    $I0 = $Progress.I
    $aFiles | ForEach  {
        $CopyFrom = $_.FullName
        $CopyTo = ($_ | Rebase-File -To "${To}")

        $Progress.Update( ( "Meta: #{0:N0}/{1:N0}. {2}" -f ( ( $Progress.I - $I0 + 1 ), $N, $_.Name ) ) )

        Sync-ItemMetadata -From "${CopyFrom}" -To "${CopyTo}" -Verbose:$false -Progress:$Progress
    }
    $Progress.Complete()
}

Function Sync-MirroredFiles {
Param ($From, $To, $DiffLevel=1, $Depth=0, [switch] $Batch=$false)

    $sActScanning = "Scanning contents: [${From}]"
    $sStatus = "*.*"

    If ( -Not ( Test-Path -LiteralPath "${To}" ) ) {
        $ErrMesg = ( "[{0}] Sync-MirroredFiles: Destination '{1}' cannot be found." -f $global:gCSSCriptName, $To )
        Write-Error $ErrMesg
        Return
    }

    $sTo = $To
    If (Test-BagItFormattedDirectory -File $To) {
        If ( -Not ( Test-BagItFormattedDirectory -File $From ) ) {
            $oPayload = ( Get-FileObject($To) | Select-BagItPayloadDirectory )
            $To = $oPayload.FullName
        }
    }

    $Steps = @(
        "Remove-MirroredFilesWhenObsolete"
        "Sync-MirroredDirectories"
        "Copy-MirroredFiles"
        "Sync-Metadata"
        "recurse"
    )
    $nSteps = $Steps.Count

    $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
    $Progress.Open( $sActScanning, "${sStatus} (sync)", $nSteps + 1 )

    ##################################################################################################################
    ### CLEAN UP (rm): Files on destination not (no longer) on source get tossed out. ################################
    ##################################################################################################################

    $Progress.Update( $sActScanning, "${sStatus} (rm)" )
    Remove-MirroredFilesWhenObsolete -From $From -To $To -Batch:$Batch -Depth $Depth

    ##################################################################################################################
    ## COPY OVER (mkdir): Create child directories on destination to mirror subdirectories of source. ################
    ##################################################################################################################

    $Progress.Update( "${sStatus} (mkdir)" )
    Sync-MirroredDirectories -From $From -To $To -Batch:$Batch -DiffLevel $DiffLevel -Depth $Depth

    ##################################################################################################################
    ## COPY OVER (cp): Copy snapshot files onto destination to mirror files on source. ###############################
    ##################################################################################################################

    $Progress.Update( "${sStatus} (cp)" )
    Copy-MirroredFiles -From $From -To $To -Batch:$Batch -DiffLevel $DiffLevel -Depth $Depth # -Progress:$Progress

    ##################################################################################################################
    ## METADATA: Synchronize source file system meta-data to destination #############################################
    ##################################################################################################################

    $Progress.Update( "${sStatus} (meta)" )
    Sync-Metadata -From $From -To $To -Batch:$Batch # -Progress:$Progress

    ##################################################################################################################
    ### RECURSION: Drop down into child directories and do the same mirroring down yonder. ###########################
    ##################################################################################################################

    $aFiles = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aFiles = ( Get-ChildItem -Directory -LiteralPath "$From" | Get-Matched-Items -Match "$To" -DiffLevel 0 )
    }
    $N = $aFiles.Count
    
    $Progress.InsertSegment( $N )
    $Progress.Redraw()

    $sFiles = ( "file" | Get-PluralizedText($N) )
    $aFiles | ForEach {
        $BaseName = $_.Name
        $MirrorFrom = $_.FullName
        $MirrorTo = ($_ | Rebase-File -To "${To}")

        $Mesg = ( "{4:N0}/{5:N0}: ${BaseName}" )
        $Progress.Update( $Mesg, 0 )
        Sync-MirroredFiles -From "${MirrorFrom}" -To "${MirrorTo}" -DiffLevel $DiffLevel -Depth ($Depth + 1) -Batch:$Batch
        $Progress.Update( $Mesg )
    }
    $Progress.Complete()
}

function Do-Mirror-Repositories ($Pairs=$null, $DiffLevel=1, [switch] $Batch=$false) {

    $mirrors = ( Get-ColdStorageRepositories )

    $Pairs = ($Pairs | % { If ( $_.Length -gt 0 ) { $_ -split "," } })

    if ( $Pairs.Count -lt 1 ) {
        $Pairs = $mirrors.Keys
    }

    $Progress = [CSProgressMessenger]::new( -Not $Batch, $Batch )
    $Progress.Open( "Mirroring between ADAHFS servers and ColdStorage", ( "{0} {1}" -f $Pairs.Count, ( "location" | Get-PluralizedText($Pairs.Count) ) ), $Pairs.Count )
    $Pairs | ForEach {
        $Pair = $_

        if ( $mirrors.ContainsKey($Pair) ) {
            $locations = $mirrors[$Pair]

            $slug = $locations[0]
            $src = (Get-Item -Force -LiteralPath $locations[2] | Get-LocalPathFromUNC ).FullName
            $dest = (Get-Item -Force -LiteralPath $locations[1] | Get-LocalPathFromUNC ).FullName

            $Progress.Update(("Location: {0}" -f $Pair), 0) 
            Sync-MirroredFiles -From "${src}" -To "${dest}" -DiffLevel $DiffLevel -Batch:$Batch
            $Progress.Update(("Location: {0}" -f $Pair)) 
        } else {
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
                Do-Mirror-Repositories -Pairs $recurseInto -DiffLevel $DiffLevel -Batch:$Batch
            }
            Else {
                Write-Warning "No such repository: ${Pair}."
            }
        } # if
    }
    $Progress.Complete()
}

# Out-BagItFormattedDirectoryWhenCleared: invoke a malware scanner (ClamAV) to clear preservation packages, then a bagger (BagIt.py) to bag them
# Formerly known as: Do-Clear-And-Bag
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
                $Payload = ( $File | Select-BagItPayloadDirectory )
                $Bag = ( $Payload.Parent )
                
                $OldManifest = "bagged-${Date}"
                Write-Verbose "We'll have to rebag it, I spose."

                Push-Location $Bag.FullName
                
                $Dates = ( Get-ChildItem -LiteralPath . |% { $_.CreationTime.ToString("yyyyMMdd") } ) | Sort-Object -Descending
                $sDate = ($Dates[0])
                $OldManifest = ".\bagged-${sDate}"
                  
                Get-ChildItem -LiteralPath . |% { If ( $_.Name -ne $Payload.Name ) {
                    $ChildName = $_.Name

                    If ( -Not ( $ChildName -match "^bagged-[0-9]+$" ) ) {
                        $Dest = "${OldManifest}\${ChildName}"

                        If ( -Not ( Test-Path -LiteralPath $OldManifest ) ) {
                            New-Item -ItemType Directory -Path $OldManifest
                        }

                        Move-Item $_.FullName -Destination $Dest -Verbose
                    }

                } }

                Move-Item $Payload -Destination "rebag-data" -Verbose
                
                Push-Location "rebag-data"

                $PWD | Out-BagItFormattedDirectory -PassThru:$PassThru -Progress:$Progress
                
                Get-ChildItem -LiteralPath . |% {
                    Move-Item $_.FullName -Destination $Bag.FullName -Verbose
                }

                Pop-Location

                Remove-Item "rebag-data"

                Pop-Location $Anchor

                Write-Verbose ( $Bag ).FullName

                If ( $PassThru ) {
                    ( $Bag ) | Write-Output
                }

                #Move-Item -LiteralPath ( $payloadDir ).FullName -
            }

        }
        ElseIf ( Test-ERInstanceDirectory($File) ) {
            If ( -not ( $BaseName -match $Exclude ) ) {

                Push-Location $DirName

                if ( Test-BagItFormattedDirectory($File) ) {
                    Write-BaggedItemNoticeMessage -File $File -Item:$File -Quiet:$Quiet -Line ( Get-CurrentLine )
                }
                else {
                    Write-Unbagged-Item-Notice -File $File -Quiet:$Quiet -Verbose -Line ( Get-CurrentLine )
                    
                    $NotOK = ( $DirName | Do-Scan-ERInstance )
                    If ( $NotOK | Shall-We-Continue ) {
                        Out-BagItFormattedDirectory -DIRNAME $DirName -PassThru:$PassThru -Progress:$Progress
                    }

                }

                Pop-Location
            }
            Else {
                Write-BaggedItemNoticeMessage -Status "SKIPPED" -File $File -Item:$File -Quiet:$Quiet -Line ( Get-CurrentLine )
            }

        }
        ElseIf ( Test-IndexedDirectory($File) ) {
            #$ToScanAndBag += , [PSCustomObject] @{
            #    "Message"=@{ "FileName"=$File.Name; "Message"="indexed directory. Scan it, bag it and tag it."; "Line"=( Get-CurrentLine ) };
            #    "File"=$File.FullName;
            #    "Method"="Out-BagItFormattedDirectory"
            #}
            Write-Unbagged-Item-Notice -File $File -Message "indexed directory. Scan it, bag it and tag it." -Verbose -Line ( Get-CurrentLine )
            If ( $File | Select-CSPackagesOK -Exclude:$Exclude -Quiet:$Quiet -Force:$Force -Rebag:$Rebag -ContinueCodes:@( 0..255 ) -Skip:$Skip -ShowWarnings | Shall-We-Continue -Force:$Force ) {
                $File | Out-BaggedPackage -PassThru:$PassThru -Progress:$Progress
            }
        }
        Else {
            Get-ChildItem -File -LiteralPath $File.FullName | ForEach {
                $ChildItem = $_
                If ( Test-UnbaggedLooseFile($ChildItem) ) {
                    $LooseFile = $ChildItem.Name
                    #$ToScanAndBag += , [PSCustomObject] @{
                    #    "Message"=@{ "FileName"=$File.Name; "Message"="loose file. Scan it, bag it and tag it."; "Line"=( Get-CurrentLine ) };
                    #    "File"=$File.FullName;
                    #    "Method"="Out-BaggedPackage"
                    #}

                    Write-Unbagged-Item-Notice -File $ChildItem -Message "loose file. Scan it, bag it and tag it." -Verbose -Line ( Get-CurrentLine )

                    if ( $ChildItem | Select-CSPackagesOK -Exclude:$Exclude -Quiet:$Quiet -Force:$Force -Rebag:$Rebag -ContinueCodes:@( 0..255 ) -Skip:$Skip -ShowWarnings | Shall-We-Continue -Force:$Force ) {
                        $ChildItem | Out-BaggedPackage -PassThru:$PassThru -Progress:$Progress
                    }
                }
                ElseIf ( $PassThru -and ( Test-LooseFile($ChildItem) ) ) {
                    $ChildItem | Get-BaggedCopyOfLooseFile | Write-Output
                }
                Else {
                    Write-BaggedItemNoticeMessage -File $ChildItem -Item:$File -Message "loose file -- already bagged." -Verbose -Line ( Get-CurrentLine )
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
    $OnUnbagged={ Param($File, $Quiet); Write-Unbagged-Item-Notice -File $File -Line ( Get-CurrentLine ) -Quiet:$Quiet },

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
            Do-Bleep-Bloop
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
                    Write-Unbagged-Item-Notice -File $File -Quiet:$Quiet -Line ( Get-CurrentLine )
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
            Write-Unbagged-Item-Notice -File $File -Message "indexed directory" -Quiet:$Quiet -Line ( Get-CurrentLine )
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
            Do-Bleep-Bloop
        }
    }
}

function Do-Scan-ERInstance () {
    [CmdletBinding()]

param (
    [Parameter(ValueFromPipeline=$true)]
    $Path
)

    Begin { }

    Process {
        If ( -Not $NoScan ) {
            "ClamAV Scan: ${Path}" | Write-Verbose -InformationAction Continue
            $ClamAV = Get-ExeForClamAV
            $Output = ( & "${ClamAV}" --stdout --bell --suppress-ok-results --recursive "${Path}" )
            if ( $LastExitCode -gt 0 ) {
                $Output | Write-Warning
                $LastExitCode
            }
            Else {
                $Output | Write-Verbose
            }
        }
        Else {
            "ClamAV Scan SKIPPED for path ${Path}" | Write-Verbose -InformationAction Continue
        }
    }

    End { }
}

function Test-CSBaggedPackageValidates ($DIRNAME, [String[]] $Skip=@( ), [switch] $Verbose = $false) {

    Push-Location $DIRNAME

    $BagIt = Get-PathToBagIt
    $BagItPy = ( $BagIt | Join-Path -ChildPath "bagit.py" )
	$Python = Get-ExeForPython

    If ( -Not ( -Not ( ( $Skip |% { $_.ToLower().Trim() } ) | Select-String -Pattern "^bagit$" ) ) ) {
        "BagIt Validation SKIPPED for path ${DIRNAME}" | Write-Verbose -InformationAction Continue
        "OK-BagIt: ${DIRNAME} (skipped)" # > stdout
    }
    ElseIf ( $Verbose ) {
        "bagit.py --validate ${DIRNAME}" | Write-Verbose
        & $( Get-ExeForPython ) "${BagItPy}" --validate . 2>&1 |% { "$_" -replace "[`r`n]","" } | Write-Verbose
        $NotOK = $LastExitCode

        if ( $NotOK -gt 0 ) {
            $OldErrorView = $ErrorView; $ErrorView = "CategoryView"
            
            "ERR-BagIt: ${DIRNAME}" | Write-Warning

            $ErrorView = $OldErrorView
        } else {
            "OK-BagIt: ${DIRNAME}" # > stdout
        }

    }
    Else {
        $Output = ( & $( Get-ExeForPython ) "${BagItPy}" --validate . 2>&1 )
        $NotOK = $LastExitCode
        if ( $NotOK -gt 0 ) {
            $OldErrorView = $ErrorView; $ErrorView = "CategoryView"
            
            "ERR-BagIt: ${DIRNAME}" | Write-Warning
            $Output |% { "$_" -replace "[`r`n]","" } | Write-Warning

            $ErrorView = $OldErrorView
        } else {
            "OK-BagIt: ${DIRNAME}" # > stdout
        }
    }

    Pop-Location

}

Function Get-CSItemValidation {

Param ( [Parameter(ValueFromPipeline=$true)] $Item, [switch] $Summary=$true )

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
        }
        ElseIf ( Test-ZippedBag -LiteralPath $sLiteralPath ) {
            $Validated = ( $_ | Test-ZippedBagIntegrity  )
        }

        $nChecked = $nChecked + 1
        $nValidated = $nValidated + $Validated.Count

        $Validated # > stdout
    }
}

End {
    If ( $Summary ) {
        "Validation: ${nValidated} / ${nChecked} validated OK." # > stdout
    }
}

}

# Invoke-BagChildDirectories: Given a parent directory (typically a repository root), loop through each child directory and do a clear-and-bag
# Formerly known as: Do-Bag-Repo-Dirs
Function Invoke-BagChildDirectories ($Pair, $From, $To, $Skip=@(), [switch] $Force=$false, [switch] $Bundle=$false, [switch] $PassThru=$false, [switch] $Batch=$false) {
    Push-Location $From
    Get-ChildItem -Directory | Out-BagItFormattedDirectoryWhenCleared -Quiet -Exclude $null -Skip:$Skip -Force:$Force -Bundle:$Bundle -PassThru:$PassThru -Batch:$Batch
    Pop-Location
}

# Invoke-ColdStorageRepositoryBag
# Formerly known as: Do-Bag
function Invoke-ColdStorageRepositoryBag ($Pairs=$null, $Skip=@(), [switch] $Force=$false, [switch] $Bundle=$false, [switch] $PassThru=$false, [switch] $Batch=$false) {
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

        Invoke-BagChildDirectories -Pair "${Pair}" -From "${src}" -To "${dest}" -Skip:$Skip -Force:$Force -Bundle:$Bundle -PassThru:$PassThru -Batch:$Batch
        $i = $i + 1
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
        
        If ( $Validated | Did-It-Have-Validation-Errors | Shall-We-Continue ) {

            $oZip = ( Get-ZippedBagOfUnzippedBag -File $oFile )

            $Result = $null

            If ( $oZip.Count -gt 0 ) {
                $sArchiveHashed = $oZip.FullName
                $Result = [PSCustomObject] @{ "Bag"=$sFile; "Zip"="${sArchiveHashed}"; "New"=$false; "Validated"=$Validated; "Compressed"=$null }
                $Progress.Update( "Located archive with MD5 Checksum", 2 )
            }
            Else {
                $Progress.Update( "Compressing archive" )

                $oRepository = ( $oFile | Get-ZippedBagsContainer )
                $sRepository = $oRepository.FullName

                $ts = $( Date -UFormat "%Y%m%d%H%M%S" )
                $sZipPrefix = ( Get-ZippedBagNamePrefix -File $oFile )

                $sZipName = "${sZipPrefix}_z${ts}"
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

Function Stop-CloudStorageUploadsToBucket {
Param ( [Parameter(ValueFromPipeline=$true)] $Bucket, [switch] $Batch=$false, [switch] $WhatIf=$false )

    Begin { If ( $WhatIf ) { $sWhatIf = "--dryrun" } Else { $sWhatIf = $null } }

    Process {

        $sMultipartUploadsJSON = ( & $( Get-ExeForAWSCLI ) s3api list-multipart-uploads --bucket "${Bucket}" )
        $oMultipartUploads = $( $sMultipartUploadsJSON | ConvertFrom-Json )
        $oMultipartUploads.Uploads |% {
            $Key = $_.Key
            $UploadId = $_.UploadId
            If ( $Key -and $UploadId ) {
                If ( $Batch ) {
                    Write-Warning "ABORT {$Key}, # ${UploadId} ..."
                    $cAbort = 'Y'
                }
                Else {
                    $cAbort = ( Read-Host -Prompt "ABORT ${Key}, # ${UploadId}? (Y/N)" )
                }
                If ( $cAbort[0] -ieq 'Y' ) {
                    If ( $WhatIf ) {
                        ( "& {0} {1} {2} {3} {4} {5} {6} {7} {8}" -f $( Get-ExeForAWSCLI ),"s3api","abort-multipart-upload","--bucket","${Bucket}","--key","${Key}","--upload-id","${UploadId}" ) | Write-Output
                    }
                    Else {
                        & $( Get-ExeForAWSCLI ) s3api abort-multipart-upload --bucket "${Bucket}" --key "${Key}" --upload-id "${UploadId}"
                    }
                }
            }
        }

    }

    End { }

}

Function Stop-CloudStorageUploads {
Param ( [Parameter(ValueFromPipeline=$true)] $Package, [switch] $Batch=$false, [switch] $WhatIf=$false )

    Begin {
        $Buckets = @{ }
    }

    Process {
        If ( $Package ) {
            $MaybeBucket = ( Get-FileObject($Package) | Get-CloudStorageBucket )
            If ( $MaybeBucket ) {
                $Buckets[$MaybeBucket] = $true
            }
        }
        Else {
            ( "[{0}] Could not determine cloud storage bucket for item: '{1}'" -f $global:gCSCommandWithVerb,$Package ) | Write-Warning
        }
    }

    End {
        $Buckets.Keys | Stop-CloudStorageUploadsToBucket -Batch:$Batch -WhatIf:$WhatIf
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

    If ( -Not $Items ) {
        Write-Warning ( "[${global:gScriptContextName}:${Destination}] Not yet implemented for repositories. Try: & coldstorage to ${Destination} -Items [File1] [File2] [...]" )
    }
    ElseIf ( $Destination -eq "cloud" ) {
        If ( $Halt ) {
            $What | Stop-CloudStorageUploads -Batch:$Batch -WhatIf:$WhatIf
        }
        ElseIf ( $Diff ) {
            $Anchor = $PWD
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
Param ( [string] $Destination, $What, [switch] $Items=$false, [switch] $Repository=$false, [switch] $Recurse=$false, [switch] $Report=$false, [switch] $Batch=$false, [String] $Output="", [String[]] $Side, [switch] $Unmatched=$false, [switch] $FullName=$false, [switch] $PassThru=$false, [switch] $WhatIf=$false )

        $Destinations = ("cloud", "drop", "adpnet")
        Switch ( $Destination ) {
            "cloud" { 
                $aSide = ( $Side |% { $_ -split "," } )
                If ( $Items ) {
                    $aItems = $What
                } Else {
                    $aItems = ( Get-ZippedBagsContainer -Repository:$What )
                }

                $aItems | Get-CloudStorageListing -Unmatched:$Unmatched -Side:($aSide) -Recurse:$true -Context:("{0} {1}" -f $global:gCSCommandWithVerb,$Destination ) -ReturnObject | Select-CSFileInfo -FullName:$FullName -ReturnObject:$PassThru
            }
            default {
                ( "[{0} {1}] Unknown destination. Try: ({2})" -f ($global:gCSCommandWithVerb, $Destination, ( $Destinations -join ", " )) ) | Write-Warning
            }
        }

}


Function Write-ColdStoragePackagesReport {
Param (
    [Parameter(ValueFromPipeline=$true)] $Package,
    [switch] $Report=$false,
    [string] $Output="",
    [switch] $FullName=$false,
    $Timestamp,
    $Context

)

    Begin { $Subsequent = $false; $sDate = ( Get-Date $Timestamp -Format "MM-dd-yyyy" ) }

    Process {
        $oContext = ( Get-FileObject $Context )

        Push-Location ( $oContext | Get-ItemFileSystemLocation ).FullName

        $sFullName = $Package.FullName
        $sRelName = ( Resolve-Path -Relative -LiteralPath $Package.FullName )
        $sTheName = $( If ( $FullName ) { $sFullName } Else { $sRelName } )

        Pop-Location

        $nBaggedFlag = $( If ( $Package.CSPackageBagged ) { 1 } Else { 0 } )
        $sBaggedFlag = $( If ( $Package.CSPackageBagged ) { "BAGGED" } Else { "unbagged" } )
        If ( $Package | Get-Member -MemberType NoteProperty -Name CSPackageZip ) {
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
        $sBaggedLocation = $( If ( $Package.CSPackageBagLocation -and ( $Package.CSPackageBagLocation.FullName -ne $Package.FullName ) ) { ( " # bag: {0}" -f ( $Package.CSPackageBagLocation.FullName | Resolve-PathRelativeTo -Base $Package.FullName ) ) } Else { "" } )

        If ( $Report ) {
            If ( "CSV" -ieq $Output ) {

                @{} `
                | Select-Object @{ n="Date"; e={ $sDate } },
                                @{ n="Name"; e={ $sTheName } },
                                @{ n="Bag"; e={ $sBaggedFlag } },
                                @{ n="Bagged"; e={ $nBaggedFlag } },
                                @{ n="ZipFile"; e={ $sZippedFile } },
                                @{ n="Zipped"; e={ $nZippedFlag } },
                                @{ n="Files"; e={ $nContents } },
                                @{ n="Contents"; e={ $sContents } },
                                @{ n="Bytes"; e={ $nFileSize } },
                                @{ n="Size"; e={ $sFileSizeReadable  } },
                                @{ n="Context"; e={ $oContext.FullName } } `
                | ConvertTo-CSV -NoTypeInformation | Select-Object -Skip:$( If ($Subsequent) { 1 } Else { 0 } )


            }
            Else {
                         
                $sBagged = ( " ({0})" -f $sBaggedFlag )
                $sZipped = $( If ( $sZippedFlag -ne $null ) { ( " ({0})" -f $sZippedFlag ) } Else { "" } )

                ( "{0}{1}{2}, {3}, {4}{5}" -f $sTheName,$sBagged,$sZipped,$sContents,$sFileSizeReadable,$sBaggedLocation )
            
            }
        }
        Else {
            $_ | Select-CSFileInfo -FullName:$FullName -ReturnObject:(-Not $FullName)
        }
        $Subsequent = $true
    }

    End { }
}

Function Select-ColdStoragePackagesToReport {
Param (
    [Parameter(ValueFromPipeline=$true)] $Package,
    [switch] $Unbagged,
    [switch] $Unzipped
)

    Begin { }

    Process {
        If ( -Not ( $Unbagged -and ( $Package.CSPackageBagged ) ) ) {
            If ( -Not ( $Unzipped -and ( $Package.CSPackageZip ) ) ) {
                $_
            }
        }
    }

    End { }
}

Function Invoke-ColdStoragePackagesReport {
Param (
    [Parameter(ValueFromPipeline=$true)] $Location,
    [switch] $Recurse,
    [switch] $ShowWarnings,
    [switch] $Unbagged,
    [switch] $Unzipped,
    [switch] $Zipped,
    [switch] $FullName,
    [switch] $Report,
    [string] $Output
)

    Begin { $CurDate = ( Get-Date ) }

    Process {
        $CheckZipped = ( $Unzipped -or $Zipped )
        $Location | Get-ChildItemPackages -Recurse:$Recurse -ShowWarnings:$ShowWarnings -CheckZipped:$CheckZipped |
            Select-ColdStoragePackagesToReport -Unbagged:$Unbagged -Unzipped:$Unzipped |
            Write-ColdStoragePackagesReport -Report:$Report -Output:$Output -FullName:$FullName -Context:$Location -Timestamp:$CurDate
    }

    End { }

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
Param ( $Words, [switch] $Bucket=$false, [switch] $Force=$false, [switch] $Batch=$false )

    Begin { }

    Process {
        $sLocation, $Remainder = ( $Words )
        $PropsFileName = "props.json"
        $DefaultProps = $null

        If ( $sLocation -eq "here" ) {
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
            $oFile | Add-CSPropsFile -PassThru -Props:@( $Props, $DefaultProps ) -Name:$PropsFileName -Force:$Force | Where { $Bucket } | Add-ZippedBagsContainer
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

function Do-Write-Usage ($cmd) {
    $mirrors = ( Get-ColdStorageRepositories )

    $Pairs = ( $mirrors.Keys -Join "|" )
    $PairedCmds = ("bag", "zip", "validate")

    Write-Output "Usage: `t$cmd mirror [-Batch] [-Diff] [$Pairs]"
    $PairedCmds |% {
        $verb = $_
        Write-Output "       `t${cmd} ${verb} [$Pairs]"
    }
    Write-Output "       `t${cmd} -?"
    Write-Output "       `t`tfor detailed documentation"
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
Param ( [Parameter(ValueFromPipeline=$true)] $Item, [switch] $Recurse=$false, [switch] $PassThru=$false )

    Begin { }

    Process {
        If ( $Recurse ) {
            $Item | Get-ChildItemPackages -Recurse:$Recurse |? { ( ( $PassThru ) -Or ( -Not $_.CSPackageBagged ) ) }
        }
        Else {
            $Item
        }
    }

    End {
    }
}

$sCommandWithVerb = ( $MyInvocation.MyCommand |% { "$_" } )
$global:gCSCommandWithVerb = $sCommandWithVerb

If ( $Verbose ) {
    $VerbosePreference = "Continue"
}

if ( $Help -eq $true ) {
    Do-Write-Usage -cmd $MyInvocation.MyCommand
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
        $N = ( $Words.Count )

        $DiffLevel = 0
        if ($Diff) {
            $DiffLevel = 2
        }
        if ($SizesOnly) {
            $DiffLevel = 1
        }

        If ( $Items ) {
            $Words |% {
                $File = Get-FileObject($_)
                If ( $File ) {
                    $oRepository = ( Get-FileRepositoryLocation -File $File )
                    $sRepository = $oRepository.FullName
                    $RepositorySlug = ( Get-FileRepositoryName -File $File )

                    $Src = ( $File | Get-MirrorMatchedItem -Pair $RepositorySlug -Original -All )
                    $Dest = ( $File | Get-MirrorMatchedItem -Pair $RepositorySlug -Reflection -All )

                    Write-Debug ( "REPOSITORY: {0}" -f $sRepository )
                    Write-Debug ( "SLUG: {0}" -f $RepositorySlug )
                    Write-Verbose ( "FROM: {0}; TO: {1}" -f $Src, $Dest )
                    Write-Verbose ( "DIFF LEVEL: {0}" -f $DiffLevel )

                    If ( -Not $WhatIf ) {
                        Sync-MirroredFiles -From "${Src}" -To "${Dest}" -DiffLevel $DiffLevel -Batch:$Batch
                    }
                    Else {
                        Write-Host "(WhatIf) Sync-MirroredFiles -From '${Src}' -To '${Dest}' -DiffLevel $DiffLevel -Batch $Batch"
                    }

                }

                #$locations = $mirrors[$Pair]

                #$slug = $locations[0]
                #$src = (Get-Item -Force -LiteralPath $locations[2] | Get-LocalPathFromUNC ).FullName
                #$dest = (Get-Item -Force -LiteralPath $locations[1] | Get-LocalPathFromUNC ).FullName

            }
        }
        Else {
            Do-Mirror-Repositories -Pairs $Words -DiffLevel $DiffLevel -Batch:$Batch
        }

    }
    ElseIf ( $Verb -eq "check" ) {
        $N = ( $Words.Count )
        If ( $Items ) {
            $Words |% {
                $File = Get-FileObject($_)
                If ( $File ) {
                    $Pair = ($_ | Get-FileRepositoryName)
                    Invoke-ColdStorageDirectoryCheck -Pair:$Pair -From:$File.FullName -To:$File.FullName -Batch:$Batch
                }
                Else {
                    ( "Item Not Found: {0}" -f $_ ) | Write-Warning
                }
            }
        }
        Else {
            Invoke-ColdStorageRepositoryCheck -Pairs $Words
        }
    }
    ElseIf ( $Verb -eq "validate" ) {
        If ( $Items ) {
            $allObjects | Get-CSItemValidation -Verbose:$Verbose
        }
        Else {
            Invoke-ColdStorageValidate -Pairs $Words -Verbose:$Verbose -Zipped
        }
    }
    ElseIf ( $Verb -eq "bag" ) {
        $N = ( $Words.Count )
        $SkipScan = @( )
        If ( $NoScan ) {
            $SkipScan = @( "clamav" )
        }

        If ( $Items ) {
            $allObjects | Get-FileObject |% { ( "[{0}] CHECK: {1}{2}" -f $sCommandWithVerb,$_.FullName,$( If ( $Recurse ) { " (recurse)" } ) ) | Write-Verbose; $_ } | Get-CSPackagesToBag -PassThru:$PassThru -Recurse:$Recurse | Out-BagItFormattedDirectoryWhenCleared -Skip:$SkipScan -Force:$Force -Bundle:$Bundle -PassThru:$PassThru -Batch:$Batch
        }
        Else {
            Invoke-ColdStorageRepositoryBag -Pairs $Words -Skip:$SkipScan -Force:$Force -Bundle:$Bundle -PassThru:$PassThru -Batch:$Batch
        }

    }
    ElseIf ( $Verb -eq "rebag" ) {
        $N = ( $Words.Count )
        If ( $Items ) {
            $Words | Get-Item -Force |% { Write-Verbose ( "[$Verb] CHECK: " + $_.FullName ) ; $_ } | Out-BagItFormattedDirectoryWhenCleared -Rebag -PassThru:$PassThru
        }
    }
    ElseIf ( $Verb -eq "unbag" ) {
        If ( $Items ) {
            $Words | Get-Item -Force | Undo-CSBagPackage
        }
        Else {
            Write-Warning "[$sVerbWithCommandName] Not currently implemented for repositories. Use -Items [File1] [File2] ..."
        }
    }
    ElseIf ( $Verb -eq "zip" ) {

        $SkipScan = @( )
        If ( $NoScan ) {
            $SkipScan = @( "clamav", "bagit", "zip" )
        }

        $allObjects |% {
            $sFile = Get-FileLiteralPath -File $_
            If ( Test-BagItFormattedDirectory -File $sFile ) {
                $_ | Compress-CSBaggedPackage -Skip:$SkipScan
            }
            ElseIf ( Test-LooseFile -File $_ ) {
                $oBag = ( Get-BaggedCopyOfLooseFile -File $_ )
                If ($oBag) {
                    $oBag | Compress-CSBaggedPackage -Skip:$SkipScan
                }
                Else {
                    Write-Warning "${sFile} is a loose file not a BagIt-formatted directory."
                }
            }
            Else {
                $_ | Get-Item -Force |% { Get-BaggedChildItem -LiteralPath $_.FullName } | Compress-CSBaggedPackage -Skip:$SkipScan
            }
        }

    }
    ElseIf ( ("index", "bundle") -ieq $Verb ) {
        $Words = ( $Words | ColdStorage-Command-Line -Default "${PWD}" )
        $Words | Add-IndexHTML -RelativeHref -Force:$Force -Context:"${global:gCSCommandWithVerb}"
    }
    ElseIf ( $Verb -eq "manifest" ) {

        $allObjects | ColdStorage-Command-Line -Default "${PWD}" | ForEach {
            $Location = ( Get-Item -LiteralPath $_ )
            $sTitle = ( $Location | Get-ADPNetAUTitle )
            If ( -Not $sTitle ) {
                $sTitle = ( Read-Host -Prompt "AU Title [${Location}]" )
            }

            Add-LOCKSSManifestHTML -Directory $_ -Title $sTitle -Force:$Force
        }
    }
    ElseIf ( $Verb -eq "drop" ) {
        $Words = ( $Words | ColdStorage-Command-Line -Default "${PWD}" )

        $Words | Add-ADPNetAUToDropServerStagingDirectory
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
        $Words = ( ( $Remainder + $Input ) | ColdStorage-Command-Line -Default "${PWD}" )
        Invoke-ColdStorageTo -Destination:$Object -What:$Words -Items:$Items -Repository:$Repository -Diff:$Diff -Report:$Report -ReportOnly:$ReportOnly -Halt:$Halt -Batch:$Batch -WhatIf:$WhatIf
    }
    ElseIf ( ("in","vs") -ieq $Verb ) {
        $Object, $Remainder = $Words
        $Words = ( ( $Remainder + $Input ) | ColdStorage-Command-Line -Default "${PWD}" )
        Invoke-ColdStorageInVs -Destination:$Object -What:$Words -Items:$Items -Repository:$Repository -Recurse:$Recurse -Report:$Report -FullName:$FullName -Batch:$Batch -Output:$Output -Side:$Side -Unmatched:( $Verb -ieq "vs" ) -PassThru:$PassThru -WhatIf:$WhatIf
    }
    ElseIf ( $Verb -eq "cloud" ) {
        $aSide = ( $Side |% { $_ -split "," } )

        If ( $Items ) {
            $Words | Get-CloudStorageListing -Unmatched:$Diff -Side:($aSide)
        }
        Else {
            ( Get-ZippedBagsContainer -Repository:$Words ) | Get-CloudStorageListing -Unmatched:$Diff -Side:($aSide)
        }
    }
    ElseIf ( $Verb -eq "stats" ) {
        $Words = ( $Words | ColdStorage-Command-Line -Default @("Processed","Unprocessed", "Masters") )
        ( $Words | Get-RepositoryStats -Count:($Words.Count) -Verbose:$Verbose -Batch:$Batch ) | Out-CSData -Output:$Output
    }
    ElseIf ( $Verb -eq "packages" ) {

        $Locations = $( If ($Items) { $Words } Else { $Words | Get-ColdStorageLocation -ShowWarnings } )
        $Locations | Invoke-ColdStoragePackagesReport -Recurse:( $Recurse -or ( -Not $Items )) `
            -ShowWarnings:$Verbose `
            -Unbagged:$Unbagged `
            -Unzipped:$Unzipped `
            -Zipped:$Zipped `
            -FullName:$FullName `
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
        Invoke-ColdStorageRepository -Items:$Items -Repository:$Repository -Words:$Words -Output:$Output
    }
    ElseIf ( $Verb -eq "zipname" ) {
        $Words | ColdStorage-Command-Line -Default "${PWD}" | ForEach {
            $File = Get-FileObject -File $_
            [PSCustomObject] @{ "File"=($File.FullName); "Prefix"=($File | Get-ZippedBagNamePrefix ); "Container"=($File | Get-ZippedBagsContainer).FullName }
        }
    }
    ElseIf ( $Verb -eq "ripe" ) {
        $Words | ColdStorage-Command-Line -Default ( Get-ChildItem ) | ForEach {
            $ripe = ( ( Get-Item -Path $_ ) | Where-Item-Is-Ripe -ReturnObject )
            If ( $ripe.Count -gt 0 ) {
                $ripe
            }
        }
    }
    ElseIf ( $Verb -eq "update" ) {
        $Object, $Words = $Words
        
        Switch ( $Object ) {
            "clamav" { $ClamAV = Get-PathToClamAV ; & "${ClamAV}\freshclam.exe" }
            "plugins" {
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
            default { Write-Warning "[coldstorage $Verb] Unknown object: $Object" }
        }

    }
    ElseIf ( $Verb -eq "settle" ) {
        Invoke-ColdStorageSettle -Words:$Words -Bucket:$Bucket -Force:$Force -Batch:$Batch
    }
    ElseIf ( $Verb -eq "bleep" ) {
        Do-Bleep-Bloop
    }
    ElseIf ( $Verb -eq "echo" ) {
        $aFlags = $MyInvocation.BoundParameters
        "Verb", "Words" |% { $Removed = ( $aFlags.Remove($_) ) }

        $oEcho = @{ "FLAGS"=( $MyInvocation.BoundParameters ); "WORDS"=( $Words ); "VERB"=( $Verb ); "PIPED"=( $Input ) }
        [PSCustomObject] $oEcho | Out-CSStream -Stream:$Output
    }
    Else {
        Do-Write-Usage -cmd $MyInvocation.MyCommand
    }


    if ( $Batch -and ( -Not $Quiet ) ) {
        $tN = ( Get-Date )
        
        Invoke-BatchCommandEpilog -Start:$t0 -End:$tN
    }
}
