<#
.SYNOPSIS
ADAHColdStorage Digital Preservation maintenance and utility script with multiple subcommands.

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
    [switch] $NoScan = $false,
    [switch] $Force = $false,
    [switch] $FullName = $false,
    [switch] $Unbagged = $false,
    [switch] $Unzipped = $false,
    [switch] $Report = $false,
    [switch] $Bork = $false,
    [switch] $Dependencies = $false,
    [String] $Output = "-",
    [String[]] $Side = "local,cloud",
    #[switch] $Verbose = $false,
    #[switch] $Debug = $false,
    [switch] $WhatIf = $false,
    [Parameter(ValueFromRemainingArguments=$true, Position=1)] $Words
)
$RipeDays = 7

$Verbose = ( $PSCmdlet.MyInvocation.BoundParameters["Verbose"].IsPresent )
$Debug = ( $PSCmdlet.MyInvocation.BoundParameters["Debug"].IsPresent )

# coldstorage
#
# Last-Modified: 28 December 2020

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
Import-Module BitsTransfer
Import-Module Posh-SSH

# Internal Dependencies - Modules
Import-Module -Verbose:( $Debug -eq $true ) -Force $( ColdStorage-Script-Dir -File "ColdStorageSettings.psm1" )
Import-Module -Verbose:( $Debug -eq $true ) -Force $( ColdStorage-Script-Dir -File "ColdStorageFiles.psm1" )
Import-Module -Verbose:( $Debug -eq $true ) -Force $( ColdStorage-Script-Dir -File "ColdStorageRepositoryLocations.psm1" )
Import-Module -Verbose:( $Debug -eq $true ) -Force $( ColdStorage-Script-Dir -File "ColdStoragePackagingConventions.psm1" )
Import-Module -Verbose:( $Debug -eq $true ) -Force $( ColdStorage-Script-Dir -File "ColdStorageBagItDirectories.psm1" )
Import-Module -Verbose:( $Debug -eq $true ) -Force $( ColdStorage-Script-Dir -File "ColdStorageBaggedChildItems.psm1" )
Import-Module -Verbose:( $Debug -eq $true ) -Force $( ColdStorage-Script-Dir -File "ColdStorageStats.psm1" )
Import-Module -Verbose:( $Debug -eq $true ) -Force $( ColdStorage-Script-Dir -File "ColdStorageZipArchives.psm1" )
Import-Module -Verbose:( $Debug -eq $true ) -Force $( ColdStorage-Script-Dir -File "ColdStorageToCloudStorage.psm1" )

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
Param ( [Parameter(ValueFromPipeline=$true)] $ExitCode )

Begin { $result = $true }

Process {
    If ( $ExitCode -gt 0 ) {
        $ShouldWeContinue = Read-Host "Exit Code ${ExitCode}, Continue (Y/N)? "
    }
    Else {
        $ShouldWeContinue = "Y"
    }

    $result = ( $result -and ( $ShouldWeContinue -eq "Y" ) )
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

Function Compress-Archive-7z {
Param ( [switch] $WhatIf=$false, $LiteralPath, $DestinationPath )

    $ZipExe = Get-ExeFor7z
    $add = "a"
    $zip = "-tzip"
    $batch = "-y"

    ( & "${ZipExe}" "${add}" "${zip}" "${batch}" "${DestinationPath}" "${LiteralPath}" ) | Write-Host
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

    if ( Test-Path -LiteralPath "${Path}" ) {
        $UNC = ( Get-Item -Force -LiteralPath "${Path}" | Get-UNCPathResolved -ReturnObject )

        $indexHtmlPath = "${UNC}\index.html"

        if ( -Not ( Test-Path -LiteralPath "${indexHtmlPath}" ) ) {
            $listing = Get-ChildItem -Recurse -LiteralPath "${UNC}" | Get-UNCPathResolved -ReturnObject | Add-File-URI | Sort-Object -Property FullName | Select-URI-Link -RelativeTo $UNC -RelativeHref:${RelativeHref}

            $NL = [Environment]::NewLine

            $htmlUL = $listing | % -Begin { "<ul>" } -Process { '  <li>' + $_ + "</li>" } -End { "</ul>" }
            $htmlTitle = ( "Contents of: {0}" -f [System.Web.HttpUtility]::HtmlEncode($UNC) )

            $htmlOut = ( "<!DOCTYPE html>${NL}<html>${NL}<head>${NL}<title>{0}</title>${NL}</head>${NL}<body>${NL}<h1>{0}</h1>${NL}{1}${NL}</body>${NL}</html>${NL}" -f $htmlTitle, ( $htmlUL -Join "${NL}" ) )

            $htmlOut | Out-File -FilePath $indexHtmlPath -NoClobber:(-Not $Force) -Encoding utf8
        } else {
            Write-Error "index.html already exists in ${Directory}!"
        }
    }
}

#############################################################################################################
## ADPNet ###################################################################################################
#############################################################################################################

Function Get-ADPNetAUTitle {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Process {
    $oFile = Get-FileObject -File $File

    # Fully qualified file system path to the containing parent
    $sFilePath = $oFile.Parent.FullName
    
    # Fully qualified UNC path to the containing parent
    $oFileUNCPath = ( $sFilePath | Get-UNCPathResolved -ReturnObject )
    $sFileUNCPath = $oFileUNCPath.FullName

    # Slice off the root directory up to the node name of the repository container
    $oRepository = Get-FileObject -File ( $oFileUNCPath | Get-FileRepositoryLocation )
    $sRepository = $oRepository.FullName
    $sRepositoryNode = ( $oRepository.Parent.Name, $oRepository.Name ) -join "-"

    $reUNCRepo = [Regex]::Escape($sRepository)
    $sPathRelativeToRepo = ( $sFileUNCPath -ireplace "^${reUNCRepo}\\+","" )
    
    $RepositoryNodes = Get-ColdStorageSettings -Name "AU-Titles"

    $Title = $null
    If ( $RepositoryNodes.${sRepositoryNode} ) {
        $sFileName = $oFile.Name
        $Node = $RepositoryNodes.${sRepositoryNode}

        $Node.PSObject.Properties | ForEach {
            $Wildcard = ( $_.Name | ConvertTo-ColdStorageSettingsFilePath )
            $Props = $_.Value -split "//"
            Write-Host "CHECK: ", $Wildcard, $Props
            If ( ".\${sPathRelativeToRepo}\${sFileName}" -like $Wildcard ) {
                $Pattern = $Props[0]
                $Process = ( $Props[1] -split "/" )[0..1]

                $sSlug = $oFile.NAme -replace $Process
                $Title = $Pattern -f ( $sSlug )
            }

        }

    }
    
    If ( $Title ) {
        $Title | Write-Output
    }
}

}

Function Get-ADPNetStartDir {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    Get-ZippedBagNamePrefix -File $File | Write-Output
}

End { }

}

