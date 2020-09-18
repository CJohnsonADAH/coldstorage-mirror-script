<#
.Description
coldstorage.ps1 mirror: Sync files to or from the ColdStorage server.
coldstorage.ps1 validate: Validate BagIt-formatted preservation packages
#>
param (
    [switch] $Help = $false,
    [switch] $Quiet = $false,
    [switch] $Diff = $false,
	[switch] $Batch = $false
)

# coldstorage
#
# Last-Modified: 4 September 2020

Import-Module BitsTransfer

$ColdStorageER = "\\ADAHColdStorage\ADAHDATA\ElectronicRecords"
$ColdStorageDA = "\\ADAHColdStorage\ADAHDATA\Digitization"
$ColdStorageBackup = "\\ADAHColdStorage\Share\ColdStorageMirroredBackup"

$mirrors = @{
    Processed=( "ER", "\\ADAHFS3\Data\Permanent", "${ColdStorageER}\Processed" )
    Working_ER=( "ER", "${ColdStorageER}\Working-Mirror", "\\ADAHFS3\Data\ArchivesDiv\PermanentWorking" )
    Unprocessed=( "ER", "\\ADAHFS1\PermanentBackup\Unprocessed", "${ColdStorageER}\Unprocessed" )
    Masters=( "DA", "${ColdStorageDA}\Masters", "\\ADAHFS3\Data\DigitalMasters" )
    Access=( "DA", "${ColdStorageDA}\Access", "\\ADAHFS3\Data\DigitalAccess" )
    Working_DA=( "DA", "${ColdStorageDA}\Working-Mirror", "\\ADAHFS3\Data\DigitalWorking" )
}

