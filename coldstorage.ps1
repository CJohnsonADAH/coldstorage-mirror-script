<#
.SYNOPSIS
ADAHColdStorage Digital Preservation maintenance and utility script with multiple subcommands.
@version 2021.0415

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
    [switch] $Bucket = $false,
    [switch] $Make = $false,
    [switch] $Bundle = $false,
    [switch] $Force = $false,
    [switch] $FullName = $false,
    [switch] $Unbagged = $false,
    [switch] $Unzipped = $false,
    [switch] $Zipped = $false,
    [switch] $Report = $false,
    [switch] $ReportOnly = $false,
    [switch] $Dependencies = $false,
    $Props = $null,
    [String] $Output = "-",
    [String[]] $Side = "local,cloud",
    [String[]] $Name = @(),
    [String] $LogLevel=0,
    [switch] $Dev = $false,
    [switch] $Bork = $false,
    #[switch] $Verbose = $false,
    #[switch] $Debug = $false,
    [switch] $WhatIf = $false,
    [switch] $Version = $false,
    [Parameter(ValueFromRemainingArguments=$true, Position=1)] $Words
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
        $Item.Parent.FullName | Join-Path -ChildPath ( "{0}-development" -f $ScriptHomeName )
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
    Return

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

Function Get-Bagged-Item-Notice {
Param ( $Prefix, $FileName, $ERCode=$null, $Zip=$false, $Suffix=$null )
    $LogMesg = "${Prefix}: " 

    If ( $ERCode -ne $null ) {
        $LogMesg += "${ERCode}, "
    }
    $LogMesg += $FileName

    If ( $Zip ) {
        $sZip = $Zip.Name
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

Function Write-Bagged-Item-Notice {
Param( $FileName, $Item=$null, $ERCode=$null, $Status=$null, $Message=$null, $Zip=$false, [switch] $Quiet=$false, [switch] $Verbose=$false, [switch] $ReturnObject=$false, $Line=$null )

    $Prefix = "BAGGED"
    If ( $Status -ne $null ) {
        $Prefix = $Status
    }

    If ( $Prefix -like "BAG*" ) {
        If ( $Zip ) {
            $Prefix = "BAG/ZIP"
        }
    }

    If ( ( $Debug ) -and ( $Line -ne $null ) ) {
        $Prefix = "${Prefix}:${Line}"
    }

    $LogMesg = (Get-Bagged-Item-Notice -Prefix $Prefix -FileName $FileName -ERCode $ERCode -Zip $Zip -Suffix $Message)

    If ( $Zip -eq $null ) { # a ZIP package was expected, but was not found.
        Write-Warning $LogMesg
    }
    ElseIf ( $Verbose ) {
        Write-Verbose $LogMesg
    }

    If ( ( $ReturnObject ) -and ( $Status -ne "SKIPPED" ) ) {
        Write-Output $Item
    }
    ElseIf ( $Zip -eq $null ) {
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
Param( $FileName, $ERCode=$null, $Status=$null, $Message=$null, [switch] $Quiet=$false, [switch] $Verbose=$false, $Line=$null )

    $Prefix = "UNBAGGED"
    If ( $Status -ne $null ) {
        $Prefix = $Status
    }
    If ( $Line -ne $null ) {
        $Prefix = "${Prefix}:${Line}"
    }

    $LogMesg = (Get-Bagged-Item-Notice -Prefix $Prefix -FileName $FileName -ERCode $ERCode -Suffix $Message)

    If ( $Verbose ) {
        Write-Verbose $LogMesg
    }
    Else {
        Write-Warning $LogMesg
    }

}

Function Do-Bag-Directory ($DIRNAME, [switch] $Verbose=$false) {

    $Anchor = $PWD
    chdir $DIRNAME

    Get-SystemArtifactItems -LiteralPath "." | Remove-Item -Force -Verbose:$Verbose

    "PS ${PWD}> bagit.py ." | Write-Verbose
    
    $BagIt = Get-PathToBagIt
	$Python = Get-ExeForPython
    $Output = ( & $( Get-ExeForPython ) "${BagIt}\bagit.py" . 2>&1 )
    $NotOK = $LASTEXITCODE

    If ( $NotOK -gt 0 ) {
        "ERR-BagIt: returned ${NotOK}" | Write-Verbose
        $Output | Write-Error
    }
    Else {
        $Output 2>&1 |% { "$_" -replace "[`r`n]","" } | Write-Verbose
    }

    chdir $Anchor
}

function Do-Bag-Loose-File ($LiteralPath) {
    $cmd = Get-Command-With-Verb

    $Anchor = $PWD

    $Item = Get-Item -Force -LiteralPath $LiteralPath
    
    chdir $Item.DirectoryName
    $OriginalFileName = $Item.Name
    $OriginalFullName = $Item.FullName
    $FileName = ( $Item | Get-PathToBaggedCopyOfLooseFile )

    $BagDir = ".\${FileName}"
    if ( -Not ( Test-Path -LiteralPath $BagDir ) ) {
        $BagDir = mkdir -Path $BagDir
    }

    Move-Item -LiteralPath $Item -Destination $BagDir
    Do-Bag-Directory -DIRNAME $BagDir
    if ( $LastExitCode -eq 0 ) {
        $NewFilePath = "${BagDir}\data\${OriginalFileName}"
        if ( Test-Path -LiteralPath "${NewFilePath}" ) {
            New-Item -ItemType HardLink -Path $OriginalFullName -Target $NewFilePath | %{ "[$cmd] Bagged ${BagDir}, created link to payload: $_" }
	        
            Set-ItemProperty -LiteralPath $OriginalFullName -Name IsReadOnly -Value $true
            Set-ItemProperty -LiteralPath $NewFilePath -Name IsReadOnly -Value $true
        }
    }
    chdir $Anchor
}

#############################################################################################################
## index.html FOR BOUND SUBDIRECTORIES ######################################################################
#############################################################################################################

Add-Type -Assembly System.Web

function Select-URI-Link {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $RelativeTo, [switch] $RelativeHref=$false )

    Begin { Push-Location; Set-Location $RelativeTo }

    Process {
        $URL = $File.FileURI

        $FileName = ($File | Resolve-Path -Relative)

        If ( $RelativeHref ) {
            $RelativeURL = (($FileName.Split("\") | % { [URI]::EscapeDataString($_) }) -join "/")
            $HREF = [System.Web.HttpUtility]::HtmlEncode($RelativeURL)
        }
        Else {
            $HREF = [System.Web.HttpUtility]::HtmlEncode($URL)
        }

        $TEXT = [System.Web.HttpUtility]::HtmlEncode($FileName)

        '<a href="{0}">{1}</a>' -f $HREF, $TEXT
    }

    End { Pop-Location }

}

function Add-File-URI {
Param( [Parameter(ValueFromPipeline=$true)] $File, $RelativeTo=$null )

    Begin { }

    Process {
        $UNC = $File.FullName
		If ($RelativeTo -ne $null) {
			$BaseUNC = $RelativeTo.FullName
			
		}
		
        $Nodes = $UNC.Split("\") | % { [URI]::EscapeDataString($_) }

        $URL = ( $Nodes -Join "/" )
        $protocolLocalAuthority = "file:///"
        
        $File | Add-Member -NotePropertyName "FileURI" -NotePropertyValue "${protocolLocalAuthority}$URL"
        $File
    }

    End { }

}

function Add-IndexHTML {
Param( $Directory, [switch] $RelativeHref=$false, [switch] $Force=$false )

    if ( $Directory -eq $null ) {
        $Path = ( Get-Location )
    } else {
        $Path = ( $Directory )
    }

    If ( ( -Not $Force ) -And ( Test-MirrorMatchedItem -File "${Path}" -Reflection ) ) {
        $originalLocation = ( "${Path}" | Get-MirrorMatchedItem -Original )
        Write-Warning "[Add-IndexHTML] This is a mirror-image location. Setting Location to: ${originalLocation}."
        Add-IndexHTML -Directory $originalLocation -RelativeHref:$RelativeHref -Force:$Force

        $originalIndexHTML = ( Get-Item -Force -LiteralPath ( $originalLocation | Join-Path -ChildPath "index.html" ) )
        If ( $originalIndexHTML ) {
            If ( Test-Path -LiteralPath "${Path}" -PathType Container ) {
                Write-Warning "[Add-IndexHTML] Copying HTML from ${originalIndexHTML} to ${Path}."
                Copy-Item -Force:$Force -LiteralPath $originalIndexHTML -Destination "${Path}"
            }
        }

    }
    ElseIf ( Test-Path -LiteralPath "${Path}" ) {
        $UNC = ( Get-Item -Force -LiteralPath "${Path}" | Get-UNCPathResolved -ReturnObject )

        $indexHtmlPath = ( "${UNC}" | Join-Path -ChildPath "index.html" )

        If ( Test-Path -LiteralPath "${indexHtmlPath}" ) {
            If ( $Force) {
                Remove-Item -Force -LiteralPath "${indexHtmlPath}"
            }
        }

        If ( -Not ( Test-Path -LiteralPath "${indexHtmlPath}" ) ) {
            $listing = Get-ChildItem -Recurse -LiteralPath "${UNC}" | Get-UNCPathResolved -ReturnObject | Add-File-URI | Sort-Object -Property FullName | Select-URI-Link -RelativeTo $UNC -RelativeHref:${RelativeHref}

            $NL = [Environment]::NewLine

            $htmlUL = $listing | % -Begin { "<ul>" } -Process { '  <li>' + $_ + "</li>" } -End { "</ul>" }
            $htmlTitle = ( "Contents of: {0}" -f [System.Web.HttpUtility]::HtmlEncode($UNC) )

            $htmlOut = ( "<!DOCTYPE html>${NL}<html>${NL}<head>${NL}<title>{0}</title>${NL}</head>${NL}<body>${NL}<h1>{0}</h1>${NL}{1}${NL}</body>${NL}</html>${NL}" -f $htmlTitle, ( $htmlUL -Join "${NL}" ) )

            $htmlOut | Out-File -FilePath $indexHtmlPath -NoClobber:(-Not $Force) -Encoding utf8
        }
        Else {
            Write-Warning "index.html already exists in ${Directory}. To force index.html to be regenerated, use -Force flag."
        }
    }
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

Function Get-Mirror-Matched-Item {
Param( [Parameter(ValueFromPipeline=$true)] $File, $Pair, [switch] $Original=$false, [switch] $Reflection=$false, $Repositories=$null )

Begin { $mirrors = ( Get-ColdStorageRepositories ) }

Process {
    
    If ( $Original ) {
        $Range = @(0)
    }
    ElseIf ( $Reflection ) {
        $Range = @(1)
    }
    Else {
        $Range = @(0..1)
    }

    # get self if $File is a directory, parent if it is a leaf node
    $oDir = ( Get-ItemFileSystemLocation $File | Get-UNCPathResolved -ReturnObject )

    If ( $Repositories.Count -eq 0 -and ( $Pair -ne $null ) ) {
        If ( $mirrors.ContainsKey($Pair) ) {
            $Repositories = ( $mirrors[$Pair][1..2] | Get-LocalPathFromUNC |% { $_.FullName } )
            $Matchable = $Repositories[$Range]
        }
        Else {
            Write-Warning ( "Get-Mirror-Matched-Item: Requested repository pair ({0}) does not exist." -f $Pair )
        }
    }
    ElseIf ( $Pair -eq $null ) {
        Write-Warning ( "Get-Mirror-Matched-Item: No valid Repository found for item ({0})." -f $File )
    }

    $Matched = ( $Matchable -ieq $oDir.FullName )
    If ( $Matched ) {
        ($Repositories -ine $oDir.FullName)
    }
    ElseIf ( $oDir ) {
        
        $Child = ( $oDir.RelativePath -join "\" )
        $Parent = $oDir.Parent
        $sParent = $Parent.FullName

        If ( $Parent ) {
            $sParent = ( $sParent | Get-Mirror-Matched-Item -Pair $Pair -Repositories $Repositories -Original:$Original -Reflection:$Reflection )
            If ( $sParent.Length -gt 0 ) {
                $oParent = ( Get-Item -Force -LiteralPath "${sParent}" )
                $sParent = $oParent.FullName
            }
            ((( @($sParent) + $oDir.RelativePath ) -ne $null ) -ne "") -join "\"
        }
        Else {

            $oDir.FullName

        }
        
    }

}

End { }

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

Function Do-Copy-Snapshot-File ($from, $to, $direction="over", [switch] $Batch=$false, [switch] $ReadOnly=$false) {
    $o1 = ( Get-Item -Force -LiteralPath "${from}" )

    If ( $o1.Count -gt 0 ) {
        If ( $Batch ) {
            Copy-Item -LiteralPath "${from}" -Destination "${to}"
        }
        Else {
            Try {
                Start-BitsTransfer -Source "${from}" -Destination "${to}" -Description "$direction to $to" -DisplayName "Copy from $from" -ErrorAction Stop
            }
            Catch {
                Write-Error "Start-BitsTransfer raised an exception"
            }
        }
    }

    If ( -Not ( Test-Path -LiteralPath "${to}" ) ) {
        Write-Error "Attempting to fall back to Copy-Item"
        Copy-Item -LiteralPath "${from}" -Destination "${to}"
    }

    if ( $ReadOnly ) {
	    Try {
	    	Set-ItemProperty -Path "$to" -Name IsReadOnly -Value $true
	    }
	    Catch {
		    Write-Error "setting read-only failed: $to"
	    }
    }
}

function Do-Reset-Metadata ($from, $to, [switch] $Verbose) {
    
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

            if ($altered -or $verbse) {
                Write-Output "meta:${oFrom} => meta:${oTo}"
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

function Sync-Metadata ($from, $to, $verbose) {
    Get-ChildItem -Recurse "$from" | ForEach-Object -Process {

        $LocalFile = $_.FullName
        $LocalSrcDir = Split-Path -Parent $LocalFile
        $LocalSrcDirParent = Split-Path -Parent $LocalFile
        $LocalSrcDirRelPath = ""
        while ($LocalSrcDirParent -ne $from) {
            $LocalSrcDirStem = Split-Path -Leaf $LocalSrcDirParent
            $LocalSrcDirParent = Split-Path -Parent $LocalSrcDirParent
            $LocalSrcDirRelPath = "${LocalSrcDirStem}\${LocalSrcDirRelPath}"
        }

		$Basename = Split-Path -Leaf $LocalFile

        $DestinationTargetPath = "${to}\${LocalSrcDirRelPath}${Basename}"

        Set-Location $LocalSrcDir
        Do-Reset-Metadata -from $_.FullName -to $DestinationTargetPath -Verbose:$verbose
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

    $Progress = [CSProgressMessenger]::new( -Not $Batch )

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
        ElseIf ( $Verbose ) {
            "[mirror:Remove-MirroredFilesWhenObsolete] SKIPPED (UNMIRRORED DERIVED ITEM): [${MoveFrom}]" | Write-Verbose
        }
    }
    $Progress.Complete()

}

Function Do-Mirror-Directories {
Param ($From, $to, $DiffLevel=1, [switch] $Batch=$false, $Depth=0)
    $aDirs = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aDirs = Get-ChildItem -Directory -LiteralPath "$From"
    }

    $N = $aDirs.Count

    $Progress = [CSProgressMessenger]::new( -Not $Batch )

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

Function Do-Mirror-Files {
Param ($From, $To, [switch] $Batch=$false, $DiffLevel=1, $Depth=0)

    $aFiles = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aFiles = ( Get-ChildItem -File -LiteralPath "$From" )
    }
    $N = $aFiles.Count

    $Progress = [CSProgressMessenger]::new( -Not $Batch )

    $sFiles = ( "file" | Get-PluralizedText($N) )
    $Progress.Open( "Matching Files (cp) [${From} => ${To}]", ( "{0:N0} {1}" -f $N, $sFiles ), $N )

    $aFiles = ( $aFiles | Get-Unmatched-Items -Exclude "Thumbs[.]db" -Match "${To}" -DiffLevel $DiffLevel -Progress:$Progress )
    $N = $aFiles.Count

    $Progress.Open( "Copying Unmatched Files [${From} => ${To}]", ( "{0:N0} {1}" -f $N, $sFiles ), $N )
    $aFiles | ForEach {
        $BaseName = $_.Name
        $CopyFrom = $_.FullName
        $CopyTo = ($_ | Rebase-File -To "${To}")
        
        If ( -Not ( $_ | Test-UnmirroredDerivedItem -MirrorBaggedCopies ) ) {

            $Progress.Update( "${BaseName}" )
            If ( $Batch ) {
                Write-Output "${CopyFrom} =>> ${CopyTo}"
            }
        
            Do-Copy-Snapshot-File "${CopyFrom}" "${CopyTo}" -Batch:$Batch
        }

    }
    $Progress.Complete()
}

Function Do-Mirror-Metadata {
Param( $From, $To, [switch] $Batch=$false )

    $aFiles = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aFiles = ( Get-ChildItem -LiteralPath "$From" | Get-Matched-Items -Match "${To}" -DiffLevel 0 )
    }
    $N = $aFiles.Count

    $Progress = [CSProgressMessenger]::new( -Not $Batch )

    $sFiles = ( "file" | Get-PluralizedText($N) )
    $Progress.Open( "Synchronizing metadata [${From}]", ( "{0:N0} {1}" -f $N, $sFiles ), $N )

    $aFiles | ForEach  {
        $CopyFrom = $_.FullName
        $CopyTo = ($_ | Rebase-File -To "${To}")

        $Progress.Update( $_.Name )

        Do-Reset-Metadata -from "${CopyFrom}" -to "${CopyTo}" -Verbose:$false
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

    $Progress = [CSProgressMessenger]::new( -Not $Batch )
    $Progress.N = 5

    ##################################################################################################################
    ### CLEAN UP (rm): Files on destination not (no longer) on source get tossed out. ################################
    ##################################################################################################################

    $Progress.Open( $sActScanning, "${sStatus} (rm)" )
    Remove-MirroredFilesWhenObsolete -From $From -To $To -Batch:$Batch -Depth $Depth

    ##################################################################################################################
    ## COPY OVER (mkdir): Create child directories on destination to mirror subdirectories of source. ################
    ##################################################################################################################

    $Progress.Update( "${sStatus} (mkdir)" )
    Do-Mirror-Directories -From $From -To $To -Batch:$Batch -DiffLevel $DiffLevel -Depth $Depth

    ##################################################################################################################
    ## COPY OVER (cp): Copy snapshot files onto destination to mirror files on source. ###############################
    ##################################################################################################################

    $Progress.Update( "${sStatus} (cp)" )
    Do-Mirror-Files -From $From -To $To -Batch:$Batch -DiffLevel $DiffLevel -Depth $Depth

    ##################################################################################################################
    ## METADATA: Synchronize source file system meta-data to destination #############################################
    ##################################################################################################################

    $Progress.Update( "${sStatus} (meta)" )
    Do-Mirror-Metadata -From $From -To $To -Batch:$Batch

    ##################################################################################################################
    ### RECURSION: Drop down into child directories and do the same mirroring down yonder. ###########################
    ##################################################################################################################

    $Progress.Update( "${sStatus} (chdir)" )

    $aFiles = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aFiles = ( Get-ChildItem -Directory -LiteralPath "$From" | Get-Matched-Items -Match "$To" -DiffLevel 0 )
    }
    $N = $aFiles.Count
    
    $sFiles = ( "file" | Get-PluralizedText($N) )
    $Progress.Open( "Recursing into subdirectories [${From}]", ( "{0:N0} {1}" -f $N,$sFiles ), $N )
    $aFiles | ForEach {
        $BaseName = $_.Name
        $MirrorFrom = $_.FullName
        $MirrorTo = ($_ | Rebase-File -To "${To}")

        $Progress.Update( ( "{0:N0}/{1:N0}: {2}" -f @($Progress.I, $Progress.N, "${BaseName}") ), 0 )
        Sync-MirroredFiles -From "${MirrorFrom}" -To "${MirrorTo}" -DiffLevel $DiffLevel -Depth ($Depth + 1) -Batch:$Batch
        $Progress.Update( ( "{0:N0}/{1:N0}: {2}" -f @($Progress.I, $Progress.N, "${BaseName}") ) )
    }
    $Progress.Complete()
}

function Do-Mirror-Repositories ($Pairs=$null, $DiffLevel=1, [switch] $Batch=$false) {

    $mirrors = ( Get-ColdStorageRepositories )

    $Pairs = ($Pairs | % { If ( $_.Length -gt 0 ) { $_ -split "," } })

    if ( $Pairs.Count -lt 1 ) {
        $Pairs = $mirrors.Keys
    }

    $Progress = [CSProgressMessenger]::new( -Not $Batch )
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

function Do-Clear-And-Bag {

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

        $DirName = $File.FullName
        $BaseName = $File.Name

        If ( Test-ERInstanceDirectory($File) ) {
            $ERMeta = ( $File | Get-ERInstanceData )
            $ERCode = $ERMeta.ERCode
        }
        Else {
            $ERCode = $null
        }

        If ( $Bundle ) {
            If ( Test-Path -LiteralPath $DirName -PathType Container ) {
                If ( -Not ( Test-BagItFormattedDirectory($File) ) ) {
                    If ( -Not ( Test-IndexedDirectory($File) ) ) {
                        Add-IndexHTML -Directory $DirName -RelativeHref
                    }
                }
            }
        }

        If ( Test-BagItFormattedDirectory($File) ) {
            Write-Bagged-Item-Notice -FileName $File.Name -Item:$File -Message "BagIt formatted directory" -ERCode:$ERCode -Verbose -Line ( Get-CurrentLine )
            If ( $Rebag ) {
                $Payload = ( $File | Select-BagItPayloadDirectory )
                $Bag = ( $Payload.Parent )
                
                $OldManifest = "bagged-${Date}"
                Write-Verbose "We'll have to rebag it, I spose."

                $Anchor = $PWD
                Set-Location $Bag.FullName
                
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
                
                Set-Location "rebag-data"

                Do-Bag-Directory -DIRNAME ( $PWD )
                
                Get-ChildItem -LiteralPath . |% {
                    Move-Item $_.FullName -Destination $Bag.FullName -Verbose
                }

                Set-Location $Bag.FullName
                Remove-Item "rebag-data"

                Set-Location $Anchor

                Write-Verbose ( $Bag ).FullName
                #Move-Item -LiteralPath ( $payloadDir ).FullName -
            }

        }
        ElseIf ( Test-ERInstanceDirectory($File) ) {
            If ( -not ( $BaseName -match $Exclude ) ) {
                $ERMeta = ( $File | Get-ERInstanceData )
                $ERCode = $ERMeta.ERCode

                chdir $DirName

                if ( Test-BagItFormattedDirectory($File) ) {
                    Write-Bagged-Item-Notice -FileName $DirName -Item:$File -ERCode $ERCode -Quiet:$Quiet -Line ( Get-CurrentLine )
                }
                else {
                    Write-Unbagged-Item-Notice -FileName $DirName -ERCode $ERCode -Quiet:$Quiet -Verbose -Line ( Get-CurrentLine )
                    
                    $NotOK = ( $DirName | Do-Scan-ERInstance )
                    If ( $NotOK | Shall-We-Continue ) {
                        Do-Bag-Directory -DIRNAME $DirName
                    }

                }
            }
            Else {
                Write-Bagged-Item-Notice -Status "SKIPPED" -FileName $DirName -Item:$File -ERCode $ERCode -Quiet:$Quiet -Line ( Get-CurrentLine )
            }

            chdir $Anchor
        }
        ElseIf ( Test-IndexedDirectory($File) ) {
            #$ToScanAndBag += , [PSCustomObject] @{
            #    "Message"=@{ "FileName"=$File.Name; "Message"="indexed directory. Scan it, bag it and tag it."; "Line"=( Get-CurrentLine ) };
            #    "File"=$File.FullName;
            #    "Method"="Do-Bag-Directory"
            #}
            Write-Unbagged-Item-Notice -FileName $File.Name -Message "indexed directory. Scan it, bag it and tag it." -Verbose -Line ( Get-CurrentLine )
            If ( $File | Select-CSPackagesOK -Exclude:$Exclude -Quiet:$Quiet -Force:$Force -Rebag:$Rebag -ContinueCodes:@( 0..255 ) -Skip:$Skip -ShowWarnings | Shall-We-Continue -Force:$Force ) {
                Do-Bag-Directory -DIRNAME $File.FullName
            }
        }
        Else {
            Get-ChildItem -File -LiteralPath $File.FullName | ForEach {
                If ( Test-UnbaggedLooseFile($_) ) {
                    $LooseFile = $_.Name
                    #$ToScanAndBag += , [PSCustomObject] @{
                    #    "Message"=@{ "FileName"=$File.Name; "Message"="loose file. Scan it, bag it and tag it."; "Line"=( Get-CurrentLine ) };
                    #    "File"=$File.FullName;
                    #    "Method"="Do-Bag-Directory"
                    #}

                    Write-Unbagged-Item-Notice -FileName $File.Name -Message "loose file. Scan it, bag it and tag it." -Verbose -Line ( Get-CurrentLine )

                    if ( $_ | Select-CSPackagesOK -Exclude:$Exclude -Quiet:$Quiet -Force:$Force -Rebag:$Rebag -ContinueCodes:@( 0..255 ) -Skip:$Skip -ShowWarnings | Shall-We-Continue -Force:$Force ) {
                        Do-Bag-Loose-File -LiteralPath $_.FullName
                    }
                }
                Else {
                    Write-Bagged-Item-Notice -FileName $File.Name -Item:$File -Message "loose file -- already bagged." -Verbose -Line ( Get-CurrentLine )
                }
            }
        }
    }

    End {
    }
}

function Do-Scan-File-For-Bags {
    [CmdletBinding()]

param (
    [Switch]
    $Quiet,

    [String]
    $Exclude="^$",

    [ScriptBlock]
    $OnBagged={ Param($File, $Payload, $BagDir, $Quiet); $PayloadPath = $Payload.FullName; $oZip = ( Get-ZippedBagOfUnzippedBag -File $BagDir ); Write-Bagged-Item-Notice -FileName $File.FullName -Item:$File -Message " = ${PayloadPath}" -Line ( Get-CurrentLine ) -Zip $oZip -Verbose -Quiet:$Quiet },

    [ScriptBlock]
    $OnDiff={ Param($File, $Payload, $Quiet); Write-Warning ( "DIFF: {0}, {1}" -f ( $File,$Payload ) ) },

    [ScriptBlock]
    $OnUnbagged={ Param($File, $Quiet); Write-Unbagged-Item-Notice -FileName $File.FullName -Line ( Get-CurrentLine ) -Quiet:$Quiet },

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
        $Anchor = $PWD
        
        $Parent = $File.Directory
        chdir $Parent

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

        chdir $Anchor
    }

    End {
        if ( -Not $Quiet ) {
            Do-Bleep-Bloop
        }
    }

}

function Select-Unbagged-Dirs () {

    [CmdletBinding()]

    param (
        [Parameter(ValueFromPipeline=$true)]
        $File
    )

    Begin { }

    Process {
        $BaseName = $File.Name
        if ( -Not ( $BaseName -match "_bagged_[0-9]+$" ) ) {
            $BaseName
        }
    }

    End { }

}


function Do-Scan-Dir-For-Bags {

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

        # Is this an ER Instance directory?
        If ( Test-ERInstanceDirectory($File) ) {
            
            chdir $DirName
            $ERMeta = ($File | Get-ERInstanceData)
            $ERCode = $ERMeta.ERCode

            If ( -not ( $BaseName -match $Exclude ) ) {

                if ( Test-BagItFormattedDirectory($File) ) {
                    $oZip = ( Get-ZippedBagOfUnzippedBag -File $File )
                    Write-Bagged-Item-Notice -FileName $DirName -Item:$File -ERCode $ERCode -Zip $oZip -Quiet:$Quiet -Line ( Get-CurrentLine )

                } else {
                    Write-Unbagged-Item-Notice -FileName $DirName -ERCode $ERCode -Quiet:$Quiet -Line ( Get-CurrentLine )
                }
            }
            Else {
                Write-Bagged-Item-Notice -Status "SKIPPED" -FileName $DirName -Item:$File -ERCode $ERCode -Quiet:$Quiet -Line ( Get-CurrentLine )
            }

            chdir $Anchor

        }
        ElseIf ( Test-BagItFormattedDirectory($File) ) {
            $oZip = ( Get-ZippedBagOfUnzippedBag -File $File )
            Write-Bagged-Item-Notice -FileName $DirName -Item:$File -Zip $oZip -Quiet:$Quiet -Verbose -Line ( Get-CurrentLine )
        }
        ElseIf ( Test-IndexedDirectory($File) ) {
            Write-Unbagged-Item-Notice -FileName $DirName -Message "indexed directory" -Quiet:$Quiet -Line ( Get-CurrentLine )
        }
        Else {

            chdir $DirName
            
            dir -File | Add-Member -NotePropertyName "CheckedSpace" -NotePropertyValue ( $File.CheckedSpace ) -PassThru | Do-Scan-File-For-Bags -Progress:$Progress -Quiet:$Quiet
            dir -Directory | Select-Unbagged-Dirs | Add-Member -NotePropertyName "CheckedSpace" -NotePropertyValue ( $File.CheckedSpace ) -PassThru | Do-Scan-Dir-For-Bags -Progress:$Progress -Quiet:$Quiet

            chdir $Anchor
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

function Do-Validate-Bag ($DIRNAME, [switch] $Verbose = $false) {

    $Anchor = $PWD
    chdir $DIRNAME

    $BagIt = Get-PathToBagIt
	$Python = Get-ExeForPython
    If ( $Verbose ) {
        "bagit.py --validate ${DIRNAME}" | Write-Verbose
        & $( Get-ExeForPython ) "${BagIt}\bagit.py" --validate . 2>&1 |% { "$_" -replace "[`r`n]","" } | Write-Verbose
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
        $Output = ( & $( Get-ExeForPython ) "${BagIt}\bagit.py" --validate . 2>&1 )
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

    chdir $Anchor
}

Function Do-Validate-Item {

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
            $Validated = ( Do-Validate-Bag -DIRNAME $_ -Verbose:$Verbose  )
        }
        ElseIf ( Test-ZippedBag -LiteralPath $sLiteralPath ) {
            $Validated = ( $_ | Test-ZippedBagIntegrity )
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

function Do-Bag-Repo-Dirs ($Pair, $From, $To, $Skip=@(), [switch] $Force=$false) {
    $Anchor = $PWD 

    chdir $From
    dir -Attributes Directory | Do-Clear-And-Bag -Quiet -Exclude $null -Skip:$Skip -Force:$Force
    chdir $Anchor
}

function Do-Bag ($Pairs=$null, $Skip=@(), [switch] $Force=$false ) {
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

        Do-Bag-Repo-Dirs -Pair "${Pair}" -From "${src}" -To "${dest}" -Skip:$Skip -Force:$Force
        $i = $i + 1
    }
}

function Invoke-ColdStorageDirectoryCheck {
Param ($Pair, $From, $To, [switch] $Batch=$false)

    $Anchor = $PWD

    chdir $From

    $Progress = [CSProgressMessenger]::new( -Not $Batch )
    $Progress.Open( ( "Checking {0}" -f $From ), "Files" )
    $Progress.Update( "Files", 1, 100 )

    dir -File | Add-Member -NotePropertyName "CheckedSpace" -NotePropertyValue $From -PassThru | Do-Scan-File-For-Bags -Progress:$Progress -Quiet:$Quiet

    $Progress.Update( "Directories", 51, 100 )

    dir -Directory | Add-Member -NotePropertyName "CheckedSpace" -NotePropertyValue $From -PassThru | Do-Scan-Dir-For-Bags -Progress:$Progress -Quiet:$Quiet -Exclude $null

    $Progress.Completed()

    chdir $Anchor
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

Function Do-Validate ($Pairs=$null, [switch] $Verbose=$false, [switch] $Zipped=$false, [switch] $Batch=$false) {
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

            $MapFile = "${src}\validate-bags.map.txt"
            $BookmarkFile = "${src}\validate-bags.bookmark.txt"

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
            $Progress = [CSProgressMessenger]::new( -Not $Batch )
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

                        $Validated = ( $BagPath | Do-Validate-Item -Verbose:$Verbose -Summary:$false )
                        
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
                Do-Validate -Pairs $recurseInto -Verbose:$Verbose -Zipped:$Zipped
            }
        } # if

        $i = $i + 1
    }

}

Function Do-Zip-Bagged-Directory {
Param( [Parameter(ValueFromPipeline=$true)] $File, $Batch = $false )

Begin { }

Process {
    
    $Progress = [CSProgressMessenger]::new( -Not $Batch )
    $Progress.Open( ( "Processing {0}" -f "${sArchive}" ), "Validating bagged preservation package", 5 )

    If ( Test-BagItFormattedDirectory -File $File ) {
        $oFile = Get-FileObject -File $File
        $sFile = Get-FileLiteralPath -File $File

        $Validated = ( Do-Validate-Bag -DIRNAME $sFile )

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
                $Result | Add-Member -MemberType NoteProperty -Name "Validated-Zip" -Value ( Test-ZippedBagIntegrity -File $sArchiveHashed )
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

Function Do-CloudUploadsAbort {

    $Bucket = "er-collections-unprocessed"

    $sMultipartUploadsJSON = ( & aws s3api list-multipart-uploads --bucket "${Bucket}" )
    $oMultipartUploads = $( $sMultipartUploadsJSON | ConvertFrom-Json )
    $oMultipartUploads.Uploads |% {
        $Key = $_.Key
        $UploadId = $_.UploadId
        If ( $Key -and $UploadId ) {
            $cAbort = ( Read-Host -Prompt "ABORT ${Key}, # ${UploadId}? (Y/N)" )
            If ( $cAbort[0] -ieq 'Y' ) {
                & aws s3api abort-multipart-upload --bucket "${Bucket}" --key "${Key}" --upload-id "${UploadId}"
            }
        }
    }
}

Function Invoke-ColdStorageTo {
Param ( [string] $Destination, $What, [switch] $Items, [switch] $Repository, [switch] $Diff, [switch] $WhatIf, [switch] $Report, [switch] $ReportOnly )

    $Destinations = ("cloud", "drop", "adpnet")

    If ( -Not $Items ) {
        Write-Warning ( "[${global:gScriptContextName}:${Destination}] Not yet implemented for repositories. Try: & coldstorage to ${Destination} -Items [File1] [File2] [...]" )
    }
    ElseIf ( $Destination -eq "cloud" ) {
        If ( $Diff ) {
            $Anchor = $PWD
            $Candidates = ( $What | Get-Item -Force | Get-CloudStorageListing -Unmatched:$true -Side:("local") -ReturnObject )
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
        Push-Location $oContext.FullName
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

                ( "{0}{1}{2}, {3}, {4}" -f $sTheName,$sBagged,$sZipped,$sContents,$sFileSizeReadable )
            
            }
        }
        ElseIf ( $FullName ) {
            $_.FullName
        }
        Else {
            $_
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

Function Invoke-BatchCommandEpilog {
Param ( $Start, $End )

    ( "Completed: {0}" -f $End ) | Write-Output
    ( New-Timespan -Start:$Start -End:$End ) | Write-Output

}

$sCommandWithVerb = ( $MyInvocation.MyCommand |% { "$_" } )

If ( $Verbose ) {
    $VerbosePreference = "Continue"
}

if ( $Help -eq $true ) {
    Do-Write-Usage -cmd $MyInvocation.MyCommand
}
ElseIf ( $Version ) {
    $oHelpMe = ( Get-Help ${global:gCSScriptPath} )
    $ver = ( $oHelpMe.Synopsis -split "@" |% { If ( $_ -match '^version\b' ) { $_ } } )
    If ( $ver.Count -gt 0 ) { Write-Output "${global:gCSScriptName} ${ver}" }
    Else { $oHelpMe }
}
Else {
    $t0 = date
    $sCommandWithVerb = "${sCommandWithVerb} ${Verb}"
    
    If ( $Verb.Length -gt 0 ) {
        $global:gScriptContextName = $sCommandWithVerb
    }

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
        $N = ( $Words.Count )

        If ( $Items ) {
            $Words | Do-Validate-Item -Verbose:$Verbose
        }
        Else {
            Do-Validate -Pairs $Words -Verbose:$Verbose -Zipped
        }
    }
    ElseIf ( $Verb -eq "bag" ) {
        $N = ( $Words.Count )
        $SkipScan = @( )
        If ( $NoScan ) {
            $SkipScan = @( "clamav" )
        }

        If ( $Items ) {
            If ( $Recurse ) {
                $Words | Get-Item -Force |% { Write-Verbose ( "[$Verb] CHECK: " + $_.FullName ) ; Get-Unbagged-ChildItem -LiteralPath $_.FullName } | Do-Clear-And-Bag -Skip:$SkipScan -Force:$Force -Bundle:$Bundle
            }
            Else {
                $Words | Get-Item -Force |% { Write-Verbose ( "[$Verb] CHECK: " + $_.FullName ) ; $_ } | Do-Clear-And-Bag -Skip:$SkipScan -Force:$Force -Bundle:$Bundle
            }
        }
        Else {
            Do-Bag -Pairs $Words -Skip:$SkipScan -Force:$Force
        }

    }
    ElseIf ( $Verb -eq "rebag" ) {
        $N = ( $Words.Count )
        If ( $Items ) {
            $Words | Get-Item -Force |% { Write-Verbose ( "[$Verb] CHECK: " + $_.FullName ) ; $_ } | Do-Clear-And-Bag -Rebag
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
        $N = ( $Words.Count )

        $Words |% {
            $sFile = Get-FileLiteralPath -File $_
            If ( Test-BagItFormattedDirectory -File $_ ) {
                $_ | Do-Zip-Bagged-Directory
            }
            ElseIf ( Test-LooseFile -File $_ ) {
                $oBag = ( Get-BaggedCopyOfLooseFile -File $_ )
                If ($oBag) {
                    $oBag | Do-Zip-Bagged-Directory
                }
                Else {
                    Write-Warning "${sFile} is a loose file not a BagIt-formatted directory."
                }
            }
            Else {
                $_ | Get-Item -Force |% { Get-BaggedChildItem -LiteralPath $_.FullName } | Do-Zip-Bagged-Directory
            }
        }
    }
    ElseIf ( ("index", "bundle") -ieq $Verb ) {
        $Words = ( $Words | ColdStorage-Command-Line -Default "${PWD}" )
        $Words | ForEach {
            Add-IndexHTML -Directory $_ -RelativeHref -Force:$Force
        }
    }
    ElseIf ( $Verb -eq "manifest" ) {

        $Words = ( $Words | ColdStorage-Command-Line -Default "${PWD}" )
        $Words | ForEach {
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
    ElseIf ( $Verb -eq "abort-cloud-uploads" ) {
        $Words | Do-CloudUploadsAbort        
    }
    ElseIf ( $Verb -eq "bucket" ) {
        $Words | Get-CloudStorageBucket
        If ( $Make ) {
            $Words | Get-CloudStorageBucket | New-CloudStorageBucket
        }

    }
    ElseIf ( $Verb -eq "to" ) {
        $Object, $Words = $Words
        $Words = ( $Words | ColdStorage-Command-Line -Default "${PWD}" )

        Invoke-ColdStorageTo -Destination:$Object -What:$Words -Items:$Items -Repository:$Repository -Diff:$Diff -Report:$Report -ReportOnly:$ReportOnly -WhatIf:$WhatIf
    }
    ElseIf ( ("in","vs") -ieq $Verb ) {
        $bUnmatched = ( $Verb -ieq "vs" )
        $Object, $Words = $Words
        $Destinations = ("cloud", "drop")

        If ( $Object -eq "cloud" ) {

            $aSide = ( $Side |% { $_ -split "," } )
            $aItems = $( If ( $Items ) { $Words } Else { ( Get-ZippedBagsContainer -Repository:$Words ) } )

            $aItems | Get-CloudStorageListing -Unmatched:$bUnmatched -Side:($aSide) -ReturnObject |% { If ( $FullName ) { $_.FullName } Else { $_.Name } }

        }
        Else {
            Write-Warning ( "[${Verb}:${Object}] Unknown destination. Try: ({0})" -f ( $Destinations -join ", " ) )
        }

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
        $Table = ( $Words | Get-RepositoryStats -Count:($Words.Count) -Verbose:$Verbose -Batch:$Batch )
        If ( "CSV" -ieq $Output ) {
            $Table | ConvertTo-CSV
        }
        ElseIf ( "JSON" -ieq $Output ) {
            $Table | ConvertTo-Json
        }
        Else {
            $Table | Write-Output
        }

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
    ElseIf ( $Verb -eq "settings" ) {
        Get-ColdStorageSettings -Name $Words
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

        $aItems | ForEach {
            $File = Get-FileObject -File $_
            @{ FILE=( $File.FullName ); REPOSITORY=($File | Get-FileRepositoryName) }
        }

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
        $sLocation, $Remainder = ( $Words )
        $PropsFileName = "props.json"
        If ( $Bucket ) {
            $sBucket, $Remainder = ( $Remainder )
            If ( $sBucket ) {
                $DefaultProps = @{ Bucket="${sBucket}" }
                $PropsFileName = "aws.json"
            }
            Else {
                Write-Warning "[$sCommandWithVerb] Where's the Bucket?"
            }
        }
        Else {
            $sDomain, $sRepository, $sPrefix, $Remainder = ( $Remainder )
            If ( $sDomain ) {
                $DefaultProps = @{ Domain="${sDomain}"; Repository="${sRepository}"; Prefix="${sPrefix}" }
            }
        }

        If ( $sLocation -eq "here" ) {
            $oFile = ( Get-Item -Force -LiteralPath $( Get-Location ) )
        }
        Else {
            $oFile = Get-FileObject($sLocation)
        }
        If ( $oFile -ne $null ) {
            $vProps = $Props            
            If ( $vProps -is [String] ) {
                If ( $vProps ) {
                    $vProps = ( $vProps | ConvertFrom-Json )
                }
            }
            If ( $vProps -ne $null ) {
                $vProps = ( $vProps | Get-TablesMerged )
            }
            If ( -Not ( $vProps -is [Hashtable] ) ) {
                $vProps = $DefaultProps
            }

            $vProps | New-ColdStorageRepositoryDirectoryProps -File $oFile -Force:$Force -FileName:$PropsFileName 
            If ( $Bucket ) {
                ( $oFile | Add-ZippedBagsContainer )
            }
        }
    }
    ElseIf ( $Verb -eq "bleep" ) {
        Do-Bleep-Bloop
    }
    ElseIf ( $Verb -eq "echo" ) {
        $aFlags = $MyInvocation.BoundParameters
        "Verb", "Words" |% { $aFlags.Remove($_) }

        $oEcho = @{ "FLAGS"=( $MyInvocation.BoundParameters ); "WORDS"=( $Words ); "VERB"=( $Verb ) }
        [PSCustomObject] $oEcho | Format-Table 'VERB', 'WORDS', 'FLAGS'
    }
    Else {
        Do-Write-Usage -cmd $MyInvocation.MyCommand
    }


    if ( $Batch -and ( -Not $Quiet ) ) {
        $tN = ( Get-Date )
        
        Invoke-BatchCommandEpilog -Start:$t0 -End:$tN
    }
}