Function Get-ADPNetStartURL {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { $hrefPrefix = Get-ColdStorageSettings -Name "Drop-Server-URL" }

Process {
    $hrefPath = ( $File | Get-ADPNetStartDir )
    ( "{0}/{1}/" -f $hrefPrefix, $hrefPath ) | Write-Output
}

End { }

}

Function Get-LOCKSSManifestPath {
Param( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    $sFile = Get-FileLiteralPath -File $File
    "${sFile}\manifest.html" | Write-Output
}

End { }
}

Function Get-LOCKSSManifest {
Param( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    
    $sFile = Get-FileLiteralPath -File $File

    If ( Test-Path -LiteralPath $sFile ) {

        $manifest = ( $sFile | Get-LOCKSSManifestPath )
        Get-FileObject -File $manifest | Write-Output

    }

}

End { }
}

Function Add-LOCKSSManifestHTML {
Param( $Directory, [string] $Title, [switch] $Force=$false )

    if ( $Directory -eq $null ) {
        $Path = ( Get-Location )
    } else {
        $Path = ( $Directory )
    }

    $TitlePrefix = Get-ColdStorageSettings -Name "Institution"

    if ( Test-Path -LiteralPath "${Path}" ) {
        $UNC = ( Get-Item -Force -LiteralPath "${Path}" | Get-UNCPathResolved -ReturnObject )
        $oManifest = ( $UNC | Get-LOCKSSManifest )
        If ( ( $oManifest ) -and ( -Not $Force ) ) {
            Write-Error ( "[manifest:${Directory}] manifest.html already exists for this AU ({0} bytes, created {1})" -f $oManifest.Length, $oManifest.CreationTime )
        }
        Else {

            $NL = [Environment]::NewLine

            $htmlStartLink = ( '<a href="{0}">{1}</a>' -f $( $Path | Get-ADPNetStartURL ), $Title )
            
            $htmlLOCKSSBadge = '<img src="LOCKSS-small.gif" alt="LOCKSS" width="108" height="108" />'
            $htmlLOCKSSPermission = 'LOCKSS system has permission to collect, preserve, and serve this Archival Unit.'
            
            $htmlBody = ( (
                "<p>${htmlStartLink}</p>",
                "<p>${htmlLOCKSSBadge} ${htmlLOCKSSPermission}</p>",
                ""
            ) -Join "${NL}" )
            
            $htmlTitle = ( "{0}: {1}" -f $TitlePrefix, $Title )

            $htmlOut = (
                (
                    (
                "<!DOCTYPE html>",
                "<html>",
                "<head>",
                "<title>{0}</title>",
                "</head>",
                "<body>",
                "<h1>{0}</h1>",
                "{1}",
                "</body>",
                "</html>",
                ""
                    ) -join "${NL}"
                ) -f $htmlTitle, $htmlBody
            )

            $htmlOut | Out-File -FilePath ( $UNC | Get-LOCKSSManifestPath ) -NoClobber:(-Not $Force) -Encoding utf8
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

    [ScriptBlock]
    $OnConsider={ Param($File, $Candidate, $DiffLevel, $I); },

    [Parameter(ValueFromPipeline=$true)]
    $File
   )

   Begin {
    $iCounter = 0
   }

   Process {
        $iCounter = $iCounter + 1
        If ( -Not ( $File.Name -match $Exclude ) ) { 
            $Object = ($File | Rebase-File -To $Match)
            $OnConsider.Invoke($File, $Object, $DiffLevel, $iCounter)
            if ( -Not ( Is-Matched-File -From $File -To $Object -DiffLevel $DiffLevel ) ) {
                $File
            }
        }
   }

   End {
    $iCounter = $null
   }
}

function Get-Matched-Items {
    [CmdletBinding()]

   param (
    [String]
    $Match,

    [Int]
    $DiffLevel = 0,

    [Parameter(ValueFromPipeline=$true)]
    $File
   )

   Begin {}

   Process {
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
            ElseIf ( $oFile | Test-ColdStorageRepositoryPropsDirectory ) {
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

Function Add-ADPNetAUToDropServerStagingDirectory {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {

        $Location = ( Get-Item -LiteralPath $File )
            
        $sLocation = $Location.FullName

        If ( -Not ( $Location | Get-LOCKSSManifest ) ) {

            $sTitle = ( $Location | Get-ADPNetAUTitle )
            If ( -Not $sTitle ) {
                $sTitle = ( Read-Host -Prompt "AU Title [${Location}]" )
            }

            Add-LOCKSSManifestHTML -Directory $File -Title $sTitle -Force:$Force

        }

        ( $Location | Set-DropServerFolder )

    }

    End { }

}

Function Get-DropServerAuthority {

    $address = ( Get-ColdStorageSettings -Name "Drop-Server-SFTP" )
    
    ( $address -split "@",2 ) | Write-Output

}

Function Get-DropServerHost {

    ( Get-DropServerAuthority )[1]

}

Function Get-DropServerUser {

    ( Get-DropServerAuthority )[0]

}

Function Get-DropServerPassword {
Param ( [string] $SFTPHost )

    $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    $utf8 = New-Object -TypeName System.Text.UTF8Encoding
    $hash = [System.BitConverter]::ToString($md5.ComputeHash($utf8.GetBytes($SFTPHost)))

    $FileName = "${hash}.txt"
    $FilePath = ColdStorage-Script-Dir
    $Txt = "${FilePath}\${FileName}"

    If ( Test-Path -LiteralPath $Txt ) {
        ( Get-Content -LiteralPath $Txt ).Trim()
    }

}

Function New-DropServerSession {

    $User = Get-DropServerUser
    $PWord = ConvertTo-SecureString -String ( Get-DropServerPassword -SFTPHost ( Get-DropServerHost ) ) -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord

    New-SFTPSession -ComputerName ( Get-DropServerHost ) -Credential ( $Credential )
}

Function Set-DropServerFolder {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin {
    $session = ( New-DropServerSession )
}

Process {
    $oFile = ( Get-FileObject -File $File )
    $sFile = $oFile.FullName

    If ( $session ) {
        If ( Test-BagItFormattedDirectory -File $sFile ) {

            If ( $oFile | Get-LOCKSSManifest ) {

                $RemoteRoot = "/drop_au_content_in_here"
                Set-SFTPLocation -SessionId $session.SessionId -Path "${RemoteRoot}"

                $RemoteDestination = ( $oFile | Get-ADPNetStartDir )
                Get-SFTPChildItem -SessionId $session.SessionId -Path $RemoteRoot |% {

                    If ( $_.Name -ieq "${RemoteDestination}" ) {
                        $RemoteBase = $_
                    }
                }


                If ( Test-SFTPPath -SFTPSession:$session -Path:$RemoteDestination ) { # Already uploaded; sync.
                    Write-Verbose "[drop:$sFile] already exists; sync with local copy."
                    $oFile | Sync-DropServerAU -SFTPSession:$session -RemoteRepository:$RemoteRoot
                }
                Else {
                    Write-Verbose "[drop:$sFile] not yet staged; add local copy"
                    $oFile | Add-DropServerAU -SFTPSession:$session -RemoteRepository:$RemoteRoot
                }

            }
            Else {
                Write-Error "[drop:$sFile]: Requires LOCKSS manifest.html file. Use: & coldstorage manifest -Items '${sFile}'"
            }

        }
        Else {

            Write-Error "[drop:$sFile]: Requires bagit formatting. Use: & coldstorage bag -Items '${sFile}'"

        }
    }
    Else {

        Write-Error "[drop:$sFile]: SFTP connection failed."
        Write-Error $session

    }

}

End {
    If ( $session ) {
        $removed = ( Remove-SFTPSession -SessionId $session.SessionId )
    }
}

}

Function Add-DropServerAU {
    Param ( [Parameter(ValueFromPipeline=$true)] $LocalFolder, $SFTPSession, $RemoteRepository )

    Begin { }

    Process {
        $sLocalFullName = $LocalFolder.FullName
        $sRemotePath = ( $LocalFolder | Get-ADPNetStartDir )
        Set-SFTPFolder -SessionId:($SFTPSession.SessionId) -LocalFolder:$sLocalFullName -RemotePath:$sRemotePath
    }

    End { }

}

Function Sync-DropServerAU {
Param ( [Parameter(ValueFromPipeline=$true)] $LocalFolder, $SFTPSession, $RemoteRepository )

Begin { }

Process {
    $RemoteDestination = ( $LocalFolder | Get-ADPNetStartDir )
    Get-SFTPChildItem -SessionId:($SFTPSession.SessionId) -Path:$RemoteRepository |% {

        If ( $_.Name -ieq "${RemoteDestination}" ) {
            $RemoteBase = $_
        }

    }

    Get-SFTPChildItem -SessionId $session.SessionId -Recursive -Path $RemoteDestination |% {
        $RemoteFile = $_
        $LocalFile = ( $_ | Get-ADPNetFileLocalPath -Session:$session -LocalBase:$LocalFolder -RemoteBase:$RemoteBase )
        $RemoteAttr = Get-SFTPPathAttribute -SessionId $session.SessionId -Path $RemoteFile.FullName
            
        $LocalLength = $LocalFile.Length
        $RemoteLength = $RemoteAttr.Size
            
        $WrittenLater = ( $LocalFile.LastWriteTime -gt $RemoteAttr.LastWriteTime )
        $SizesDiffer = ( $LocalFile.Length -ne $RemoteAttr.Size )
        If ( $RemoteAttr.IsRegularFile ) {
            If ( $WrittenLater -or $SizesDiffer ) {
                $FileName = $LocalFile.Name
                Write-Warning "${FileName} differs. Local copy: ${LocalLength}; Remote: ${RemoteLength}"
                $RemotePath = ( $RemoteFile.FullName -split "/" )
                $RemoteParent = ( $RemotePath[0..($RemotePath.Count-2)] ) -join "/"
                Set-SFTPItem -SFTPSession:$session -Path:($LocalFile.FullName) -Destination:($RemoteParent) -Force -Verbose
            }
        }
    }

}

End { }
}

Function Get-ADPNetFileLocalPath {
Param ( [Parameter(ValueFromPipeline=$true)] $RemoteFile, $Session, $LocalBase, $RemoteBase )

Begin { }

Process {
    $reRemoteBase = [Regex]::Escape($RemoteBase.FullName)
    $remoteRelative = ( $RemoteFile.FullName -replace "^${reRemoteBase}/","" ) -replace "[/]","\"
    $LocalizedFileName = ( $LocalBase.FullName + "\${remoteRelative}" )
    If ( Test-Path -LiteralPath $LocalizedFileName ) {
        Get-Item -Force -LiteralPath $LocalizedFileName | Write-Output
    }
}

End { }
}

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

Function Do-Mirror-Clean-Up-Obsolete-Files {
Param ($From, $To, $Trashcan, [switch] $Batch=$false, $Depth=0, $ProgressId=0, $NewProgressId=0)

    $aDirs = Get-ChildItem -Directory -LiteralPath "$To"
    $N = $aDirs.Count
    $aDirs | Get-Unmatched-Items -Match "$From" -DiffLevel 0 -OnConsider {
        Param($File, $Candidate, $DiffLevel, $I);
        If ( -Not $Batch ) {
            Write-Progress -Id ($NewProgressId + 3) -Activity "Matching (rm): [${To}]" -Status $File.Name -percentComplete (100*$I/$N)
        }
    } | ForEach {

        $BaseName = $_.Name
        $MoveFrom = $_.FullName
        $MoveTo = ($_ | Rebase-File -To $Trashcan)

        If ( -Not ( $_ | Test-UnmirroredDerivedItem ) ) {
            "Move-Item -LiteralPath $MoveFrom -Destination $MoveTo -Force"
            If ( -Not ( Test-Path -LiteralPath $Trashcan ) ) {
                mkdir $Trashcan
            }
            Move-Item -LiteralPath $MoveFrom -Destination $MoveTo -Force
        }
        ElseIf ( $Verbose ) {
            Write-Warning "SKIPPED (UNMIRRORED DERIVED ITEM): [${MoveFrom}]"
        }
    }
    If ( -Not $Batch ) {
        Write-Progress -Id ($NewProgressId + 3) -Activity "Matching (rm): [${To}]" -Completed
    }

}

Function Do-Mirror-Directories {
Param ($From, $to, $Trashcan, $DiffLevel=1, [switch] $Batch=$false, $Depth=0, $ProgressId=0, $NewProgressId=0)
    $aDirs = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aDirs = Get-ChildItem -Directory -LiteralPath "$From"
    }

    $N = $aDirs.Count
    $aDirs | Get-Unmatched-Items -Match "${To}" -DiffLevel 0 -OnConsider {
        Param($File, $Candidate, $DiffLevel, $I);
        If ( -Not $Batch ) {
            $sFileName = $File.Name
            Write-Progress -Id ($NewProgressId + 3) -Activity "Matching (mkdir): [${From}]" -Status $sFileName -percentComplete (100*$I / $N)
        }
    } | ForEach {
        If ( -Not ( $_ | Test-UnmirroredDerivedItem -MirrorBaggedCopies ) ) {
            $CopyFrom = $_.FullName
            $CopyTo = ($_ | Rebase-File -To "${To}")

            Write-Output "${CopyFrom}\\ =>> ${CopyTo}\\"
            Copy-Item -LiteralPath "${CopyFrom}" -Destination "${CopyTo}"
        }
    }
    If ( -Not $Batch ) {
        Write-Progress -Id ($NewProgressId + 3) -Activity "Matching (mkdir): [${From}]" -Completed
    }
}

Function Do-Mirror-Files {
Param ($From, $To, $Trashcan, [switch] $Batch=$false, $DiffLevel=1, $Depth=0, $ProgressId=0, $NewProgressId=0)

    $i = 0
    $aFiles = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aFiles = ( Get-ChildItem -File -LiteralPath "$From" )
    }
    $N = $aFiles.Count

    $sProgressActivity = "Matching Files (cp) [${From} => ${To}]"
    $aFiles = ( $aFiles | Get-Unmatched-Items -Exclude "Thumbs[.]db" -Match "${To}" -DiffLevel $DiffLevel -OnConsider {
        Param($File, $Candidate, $DiffLevel, $I);
        If ( -Not $Batch ) {
            $sFileName = $File.Name
            Write-Progress -Id ($NewProgressId + 3) -Activity $sProgressActivity -Status $sFileName -percentComplete (100*$I / $N)
        }
    })
    $N = $aFiles.Count

    $sProgressActivity = "Copying Unmatched Files [${From} => ${To}]"
    $aFiles | ForEach {
        $BaseName = $_.Name
        $CopyFrom = $_.FullName
        $CopyTo = ($_ | Rebase-File -To "${To}")
        
        If ( -Not ( $_ | Test-UnmirroredDerivedItem -MirrorBaggedCopies ) ) {

            If ( -Not $Batch ) {
                Write-Progress -Id ($NewProgressId + 3) -Activity $sProgressActivity -Status "${BaseName}" -percentComplete (100*$i / $N)
            }
            Else {
                Write-Output "${CopyFrom} =>> ${CopyTo}"
            }
            $i = $i + 1

        
            Do-Copy-Snapshot-File "${CopyFrom}" "${CopyTo}" -Batch:$Batch
        }

    }
    If ( -Not $Batch ) {
        Write-Progress -Id ($NewProgressId + 3) -Activity $sProgressActivity -Completed
    }
}

Function Do-Mirror-Metadata {
Param( $From, $To, $ProgressId, $NewProgressId, [switch] $Batch=$false )

    $i = 0
    $aFiles = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aFiles = ( Get-ChildItem -LiteralPath "$From" | Get-Matched-Items -Match "${To}" -DiffLevel 0 )
    }
    $N = $aFiles.Count

    $aFiles | ForEach  {
        $CopyFrom = $_.FullName
        $CopyTo = ($_ | Rebase-File -To "${To}")

        If ( -Not $Batch ) {
            Write-Progress -Id ($NewProgressId + 1) -Activity "Synchronizing metadata [${From}]" -Status $_.Name -percentComplete (100*$i / $N)
        }
        $i = $i + 1

        Do-Reset-Metadata -from "${CopyFrom}" -to "${CopyTo}" -Verbose:$false
    }
    If ( -Not $Batch ) {
        Write-Progress -Id ($NewProgressId + 1) -Activity "Synchronizing metadata [${From}]" -Completed
    }
}

function Do-Mirror ($From, $To, $Trashcan, $DiffLevel=1, $Depth=0, [switch] $Batch=$false) {
    $IdBase = (10 * $Depth)
    If ($Depth -gt 0) {
        $RootedIdBase = 0
    }
    Else {
        $RootedIdBase = 0
    }

    $sActScanning = "Scanning contents: [${From}]"
    $sStatus = "*.*"

    $sTo = $To
    If (Test-BagItFormattedDirectory -File $To) {
        If ( -Not ( Test-BagItFormattedDirectory -File $From ) ) {
            $oPayload = ( Get-FileObject($To) | Select-BagItPayloadDirectory )
            $To = $oPayload.FullName
        }
    }

    ##################################################################################################################
    ### CLEAN UP (rm): Files on destination not (no longer) on source get tossed out. ################################
    ##################################################################################################################

    If ( -Not $Batch ) {
        Write-Progress -Id ($RootedIdBase + 2) -Activity $sActScanning -Status "${sStatus} (rm)" -percentComplete 0
    }
    Do-Mirror-Clean-Up-Obsolete-Files -From $From -To $To -Trashcan $Trashcan -Batch:$Batch -Depth $Depth -ProgressId $RootedIdBase -NewProgressId $IdBase

    ##################################################################################################################
    ## COPY OVER (mkdir): Create child directories on destination to mirror subdirectories of source. ################
    ##################################################################################################################

    If ( -Not $Batch ) {
        Write-Progress -Id ($RootedIdBase + 2) -Activity $sActScanning -Status "${sStatus} (mkdir)" -percentComplete 20
    }
    Do-Mirror-Directories -From $From -To $To -Trashcan $Trashcan -Batch:$Batch -DiffLevel $DiffLevel -Depth $Depth -ProgressId $RootedIdBase -NewProgressId $IdBase

    ##################################################################################################################
    ## COPY OVER (cp): Copy snapshot files onto destination to mirror files on source. ###############################
    ##################################################################################################################

    If ( -Not $Batch ) {
        Write-Progress -Id ($RootedIdBase + 2) -Activity $sActScanning -Status "${sStatus} (cp)" -percentComplete 40
    }
    Do-Mirror-Files -From $From -To $To -Trashcan $Trashcan -Batch:$Batch -DiffLevel $DiffLevel -Depth $Depth -ProgressId $RootedIdBase -NewProgressId $IdBase

    ##################################################################################################################
    ## METADATA: Synchronize source file system meta-data to destination #############################################
    ##################################################################################################################

    If ( -Not $Batch ) {
        Write-Progress -Id ($RootedIdBase + 2) -Activity $sActScanning -Status "${sStatus} (meta)" -percentComplete 60
    }
    Do-Mirror-Metadata -From $From -To $To -Batch:$Batch -ProgressId $RootedIdBase -NewProgressId $IdBase

    ##################################################################################################################
    ### RECURSION: Drop down into child directories and do the same mirroring down yonder. ###########################
    ##################################################################################################################

    If ( -Not $Batch ) {
        Write-Progress -Id ($RootedIdBase + 2) -Activity $sActScanning -Status "${sStatus} (chdir)" -percentComplete 80
    }

    $i = 0
    $aFiles = @( )
    If ( Test-Path -LiteralPath "$From" ) {
        $aFiles = ( Get-ChildItem -Directory -LiteralPath "$From" | Get-Matched-Items -Match "$To" -DiffLevel 0 )
    }
    $N = $aFiles.Count
    
    $aFiles | ForEach {
        $BaseName = $_.Name
        $MirrorFrom = $_.FullName
        $MirrorTo = ($_ | Rebase-File -To "${To}")
        $MirrorTrash = ($_ | Rebase-File -To "${Trashcan}")

        $i = $i + 1
        If ( -Not $Batch ) {
            Write-Progress -Id ($RootedIdBase + 2) -Activity "Recursing into subdirectories [${From}]" -Status "${BaseName}" -percentComplete (100*$i / $N)
        }
        Do-Mirror -From "${MirrorFrom}" -To "${MirrorTo}" -Trashcan "${MirrorTrash}" -DiffLevel $DiffLevel -Depth ($Depth + 1) -Batch:$Batch
    }
    If ( -Not $Batch ) {
        Write-Progress -Id ($RootedIdBase + 2) -Activity "Recursing into subdirectories [${From}]" -Completed
    }
}

function Do-Mirror-Repositories ($Pairs=$null, $DiffLevel=1, [switch] $Batch=$false) {

    $mirrors = ( Get-ColdStorageRepositories )

    $Pairs = ($Pairs | % { If ( $_.Length -gt 0 ) { $_ -split "," } })

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
            $src = (Get-Item -Force -LiteralPath $locations[2] | Get-LocalPathFromUNC ).FullName
            $dest = (Get-Item -Force -LiteralPath $locations[1] | Get-LocalPathFromUNC ).FullName
            $TrashcanLocation = ( $Pair | Get-ColdStorageTrashLocation )

            if ( -Not ( Test-Path -LiteralPath "${TrashcanLocation}" ) ) { 
                mkdir "${TrashcanLocation}"
            }

            Write-Progress -Id 1138 -Activity "Mirroring between ADAHFS servers and ColdStorage" -Status "Location: ${Pair}" -percentComplete ( 100 * $i / $N )
            Do-Mirror -From "${src}" -To "${dest}" -Trashcan "${TrashcanLocation}" -DiffLevel $DiffLevel -Batch:$Batch
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
        $i = $i + 1
    }
    Write-Progress -Id 1138 -Activity "Mirroring between ADAHFS servers and ColdStorage" -Completed
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
            Write-Unbagged-Item-Notice -FileName $File.Name -Message "indexed directory. Scan it, bag it and tag it." -Verbose -Line ( Get-CurrentLine )

            If ( $File.FullName | Do-Scan-ERInstance | Shall-We-Continue ) {
                Do-Bag-Directory -DIRNAME $File.FullName
            }
        }
        Else {
            Get-ChildItem -File -LiteralPath $File.FullName | ForEach {
                If ( Test-UnbaggedLooseFile($_) ) {
                    $LooseFile = $_.Name
                    Write-Unbagged-Item-Notice -FileName $File.Name -Message "loose file. Scan it, bag it and tag it." -Verbose -Line ( Get-CurrentLine )

                    if ( $_.FullName | Do-Scan-ERInstance | Shall-We-Continue ) {
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

        If ( -Not $Batch ) {
            Write-Progress -Id 201 -Activity ( "Checking {0}" -f ( $File.CheckedSpace ) ) -Status ( "Check FILE: {0}  ... {1}" -f ( $File.Directory ),$File.Name ) -PercentComplete 10
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

        If ( -Not $Batch ) {
            Write-Progress -Id 201 -Activity ( "Checking {0}" -f ( $File.CheckedSpace ) ) -Status ( "Check DIR: {0} ... {0}" -f ( $File.Parent, $BaseName ) ) -PercentComplete 60
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
            
            dir -File | Add-Member -NotePropertyName "CheckedSpace" -NotePropertyValue ( $File.CheckedSpace ) -PassThru | Do-Scan-File-For-Bags -Quiet:$Quiet
            dir -Directory | Select-Unbagged-Dirs | Add-Member -NotePropertyName "CheckedSpace" -NotePropertyValue ( $File.CheckedSpace ) -PassThru | Do-Scan-Dir-For-Bags -Quiet:$Quiet

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

function Do-Bag-Repo-Dirs ($Pair, $From, $To) {
    $Anchor = $PWD 

    chdir $From
    dir -Attributes Directory | Do-Clear-And-Bag -Quiet -Exclude $null
    chdir $Anchor
}

function Do-Bag ($Pairs=$null) {
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

        Do-Bag-Repo-Dirs -Pair "${Pair}" -From "${src}" -To "${dest}"
        $i = $i + 1
    }
}

function Invoke-ColdStorageDirectoryCheck {
Param ($Pair, $From, $To, [switch] $Batch=$false)

    $Anchor = $PWD

    chdir $From

    If ( -Not $Batch ) {
        Write-Progress -Id 201 -Status ( "Checking {0}" -f $From ) -Activity "Files" -PercentComplete 1
    }

    dir -File | Add-Member -NotePropertyName "CheckedSpace" -NotePropertyValue $From -PassThru | Do-Scan-File-For-Bags -Quiet:$Quiet

    If ( -Not $Batch ) {
        Write-Progress -Id 201 -Status ( "Checking {0}" -f $From ) -Activity "Directories" -PercentComplete 51
    }

    dir -Directory | Add-Member -NotePropertyName "CheckedSpace" -NotePropertyValue $From -PassThru | Do-Scan-Dir-For-Bags -Quiet:$Quiet -Exclude $null

    If ( -Not $Batch ) {
        Write-Progress -Id 201 -Status ( "Checking {0}" -f $From ) -Activity "Completed." -Completed
    }

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

Function Do-Validate ($Pairs=$null, [switch] $Verbose=$false, [switch] $Zipped=$false) {
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
            $MapLines | % {
                $nGlanced = $nGlanced + 1
                $BagPathLeaf = (Split-Path -Leaf $_)
                Write-Progress -Id 101 -Activity "Validating ${nTotal} BagIt directories in ${Pair}" -Status ("#${nGlanced}. Considering: ${BagPathLeaf}") -percentComplete (100*$nGlanced/$nTotal)

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
                        Write-Progress -Id 101 -Activity "Validating ${nTotal} BagIt directories in ${Pair}" -Status ("#${nGlanced}. Validating: ${BagPathLeaf}") -percentComplete (100*$nGlanced/$nTotal)
                        $Validated = ( $BagPath | Do-Validate-Item -Verbose:$Verbose -Summary:$false )
                        
                        $nChecked = $nChecked + 1
                        $nValidated = $nValidated + $Validated.Count

                        $Validated # > stdout
                    }

                }
            }
            Write-Progress -Id 101 -Activity "Validating ${nTotal} BagIt directories in ${Pair}" -Completed

            "${nValidated}/${nChecked} BagIt packages validated OK." # > stdout

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
Param( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    
    If ( Test-BagItFormattedDirectory -File $File ) {
        $oFile = Get-FileObject -File $File
        $sFile = Get-FileLiteralPath -File $File

        $Validated = ( Do-Validate-Bag -DIRNAME $sFile )
        
        $Validated
        If ( $Validated | Did-It-Have-Validation-Errors | Shall-We-Continue ) {

            $oZip = ( Get-ZippedBagOfUnzippedBag -File $oFile )

            If ( $oZip.Count -gt 0 ) {
                $sArchiveHashed = $oZip.FullName
                "ZIP: ${sArchiveHashed}"
            }
            Else {
                $oRepository = ( $oFile | Get-ZippedBagsContainer )
                $sRepository = $oRepository.FullName

                $ts = $( Date -UFormat "%Y%m%d%H%M%S" )
                $sZipPrefix = ( Get-ZippedBagNamePrefix -File $oFile )

                $sZipName = "${sZipPrefix}_z${ts}"
                $sArchive = "${sRepository}\${sZipName}.zip"

                Write-Progress -Id 101 -Activity "Processing ${sArchiveFile}" -Status "Compressing archive" -PercentComplete 25
                Compress-Archive-7z -WhatIf:$WhatIf -LiteralPath ${sFile} -DestinationPath ${sArchive}

                Write-Progress -Id 101 -Activity "Processing ${sArchiveFile}" -Status "Computing MD5 checksum" -PercentComplete 50
                If ( -Not $WhatIf ) {
                    $md5 = $( Get-FileHash -LiteralPath "${sArchive}" -Algorithm MD5 ).Hash.ToLower()
                }
                else {
                    $stream = [System.IO.MemoryStream]::new()
                    $writer = [System.IO.StreamWriter]::new($stream)
                    $writer.write($sArchive)
                    $writer.Flush()
                    $stream.Position = 0
                    $md5 = $( Get-FileHash -InputStream $stream ).Hash.ToLower()
                }
                Write-Progress -Id 101 -Activity "Processing ${sArchiveFile}" -Status "Computing MD5 checksum" -PercentComplete 100 -Complete

                $sZipHashedName = "${sZipName}_md5_${md5}"
                $sArchiveHashed = "${sRepository}\${sZipHashedName}.zip"

                If ( -Not $WhatIf ) {
                    Move-Item -WhatIf:$WhatIf -LiteralPath $sArchive -Destination $sArchiveHashed
                }

                "ZIP: ${sFile} -> ${sArchiveHashed}"
            }

            Test-ZippedBagIntegrity -File $sArchiveHashed
        }
    }
    Else {
        $sFile = $File.FullName
        Write-Warning "${sFile} is not a BagIt-formatted directory."
    }

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
} else {
    $t0 = date
    $sCommandWithVerb = "${sCommandWithVerb} ${Verb}"
    
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
                    $RepositorySlug = ( Get-FileRepositoryName -File $sRepository )
                    $TrashcanLocation = ( $RepositorySlug | Get-ColdStorageTrashLocation )

                    $Src = ( $File | Get-Mirror-Matched-Item -Pair $RepositorySlug -Original )
                    $Dest = ( $File | Get-Mirror-Matched-Item -Pair $RepositorySlug -Reflection )

                    Write-Debug ( "REPOSITORY: {0}" -f $sRepository )
                    Write-Debug ( "SLUG: {0}" -f $RepositorySlug )
                    Write-Verbose ( "FROM: {0}; TO: {1}" -f $Src, $Dest )
                    Write-Debug ( "TRASHCAN: {0}" -f $TrashcanLocation )
                    Write-Verbose ( "DIFF LEVEL: {0}" -f $DiffLevel )

                    if ( -Not ( Test-Path -LiteralPath "${TrashcanLocation}" ) ) { 
                        mkdir "${TrashcanLocation}"
                    }

                    Do-Mirror -From "${Src}" -To "${Dest}" -Trashcan "${TrashcanLocation}" -DiffLevel $DiffLevel -Batch:$Batch

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

        Invoke-ColdStorageRepositoryCheck -Pairs $Words
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

        If ( $Items ) {
            If ( $Recurse ) {
                $Words | Get-Item -Force |% { Write-Verbose ( "CHECK: " + $_.FullName ) ; Get-Unbagged-ChildItem -LiteralPath $_.FullName } | Do-Clear-And-Bag 
            }
            Else {
                $Words | Get-Item -Force |% { Write-Verbose ( "CHECK: " + $_.FullName ) ; $_ } | Do-Clear-And-Bag 
            }
        }
        Else {
            Do-Bag -Pairs $Words
        }
    }
    ElseIf ( $Verb -eq "rebag" ) {
        $N = ( $Words.Count )
        If ( $Items ) {
            $Words | Get-Item -Force |% { Write-Verbose ( "CHECK: " + $_.FullName ) ; $_ } | Do-Clear-And-Bag -Rebag
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
    ElseIf ( $Verb -eq "index" ) {
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
    }
    ElseIf ( $Verb -eq "to" ) {
        $Object, $Words = $Words
        $Destinations = ("cloud", "drop")

        $Words = ( $Words | ColdStorage-Command-Line -Default "${PWD}" )
        If ( -Not $Items ) {
            Write-Warning ( "[${Verb}:${Object}] Not yet implemented for repositories. Try: & coldstorage to ${Object} -Items [File1] [File2] [...]" )
        }
        ElseIf ( $Object -eq "cloud" ) {
            If ( $Diff ) {
                $Anchor = $PWD
                $Candidates = ( $Words | Get-Item -Force | Get-CloudStorageListing -Unmatched:$true -Side:("local") -ReturnObject )
                $Candidates | Write-Verbose
                $Candidates | Add-PackageToCloudStorageBucket -WhatIf:${WhatIf}
            }
            Else {
                $Words | Add-PackageToCloudStorageBucket
            }
        }
        ElseIf ( $Object -eq "drop" ) {
            $Words | Add-ADPNetAUToDropServerStagingDirectory
        }
        Else {
            Write-Warning ( "[${Verb}:${Object}] Unknown destination. Try: ({0})" -f ( $Destinations -join ", " ) )
        }
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

        If ( $Items ) {
            $Words | Get-ChildItemPackages -Recurse:$Recurse -ShowWarnings:$Verbose -CheckZipped:$Unzipped |% {
                If ( -Not ( $Unbagged -and ( $_.CSPackageBagged ) ) ) {
                    If ( -Not ( $Unzipped -and ( $_.CSPackageZip ) ) ) {
                        $_
                    }
                }
            } |% {
                $sFullName = $_.FullName
                $sRelName = ( $_.FullName | Resolve-Path -Relative )
                If ( $FullName ) { $sTheName = $sFullName } Else { $sTheName = $sRelName }

                If ( $Report ) {
                    $sBagged = " (unbagged)"
                    If ( $_.CSPackageBagged ) {
                        $sBagged = " (BAGGED)"
                    }
                    $sZipped = ""
                    If ( $_ | Get-Member -MemberType NoteProperty -Name CSPackageZip ) {
                        $sZipped = " (unzipped)"
                        If ( $_.CSPackageZip.Count -gt 0 ) {
                            $sZipped = " (ZIPPED)"
                        }
                    }
                    $nContents = ( "{0:N0}" -f $_.CSPackageContents )
                    $sFileSize = ( "{0}" -f ( $_.CSPackageFileSize | Format-BytesHumanReadable ) )
                    ( "${sTheName}{0}{1}, {2} file{3}, {4}" -f $sBagged,$sZipped,$nContents,$( If ( $nContents -ne 1 ) { "s" } Else { "" } ),$sFileSize )
                    #$_.CSPackageContents | Write-Verbose
                }
                ElseIf ( $FullName ) {
                    $_.FullName
                }
                Else {
                    $_
                } }
        }
        Else {
            ( $Words |% { Get-ColdStorageLocation -Repository $_ } ) | Get-ChildItemPackages -Recurse:$Recurse -ShowWarnings:$Verbose |% { If ( $FullName ) { $_.FullName } Else { $_ } }
        }
        
    }
    ElseIf ( $Verb -eq "settings" ) {
        Get-ColdStorageSettings -Name $Words
    }
    ElseIf ( $Verb -eq "test" ) {
        
        If ( $Dependencies ) {
            Invoke-TestDependencies -Bork:${Bork} | Format-Table
        }

    }
    ElseIf ( $Verb -eq "repository" ) {
        $Words | ColdStorage-Command-Line -Default "${PWD}" | ForEach {
            $File = Get-FileObject -File $_
            @{ FILE=( $File.FullName ); REPOSITORY=($File | Get-FileRepositoryName) }
        }
    }
    ElseIf ( $Verb -eq "zipname" ) {
        $Words | ColdStorage-Command-Line -Default "${PWD}" | ForEach {
            $File = Get-FileObject -File $_
            "FILE:", $File.FullName, "PREFIX:", ($File | Get-ZippedBagNamePrefix )
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
            default { Write-Warning "[coldstorage $Verb] Unknown object: $Object" }
        }

    }
    ElseIf ( $Verb -eq "settle" ) {
        $sLocation, $sDomain, $sRepository, $sPrefix, $Remainder = ( $Words )
        If ( $sLocation -eq "here" ) {
            $oFile = ( Get-Item -Force -LiteralPath $( Get-Location ) )
        }
        Else {
            $oFile = Get-FileObject($sLocation)
        }
        If ( $oFile -ne $null ) {
            @{ Domain="${sDomain}"; Repository="${sRepository}"; Prefix="${sPrefix}" } | New-ColdStorageRepositoryDirectoryProps -File $oFile -Force:$Force
        }
    }
    ElseIf ( $Verb -eq "bleep" ) {
        Do-Bleep-Bloop
    }
    ElseIf ( $Verb -eq "echo" ) {
        "VERB:", $Verb
        "WORDS:", $Words
    }
    Else {
        Do-Write-Usage -cmd $MyInvocation.MyCommand
    }


    if ( $Batch -and ( -Not $Quiet ) ) {
        $tN = ( Get-Date )
        
        Invoke-BatchCommandEpilog -Start:$t0 -End:$tN
    }
}