# Bleep Bleep Bleep Bleep Bleep Bleep -- BLOOP!
function Do-Bleep-Bloop () {
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

Function Get-File-Object ( $File ) {
    
    $oFile = $null
    If ( $File -is [String] ) {
        If ( Test-Path -LiteralPath "${File}" ) {
            $oFile = ( Get-Item -Force -LiteralPath "${File}" )
        }
    }
    Else {
        $oFile = $File
    }

    return $oFile
}

Function Get-File-Literal-Path {
Param($File)

	$sFile = $null

	If ( $File -eq $null ) {
		$oFile = $null
	}
	ElseIf ( -Not ( Get-Member -InputObject $File -name "FullName" -MemberType Properties ) ) {
		$oFile = Get-File-Object($File)
	}
	Else {
		$oFile = $File
	}

	If ( Get-Member -InputObject $oFile -name "FullName" -MemberType Properties ) {
		$sFile = $oFile.FullName
	}
	
	return $sFile
}

#############################################################################################################
## SETTINGS: PATHS, ETC. ####################################################################################
#############################################################################################################

Function ColdStorage-Script-Dir () {
    $ScriptPath = ( Split-Path -Parent $PSCommandPath )
    return (Get-Item -Force -LiteralPath $ScriptPath)
}

Function ColdStorage-Settings-File () {
    $JsonDir = ( ColdStorage-Script-Dir ).FullName

    $paths = "${JsonDir}\settings-${env:COMPUTERNAME}.json", "${JsonDir}\settings.json"
    
    $File = $null
    $paths | % {
        If ( $File -eq $null ) {
            If ( Test-Path -LiteralPath $_ ) {
                $File = (Get-Item -Force -LiteralPath $_)
            }
        }
    }

    return $File
}

Function ColdStorage-Settings-Defaults {
    $Out=@{
        BagIt="${HOME}\bin\bagit"
        ClamAV="${HOME}\bin\clamav"
    }
    $Out
}

Function ColdStorage-Settings-Json {
    ColdStorage-Settings-File | % {
        If ( $_ -eq $null ) {
            ColdStorage-Settings-Defaults | ConvertTo-Json
        } Else {
            Get-Content -Raw $_
        }
    }
}

Function ColdStorage-Settings-ToFilePath {
Param ( [Parameter(ValueFromPipeline=$true)] $Path )

Begin { }

Process {
    ( ( $Path -replace "[/]",'\' ) -replace '^~[\\]',"${HOME}\" )
}

End { }
}

Function Get-Json-Settings {
Param([String] $Name="", [Parameter(ValueFromPipeline=$true)] $Json)

Begin { }

Process {
    $Hashtable = ( $Json | ConvertFrom-Json )
    If ( $Name.Length -gt 0 ) {
        ( $Hashtable )."${Name}"
    }
    Else {
        $Hashtable
    }
}

End { }

}

Function ColdStorage-Settings {
Param([String] $Name="")

Begin { }

Process {
    ColdStorage-Settings-Json | Get-Json-Settings -Name $Name
}

End { }
}


function Get-ClamAV-Path () {
    return ( ColdStorage-Settings("ClamAV") | ColdStorage-Settings-ToFilePath )
}

function Get-BagIt-Path () {
    return ( ColdStorage-Settings("BagIt") | ColdStorage-Settings-ToFilePath )
}

#############################################################################################################
## BagIt DIRECTORIES ########################################################################################
#############################################################################################################

function Is-BagIt-Formatted-Directory ( $File ) {
    $result = $false # innocent until proven guilty

    $oFile = Get-File-Object -File $File   

    $BagDir = $oFile.FullName
    if ( Test-Path -LiteralPath $BagDir -PathType Container ) {
        $PayloadDir = "${BagDir}\data"
        if ( Test-Path -LiteralPath $PayloadDir -PathType Container ) {
            $BagItTxt = "${BagDir}\bagit.txt"
            if ( Test-Path -LiteralPath $BagItTxt -PathType Leaf ) {
                $result = $true
            }
        }
    }

    return $result
}

function Select-BagIt-Formatted-Directories () {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process { if ( Is-BagIt-Formatted-Directory($File) ) { $File } }

End { }
}

function Select-BagIt-Payload () {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    if ( Is-BagIt-Formatted-Directory($File) ) {
        $oFile = Get-File-Object($File)
        $payloadPath = $oFile.FullName + "\data"
        Get-ChildItem -Force -Recurse -LiteralPath "${payloadPath}"
    }
}

End { }

}

#############################################################################################################
## BagIt PACKAGING CONVENTIONS ##############################################################################
#############################################################################################################

function Is-Loose-File ( $File ) {
    
    $oFile = Get-File-Object($File)

    $result = $false
    If ( -Not ( $oFile -eq $null ) ) {
        if ( Test-Path -LiteralPath $oFile.FullName -PathType Leaf ) {
            $result = $true

            $Context = $oFile.Directory
            $sContext = $Context.FullName

            If ( Is-Indexed-Directory($sContext) ) {
                $result = $false
            }
            ElseIf  ( Is-Bagged-Indexed-Directory($sContext) ) {
                $result = $false
            }
            ElseIf ( Is-ER-Instance-Directory($Context) ) {
                $result = $false
            }
        }
    }
    return $result
}

function Is-Bagged-Copy-of-Loose-File ( $File, $Context ) {
    $result = $false # innocent until proven guilty

    if ( Is-BagIt-Formatted-Directory( $File ) ) {
        $BagDir = $File.FullName
        $payload = ( Get-ChildItem -Force -LiteralPath "${BagDir}\data" | Measure-Object )

        if ($payload.Count -eq 1) {
            $result = $true
        }
    }
    return $result
}

function Select-Bagged-Copies-of-Loose-Files {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process { if ( Is-Bagged-Copy-of-Loose-File($File) ) { $File } }

End { }
}

function Match-Bagged-Copy-to-Loose-File {
Param ( [Parameter(ValueFromPipeline=$true)] $Bag, $File, $DiffLevel=0 )

Begin { }

Process {
    If ( Is-Loose-File($File) ) {
        $oBag = Get-File-Object -File $Bag
        $Payload = ( Get-Item -Force -LiteralPath $oBag.FullName | Select-BagIt-Payload )
        If ( Is-Bagged-Copy-of-Loose-File($Bag) ) {
            If ( $Payload.Count -eq 1 ) {
                $oFile = Get-File-Object -File $File
                
                $Mismatched = $false
                If ( $Payload.Name -ne $oFile.Name ) {
                    $Mismatched = $true
                }
                ElseIf ( $Payload.Length -ne $oFile.Length ) {
                    $Mismatched = $true
                }
                ElseIf ( $DiffLevel -gt 0 ) {
                    If ( Is-Different-File-Content -From $Payload -To $File -DiffLevel $DiffLevel ) {
                        $Mismatched = $true
                    }
                }

                if ( -Not $Mismatched ) {
                    $Bag
                }
            }
        }
    }
}

End { }
}

function Get-Bagged-Copy-of-Loose-File ( $File ) {
    $result = $null

    If ( Is-Loose-File($File) ) {
        $oFile = Get-File-Object($File)
        $Parent = $oFile.Directory

        $match = ( Get-ChildItem -Directory $Parent | Select-Bagged-Copies-of-Loose-Files | Match-Bagged-Copy-to-Loose-File -File $oFile )

        if ( $match.Count -gt 0 ) {
            $result = $match
        }
    }

    return $result
}

function Is-Unbagged-Loose-File ( $File ) {

    $oFile = Get-File-Object($File)
    
    $result = $false
    If ( -Not ( $oFile -eq $null ) ) {
        If ( Is-Loose-File($File) ) {
            $result = $true
            $bag = Get-Bagged-Copy-of-Loose-File -File $oFile
                       
            if ( $bag.Count -gt 0 ) {
                $result = $false
            }
        }
    }
    return $result
}


function Do-Bag-Loose-File ($LiteralPath) {
    $Anchor = $PWD

    $Item = Get-Item -Force -LiteralPath $LiteralPath
    
    chdir $Item.DirectoryName
    $OriginalFileName = $Item.Name
    $OriginalFullName = $Item.FullName
    $FileName = ( $Item | Bagged-File-Path )

    $BagDir = ".\${FileName}"
    if ( -Not ( Test-Path -LiteralPath $BagDir ) ) {
        $BagDir = mkdir -Path $BagDir
    }

    Move-Item -LiteralPath $Item -Destination $BagDir
    Do-Bag-ERInstance -DIRNAME $BagDir
    if ( $LastExitCode -eq 0 ) {
        $NewFilePath = "${BagDir}\data\${OriginalFileName}"
        if ( Test-Path -LiteralPath "${NewFilePath}" ) {
            New-Item -ItemType HardLink -Path $OriginalFullName -Target $NewFilePath
	        
            Set-ItemProperty -LiteralPath $OriginalFullName -Name IsReadOnly -Value $true
            Set-ItemProperty -LiteralPath $NewFilePath -Name IsReadOnly -Value $true
        }
    }
    chdir $Anchor
}

#############################################################################################################
## ER INSTANCE DIRECTORIES: Typically found in ER Unprocessed directory #####################################
#############################################################################################################

function Is-ER-Instance-Directory ( $File ) {
    $result = $false # innocent until proven guilty
    if ( Test-Path -LiteralPath $File.FullName -PathType Container ) {
        $BaseName = $File.Name
        $result = ($BaseName -match "^[A-Za-z0-9]{2,3}_ER")
    }
    return $result
}

function Select-ER-Instance-Directories () {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process { if ( Is-ER-Instance-Directory($File) ) { $File } }

End { }
}

function Select-ER-Instance-Data () {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    $BaseName = $File.Name
    
    $DirParts = $BaseName.Split("_")

    $ERMeta = @{
        CURNAME=( $DirParts[0] )
        ERType=( $DirParts[1] )
        ERCreator=( $DirParts[2] )
        ERCreatorInstance=( $DirParts[3] )
        Slug=( $DirParts[4] )
    }
    $ERMeta.ERCode = ( "{0}-{1}-{2}" -f $ERMeta.ERType, $ERMeta.ERCreator, $ERMeta.ERCreatorInstance )

    return $ERMeta
}

End { }
}

function Do-Bag-ERInstance ($DIRNAME) {

    $Anchor = $PWD
    chdir $DIRNAME

    Write-Output ""
    Write-Output "BagIt: ${PWD}"
    $BagIt = Get-BagIt-Path
    ( python.exe "${BagIt}\bagit.py" . 2>&1 ) | Write-Output

    chdir $Anchor
}


#############################################################################################################
## index.html FOR BOUND SUBDIRECTORIES ######################################################################
#############################################################################################################

Add-Type -Assembly System.Web

function Resolve-UNC-Path {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $ReturnObject=$false )

Begin {}

Process {
    $output = $null

    $FileObject = Get-File-Object($File)

    $Drive = $null
    $Root = $null

    If ( Get-Member -InputObject $FileObject -Name "Root" -MemberType Properties ) {
        $Root = $FileObject.Root
    } ElseIf ( Get-Member -InputObject $FileObject -Name "Directory" -MemberType Properties ) {
        $Parent = $FileObject.Directory
        $Root = $Parent.Root
    }

    If ( -Not ( $Root -eq $null ) ) {
        Try {
            $Drive = New-Object System.IO.DriveInfo($Root)
            $Drive.DriveType | Out-Null
        } Catch {
            $Drive = $null
        }

        If ($Drive -eq $null) {
            $output = $FileObject.FullName
        }
        ElseIf ($Drive.DriveType -eq "Fixed") {
            $output = $FileObject.FullName
        }
        Else {
            $RootPath = $Parent
            $currentDrive = Split-Path -Qualifier $Root.FullName
            $logicalDisk = Gwmi Win32_LogicalDisk -filter "DriveType = 4 AND DeviceID = '${currentDrive}'"
            $ProviderName = $logicalDisk.ProviderName
            $unc = $FileObject.FullName.Replace($currentDrive, $ProviderName)
            $output = $unc
        }

        if ($ReturnObject) {
            $output = (Get-Item -Force -LiteralPath $output)
        }
        $output
    }
}

End {}

}

function Resolve-UNC-Path-To-Local-If-Local {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin {
    $sHost = $env:COMPUTERNAME
    $aShares = ( Get-WMIObject -ComputerName "${sHost}" -Query "SELECT * FROM Win32_Share" )

    $sShareLocalPath = $null
    $sLocalFullName = $null
}

Process {
    $Output = $File

    If ( $File.PSDrive ) {
        # This is on a local drive, we're all good
    }
    ElseIf ( $File.Root ) {
        $UNCRoot = $File.Root.FullName
        $sShareLocalPath = $null
        $sLocalFullName = $null

        $aShares | ForEach {
            $sSharePath = $_.Name
            If ( $UNCRoot -eq "\\${sHost}\${sSharePath}" ) {
                $sShareLocalPath = $_.Path
            }
        }
        If ( $sShareLocalPath -ne $null ) {
            $reUNCRoot = [Regex]::Escape($UNCRoot)
            $replaceLocalPath = ($sShareLocalPath -replace [Regex]::Escape("$"), "\$&")
            $sLocalFullName = $File.FullName -ireplace "^${reUNCRoot}","${replaceLocalPath}"
        }

        If ( $sLocalFullName -ne $null ) {
            If ( Test-Path -LiteralPath $sLocalFullName ) {
                $Output = ( Get-Item -Force -LiteralPath $sLocalFullName )
            }
        }
        
    }

    If ( $Output ) {
        $Output
    }
    Else {
        $File
    }

}

End { }

}

function Select-URI-Link {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $RelativeTo )

    Begin { Push-Location; Set-Location $RelativeTo }

    Process {
        $URL = $File.FileURI

        $HREF = [System.Web.HttpUtility]::HtmlEncode($URL)

        $FileName = ($File | Resolve-Path -Relative)

        $TEXT = [System.Web.HttpUtility]::HtmlEncode($FileName)

        '<a href="{0}">{1}</a>' -f $HREF, $TEXT
    }

    End { Pop-Location }

}

function Add-File-URI {
Param( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $UNC = $File.FullName
        $Nodes = $UNC.Split("\") | % { [URI]::EscapeDataString($_) }

        $URL = ( $Nodes -Join "/" )
        $protocolLocalAuthority = "file:///"
        
        $File | Add-Member -NotePropertyName "FileURI" -NotePropertyValue "${protocolLocalAuthority}$URL"
        $File
    }

    End { }

}

function Do-Make-Index-Html {
Param( $Directory )

    if ( $Directory -eq $null ) {
        $Path = ( Get-Location )
    } else {
        $Path = ( $Directory )
    }

    if ( Test-Path -LiteralPath "${Path}" ) {
        $UNC = ( Get-Item -Force -LiteralPath "${Path}" | Resolve-UNC-Path -ReturnObject )

        $indexHtmlPath = "${UNC}\index.html"

        if ( -Not ( Test-Path -LiteralPath "${indexHtmlPath}" ) ) {
            $listing = Get-ChildItem -Recurse -LiteralPath "${UNC}" | Resolve-UNC-Path -ReturnObject | Add-File-URI | Sort-Object -Property FullName | Select-URI-Link -RelativeTo $UNC

            $NL = [Environment]::NewLine

            $htmlUL = $listing | % -Begin { "<ul>" } -Process { '  <li>' + $_ + "</li>" } -End { "</ul>" }
            $htmlTitle = ( "Contents of: {0}" -f [System.Web.HttpUtility]::HtmlEncode($UNC) )

            $htmlOut = ( "<!DOCTYPE html>${NL}<html>${NL}<head>${NL}<title>{0}</title>${NL}</head>${NL}<body>${NL}<h1>{0}</h1>${NL}{1}${NL}</body>${NL}</html>${NL}" -f $htmlTitle, ( $htmlUL -Join "${NL}" ) )

            $htmlOut > $indexHtmlPath
        } else {
            Write-Error "index.html already exists in ${Directory}!"
        }
    }
}

function Is-Indexed-Directory {
Param( $File )

    $FileObject = Get-File-Object($File)
    $FilePath = $FileObject.FullName

    $result = $false
    if ( Test-Path -LiteralPath "${FilePath}" ) {
        $NewFilePath = "${FilePath}\index.html"
        $result = Test-Path -LiteralPath "${NewFilePath}"
    }
    return $result
}

function Is-Bagged-Indexed-Directory {
Param( $File )

    $FileObject = Get-File-Object($File)
    $FilePath = $FileObject.FullName

    $result = $false
    if ( Is-BagIt-Formatted-Directory($File) ) {
        $payloadPath = "${FilePath}\data"
        $result = Is-Indexed-Directory($payloadPath)
    }
    return $result
}

############################################################################################################
## FILE / DIRECTORY COMPARISON FUNCTIONS ###################################################################
############################################################################################################

Function Is-Different-File-Content {
Param ( $From, $To, [Int] $DiffLevel=2, [switch] $Verbose=$false )

    # We go through some rigamarole here because each side of the comparison MAY be
    # a valid file path whose content we can hash, OR it MAY be a string of a path
    # to a file that does not (yet) exist.

	$oFrom = Get-File-Object($From)
	$oTo = Get-File-Object($To)
	
	If ( $oFrom -ne $null ) {
		$Differentiated = ($oTo -eq $null)
	
		If ( ( -Not $Differentiated ) -and ( $DiffLevel -gt 0 ) ) {
			$LeftLength = $null
			$RightLength = $null
			If ( $oFrom -ne $null ) {
				$LeftLength = $oFrom.Length
			}
			If ( $oTo -ne $null ) {
				$RightLength = $oTo.Length
			}
			If ($Verbose) { Write-Output "Length comparison: ${LeftLength} vs. ${RightLength}" }
			$Differentiated=($Differentiated -or ( $LeftLength -ne $RightLength ))
		}

		If ( ( -Not $Differentiated ) -and ( $DiffLevel -gt 1 ) ) {
			$sFrom = Get-File-Literal-Path($oFrom)
			$sTo = Get-File-Literal-Path($oTo)
			
			$LeftHash = $null
			$RightHash = $null

			If ( $sFrom -ne $null ) {
				$LeftHash = (Get-FileHash -LiteralPath $sFrom).hash
			}
			If ( $sTo -ne $null ) {
				$RightHash = (Get-FileHash -LiteralPath $sTo).hash
			}
			If ($Verbose) { Write-Output "Hash comparison: ${LeftHash} vs. ${RightHash}" }
			$Differentiated=($Differentiated -or ( $LeftHash -ne $RightHash))
        }
    }
	Else {
		$Differentiated = ($oTo -ne $null)
	}

    Return $Differentiated
}

function Is-Matched-File ($From, $To, $DiffLevel=0) {
    $ToPath = $To
    if ( Get-Member -InputObject $To -name "FullName" -MemberType Properties ) {
        $ToPath = $To.FullName
    }

    $TreatAsMatched = ( Test-Path -LiteralPath "${ToPath}" )
    if ( $TreatAsMatched ) {
        $ObjectFile = (Get-Item -Force -LiteralPath "${ToPath}")
        if ( $DiffLevel -gt 0 ) {
            $TreatAsMatched = -Not ( Is-Different-File-Content -From $From -To $ObjectFile -DiffLevel $DiffLevel )
        }
    }
    return $TreatAsMatched
}

function Get-Unmatched-Items {
    [CmdletBinding()]

   param (
    [String]
    $Match,

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
        $Object = ($File | Rebase-File -To $Match)
        $OnConsider.Invoke($File, $Object, $DiffLevel, $iCounter)
        if ( -Not ( Is-Matched-File -From $File -To $Object -DiffLevel $DiffLevel ) ) {
            $File
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

Function Get-Bagged-ChildItem {
Param( $LiteralPath=$null, $Path=$null )

    If ( $LiteralPath -ne $null ) {
        $Items = Get-ChildItem -LiteralPath $LiteralPath -Directory
    }
    Else {
        $Items = Get-ChildItem -Path $Path -Directory
    }

    $Items | % {
        $Item = Get-File-Object -File $_

        If ( Is-BagIt-Formatted-Directory $Item ) {
            $Item
        }
        ElseIf ( -Not ( Is-Indexed-Directory -File $Item ) ) {
            Get-Bagged-Child-Items -LiteralPath $_.FullName
        }
    }

}

#############################################################################################################
## COMMAND FUNCTIONS ########################################################################################
#############################################################################################################

Function Do-Make-Bagged-ChildItem-Map {
Param( $LiteralPath=$null, $Path=$null)

    Get-Bagged-ChildItem -LiteralPath $LiteralPath -Path $Path | % {
        $_.FullName
    }
}

Function Do-Copy-Snapshot-File ($from, $to, $direction="over", $Batch=$false, [switch] $ReadOnly=$false) {
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
Param ($From, $To, $Trashcan, $Depth=0, $ProgressId=0, $NewProgressId=0)

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

        if ( -Not ( Is-Bagged-Copy-of-Loose-file -File ( Get-Item -LiteralPath $_.FullName ) ) ) {
            "Move-Item -LiteralPath $MoveFrom -Destination $MoveTo -Force"
            if ( -Not ( Test-Path -LiteralPath $Trashcan ) ) {
                mkdir $Trashcan
            }
            Move-Item -LiteralPath $MoveFrom -Destination $MoveTo -Force
        }
    }
    If ( -Not $Batch ) {
        Write-Progress -Id ($NewProgressId + 3) -Activity "Matching (rm): [${To}]" -Completed
    }

}

Function Do-Mirror-Directories {
Param ($From, $to, $Trashcan, $DiffLevel=1, $Depth=0, $ProgressId=0, $NewProgressId=0)

    $aDirs = Get-ChildItem -Directory -LiteralPath "$From"
    $N = $aDirs.Count
    $aDirs | Get-Unmatched-Items -Match "${To}" -DiffLevel 0 -OnConsider {
        Param($File, $Candidate, $DiffLevel, $I);
        If ( -Not $Batch ) {
            $sFileName = $File.Name
            Write-Progress -Id ($NewProgressId + 3) -Activity "Matching (mkdir): [${From}]" -Status $sFileName -percentComplete (100*$I / $N)
        }
    } | ForEach {
        $CopyFrom = $_.FullName
        $CopyTo = ($_ | Rebase-File -To "${To}")

        Write-Output "${CopyFrom}\\ =>> ${CopyTo}\\"
        Copy-Item -LiteralPath "${CopyFrom}" -Destination "${CopyTo}"
    }
    If ( -Not $Batch ) {
        Write-Progress -Id ($NewProgressId + 3) -Activity "Matching (mkdir): [${From}]" -Completed
    }
}

Function Do-Mirror-Files {
Param ($From, $To, $Trashcan, $DiffLevel=1, $Depth=0, $ProgressId=0, $NewProgressId=0)

    $i = 0
    $aFiles = ( Get-ChildItem -File -LiteralPath "$From" )
    $N = $aFiles.Count

    $sProgressActivity = "Matching Files (cp) [${From} => ${To}]"
    $aFiles = ( $aFiles | Get-Unmatched-Items -Match "${To}" -DiffLevel $DiffLevel -OnConsider {
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
        
        If ( -Not $Batch ) {
            Write-Progress -Id ($NewProgressId + 3) -Activity $sProgressActivity -Status "${BaseName}" -percentComplete (100*$i / $N)
        }
        Else {
            Write-Output "${CopyFrom} =>> ${CopyTo}"
        }
        $i = $i + 1

        
        Do-Copy-Snapshot-File "${CopyFrom}" "${CopyTo}" -Batch $Batch
        
    }
    If ( -Not $Batch ) {
        Write-Progress -Id ($NewProgressId + 3) -Activity $sProgressActivity -Completed
    }
}

Function Do-Mirror-Metadata {
Param( $From, $To, $ProgressId, $NewProgressId )

    $i = 0
    $aFiles = ( Get-ChildItem -LiteralPath "$From" | Get-Matched-Items -Match "${To}" -DiffLevel 0 )
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

function Do-Mirror ($From, $To, $Trashcan, $DiffLevel=1, $Depth=0) {
    $IdBase = (10 * $Depth)
    If ($Depth -gt 0) {
        $RootedIdBase = 0
    }
    Else {
        $RootedIdBase = 0
    }

    $sActScanning = "Scanning contents: [${From}]"
    $sStatus = "*.*"

    ##################################################################################################################
    ### CLEAN UP (rm): Files on destination not (no longer) on source get tossed out. ################################
    ##################################################################################################################

    Write-Progress -Id ($RootedIdBase + 2) -Activity $sActScanning -Status "${sStatus} (rm)" -percentComplete 0
    Do-Mirror-Clean-Up-Obsolete-Files -From $From -To $To -Trashcan $Trashcan -Depth $Depth -ProgressId $RootedIdBase -NewProgressId $IdBase

    ##################################################################################################################
    ## COPY OVER (mkdir): Create child directories on destination to mirror subdirectories of source. ################
    ##################################################################################################################

    Write-Progress -Id ($RootedIdBase + 2) -Activity $sActScanning -Status "${sStatus} (mkdir)" -percentComplete 20
    Do-Mirror-Directories -From $From -To $To -Trashcan $Trashcan -DiffLevel $DiffLevel -Depth $Depth -ProgressId $RootedIdBase -NewProgressId $IdBase

    ##################################################################################################################
    ## COPY OVER (cp): Copy snapshot files onto destination to mirror files on source. ###############################
    ##################################################################################################################

    Write-Progress -Id ($RootedIdBase + 2) -Activity $sActScanning -Status "${sStatus} (cp)" -percentComplete 40
    Do-Mirror-Files -From $From -To $To -Trashcan $Trashcan -DiffLevel $DiffLevel -Depth $Depth -ProgressId $RootedIdBase -NewProgressId $IdBase

    ##################################################################################################################
    ## METADATA: Synchronize source file system meta-data to destination #############################################
    ##################################################################################################################

    Write-Progress -Id ($RootedIdBase + 2) -Activity $sActScanning -Status "${sStatus} (meta)" -percentComplete 60
    Do-Mirror-Metadata -From $From -To $To -ProgressId $RootedIdBase -NewProgressId $IdBase

    ##################################################################################################################
    ### RECURSION: Drop down into child directories and do the same mirroring down yonder. ###########################
    ##################################################################################################################

    Write-Progress -Id ($RootedIdBase + 2) -Activity $sActScanning -Status "${sStatus} (chdir)" -percentComplete 80

    $i = 0
    $aFiles = ( Get-ChildItem -Directory -LiteralPath "$From" | Get-Matched-Items -Match "$To" -DiffLevel 0 )
    $N = $aFiles.Count
    
    $aFiles | ForEach {
        $BaseName = $_.Name
        $MirrorFrom = $_.FullName
        $MirrorTo = ($_ | Rebase-File -To "${To}")
        $MirrorTrash = ($_ | Rebase-File -To "${Trashcan}")

        $i = $i + 1
        Write-Progress -Id ($RootedIdBase + 2) -Activity "Recursing into subdirectories [${From}]" -Status "${BaseName}" -percentComplete (100*$i / $N)

        Do-Mirror -From "${MirrorFrom}" -To "${MirrorTo}" -Trashcan "${MirrorTrash}" -DiffLevel $DiffLevel -Depth ($Depth + 1)
    }
    Write-Progress -Id ($RootedIdBase + 2) -Activity "Recursing into subdirectories [${From}]" -Completed
}

function Do-Mirror-Repositories ($Pairs=$null, $DiffLevel=1) {

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
            $src = (Get-Item -Force -LiteralPath $locations[2] | Resolve-UNC-Path-To-Local-If-Local ).FullName
            $dest = (Get-Item -Force -LiteralPath $locations[1] | Resolve-UNC-Path-To-Local-If-Local ).FullName
            $TrashcanLocation = "${ColdStorageBackup}\${slug}_${Pair}"

            if ( -Not ( Test-Path -LiteralPath "${TrashcanLocation}" ) ) { 
                mkdir "${TrashcanLocation}"
            }

            Write-Progress -Id 1138 -Activity "Mirroring between ADAHFS servers and ColdStorage" -Status "Location: ${Pair}" -percentComplete ( 100 * $i / $N )
            Do-Mirror -From "${src}" -To "${dest}" -Trashcan "${TrashcanLocation}" -DiffLevel $DiffLevel
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
                Do-Mirror-Repositories -Pairs $recurseInto -DiffLevel $DiffLevel
            }
            Else {
                Write-Output "No such repository: ${Pair}."
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
        If ( Is-ER-Instance-Directory($File) ) {
            If ( -not ( $BaseName -match $Exclude ) ) {
                $ERMeta = ( $File | Select-ER-Instance-Data )
                $ERCode = $ERMeta.ERCode

                chdir $DirName

                if ( Is-BagIt-Formatted-Directory($File) ) {
                    if ( $Quiet -eq $false ) {
                        Write-Output "BAGGED: ${ERCode}, $DirName"
                    }
                } else {
                    Write-Output "UNBAGGED: ${ERCode}, $DirName"
                    
                    $NotOK = ( $DirName | Do-Scan-ERInstance )
                    if ( $NotOK.Count -gt 0 ) {
                        Do-Bleep-Bloop
                        $ShouldWeContinue = Read-Host "Exit Code ${NotOK}, Continue (Y/N)? "
                    } else {
                        $ShouldWeContinue = "Y"
                    }

                    if ( $ShouldWeContinue -eq "Y" ) {
                        Do-Bag-ERInstance $DirName
                    }

                }
            }
            ElseIf ( $Quiet -eq $false ) {
                Write-Output "SKIPPED: ${ERCode}, $DirName"
            }

            chdir $Anchor
        }
        ElseIf ( Is-Indexed-Directory($File) ) {
            Write-Output "STUBBED: ${File}, indexed." #FIXME
        }
        Else {
            Write-Output "Check for loosies."
            Get-ChildItem -File -LiteralPath $File.FullName | ForEach {
                If ( Is-Loose-File($_) ) {
                    If ( Is-Unbagged-Loose-File($_) ) {
                        $LooseFile = $_.Name
                        Write-Output "UNBAGGED: ${LooseFile}, loose."
                        Do-Bag-Loose-File -LiteralPath $_.FullName
                    }
                }
            }
        }
    }

    End {
    }
}

function Bagged-File-Path {
    param (
        [Switch]
        $FullName,

        [Switch]
        $Wildcard,

        [Parameter(ValueFromPipeline=$true)]
        $File
    )

    Begin { }

    Process {
        $Prefix = ""
        if ( $FullName ) {
            $Prefix = $File.Directory
            $Prefix = "${Prefix}\"
        }
        $FileName = $File.Name
        $FileName = ( $FileName -replace "[^A-Za-z0-9]", "_" )
        
        if ( $Wildcard ) {
            # 4 = YYYY, 2 = mm, 2 = dd, 2 = HH, 2 = MM, 2 = SS
            $Suffix = ( "[0-9]" * ( 4 + 2 + 2 + 2 + 2 + 2) )
        } else {
            $DateStamp = ( Date -UFormat "%Y%m%d%H%M%S" )
            $Suffix = "${DateStamp}"
        }
        $Suffix = "_bagged_${Suffix}"

        "${Prefix}${FileName}${Suffix}"
    }

    End { }
}

function Do-Scan-File-For-Bags {
    [CmdletBinding()]

param (
    [Switch]
    $Quiet,

    [String]
    $Exclude="^$",

    [ScriptBlock]
    $OnBagged={ Param($File, $Payload, $BagDir); $FilePath = $File.FullName; $PayloadPath = $Payload.FullName; Write-Output "BAGGED: ${FilePath} = ${PayloadPath}" },

    [ScriptBlock]
    $OnDiff={ Param($File, $Payload, $LeftHash, $RightHash); },

    [ScriptBlock]
    $OnUnbagged={ Param($File); $FilePath = $File.FullName; Write-Output "UNBAGGED: ${FilePath}" },

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
        $CardBag = ( $File | Bagged-File-Path -Wildcard )

        $BagPayload = $null
        if ( Test-Path -Path $CardBag ) {
            Dir -Force -Path $CardBag | ForEach {
                $BagPath = $_
                $BagData = $BagPath.FullName + "\data"
                if ( Test-Path -LiteralPath $BagData ) {
                    $BagPayloadPath = "${BagData}\${FileName}"
                    if ( Test-Path -LiteralPath $BagPayloadPath ) {
                    
                        $LeftHash = Get-FileHash -LiteralPath $File
                        $RightHash = Get-FileHash -LiteralPath $BagPayloadPath

                        if ( $LeftHash.hash -eq $RightHash.hash ) {
                            $BagPayload = ( Get-Item -Force -LiteralPath $BagPayloadPath )
                            $OnBagged.Invoke($File, $BagPayload, $BagPath)
                        } else {
                            $OnDiff.Invoke($File, $(Get-Item -Force -LiteralPath $BagPayloadPath), $LeftHash, $RightHash )
                        }
                    }
                }
            }
        }

        if ( -Not $BagPayload ) {
            $OnUnbagged.Invoke($File)
        }

        chdir $Anchor
    }

    End {
        if ( $Quiet -eq $false ) {
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

        $DirName = $File.FullName
        $BaseName = $File.Name

        # Is this an ER Instance directory?
        if ( Is-ER-Instance-Directory($File) ) {
            if ( -not ( $BaseName -match $Exclude ) ) {
                $ERMeta = ($File | Select-ER-Instance-Data)
                $ERCode = $ERMeta.ERCode

                chdir $DirName

                if ( Is-BagIt-Formatted-Directory($File) ) {
                    if ( $Quiet -eq $false ) {
                        Write-Output "BAGGED: ${ERCode}, $DirName"
                    }
                } else {
                    Write-Output "UNBAGGED: ${ERCode}, $DirName"
                }
            } elseif ( $Quiet -eq $false ) {
                Write-Output "SKIPPED: ${ERCode}, $DirName"
            }

            chdir $Anchor
        } else {
            chdir $File
            
            dir -File | Do-Scan-File-For-Bags
            dir -Directory | Select-Unbagged-Dirs | Do-Scan-Dir-For-Bags

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
        Write-Output "ClamAV Scan: ${Path}" -InformationAction Continue
        $ClamAV = Get-ClamAV-Path
        & "${ClamAV}\clamscan.exe" --stdout --bell --suppress-ok-results --recursive "${Path}" | Write-Output
        if ( $LastExitCode -ne 0 ) {
            $LastExitCode
        }
    }

    End { }
}

function Do-Validate-Bag ($DIRNAME, [switch] $Verbose = $false) {

    $Anchor = $PWD
    chdir $DIRNAME

    $BagIt = Get-BagIt-Path
    If ( $Verbose ) {
        & python.exe "${BagIt}\bagit.py" --validate . | Write-Host
    }
    Else {
        & python.exe "${BagIt}\bagit.py" --validate --quiet . 2>&1 | Write-Host
        $NotOK = $LastExitCode

        if ( $NotOK -gt 0 ) {
            Do-Bleep-Bloop
            & python.exe "${BagIt}\bagit.py" --validate . | Write-Host
        } else {
            Write-Output "OK-BagIt: ${DIRNAME}"
        }
    }
    chdir $Anchor
}

function Do-Bag-Repo-Dirs ($Pair, $From, $To) {
    $Anchor = $PWD

    chdir $From
    dir -Attributes Directory | Do-Clear-And-Bag -Quiet -Exclude $null
    chdir $Anchor
}

function Do-Bag ($Pairs=$null) {
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

function Do-Check-Repo-Dirs ($Pair, $From, $To) {
    $Anchor = $PWD

    chdir $From
    dir -File | Do-Scan-File-For-Bags
    dir -Directory| Do-Scan-Dir-For-Bags -Quiet -Exclude $null

    chdir $Anchor
}

function Do-Check ($Pairs=$null) {
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

            Do-Check-Repo-Dirs -Pair "${Pair}" -From "${src}" -To "${dest}"
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
            Do-Check -Pairs $recurseInto
        } # if

        $i = $i + 1
    }

}

Function Do-Validate ($Pairs=$null, [switch] $Verbose=$false) {
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
                Do-Make-Bagged-ChildItem-Map $src > $MapFile
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

            Get-Content $MapFile | % {
                If ( -Not $EnteredRange ) {
                    $EnteredRange = ( $BagRange[0] -eq $_ )
                }
                Else {
                    If ( -Not $ExitedRange ) {
                        $ExitedRange = ( $BagRange[1] -eq $_ )
                    }

                    If ( $ExitedRange ) {

                        $BagRange[1] = $_
                        $BagRange > $BookmarkFile
                                
                        $BagPath = Get-File-Literal-Path -File $_
                        Do-Validate-Bag -DIRNAME $BagPath -Verbose:$Verbose

                    }

                }
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
                Do-Validate -Pairs $recurseInto
            }
        } # if

        $i = $i + 1
    }

}

function Do-Rsync ($Pairs=$null, $DiffLevel=0) {
    
    if ( $Pairs.Count -lt 1 ) {
        $Pairs = $mirrors.Keys
    }
    
    $i = 0
    $N = ($Pairs.Count * 2)
    $Pairs | ForEach {
        $Pair = $_
        $locations = $mirrors[$Pair]
        
        $slug = $locations[0]
        $src = $locations[2]
        $dest = $locations[1]

        Write-Progress -Id 1137 -Activity "rsync between ADAHFS servers and ColdStorage" -Status "Location: ${Pair}" -percentComplete ( 100 * $i / $N )
        wsl -- "~/bin/coldstorage/coldstorage-mirror.bash" "${Pair}"
        $i = $i + 1 # Step 1

        Write-Progress -Id 1137 -Activity "rsync between ADAHFS servers and ColdStorage" -Status "Location: ${Pair}" -percentComplete ( 100 * $i / $N )
        Do-Mirror-Repositories -Pair "${Pair}" -DiffLevel $DiffLevel

        $i = $i + 1 # Step 2
    }
    Write-Progress -Id 1137 -Activity "rsync between ADAHFS servers and ColdStorage" -Completed
}

function Do-Write-Usage ($cmd) {
    $Pairs = ( $mirrors.Keys -Join "|" )

    Write-Output "Usage: $cmd mirror [$Pairs]"
}

if ( $Help -eq $true ) {
    Do-Write-Usage -cmd $MyInvocation.MyCommand
} else {
    $verb = $args[0]
    $t0 = date
    
    If ( $verb -eq "mirror" ) {
        $N = ( $args.Count - 1 )
        if ( $N -gt 0 ) {
            $Words = $args[1 .. $N]
        } else {
            $Words = @( )
        }

        $DiffLevel = 0
        if ($Diff) {
            $DiffLevel = 2
        }

        Do-Mirror-Repositories -Pairs $Words -DiffLevel $DiffLevel
    }
    ElseIf ( $verb -eq "check" ) {
        $Words = @( )

        $N = ( $args.Count - 1 )
        if ( $N -gt 0 ) {
            $Words = $args[1 .. $N]
        }
        Do-Check -Pairs $Words
    }
    ElseIf ( $verb -eq "validate" ) {
        $Words = @( )

        $N = ( $args.Count - 1 )
        if ( $N -gt 0 ) {
            $Words = $args[1 .. $N]
        }
        Do-Validate -Pairs $Words
    }
    ElseIf ( $verb -eq "bag" ) {
        $Words = @( )

        $N = ( $args.Count - 1 )
        if ( $N -gt 0 ) {
            $Words = $args[1 .. $N]
        }
        Do-Bag -Pairs $Words
    }
    ElseIf ( $verb -eq "index" ) {
        if ( $N -gt 0 ) {
            $Words = $args[1 .. $N]
        } else {
            $Words = @( Get-Location )
        }
        $Words | ForEach {
            Do-Make-Index-Html -Directory $_
        }
    }
    ElseIf ( $verb -eq "settings" ) {
        ColdStorage-Settings -Name $args[1]
        $Quiet = $true
    }
    ElseIf ( $verb -eq "bleep" ) {
        Do-Bleep-Bloop
    }
    Else {
        Do-Write-Usage -cmd $MyInvocation.MyCommand
        $Quiet = $true
    }

    $tN = date

    if ( -not $Quiet ) {
        Write-Output "Completed: ${tN}"
        Write-Output ( $tN - $t0 )
    }
}
