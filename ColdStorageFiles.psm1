<#
.SYNOPSIS
Module for utility functions dealing with the local or network-shared file system.

.DESCRIPTION

@version 2021.0324
#>

Function Get-FileObject ( $File ) {
    
    $oFile = $null
    If ( ( $File -is [String] ) -and ( $File.length -gt 0 ) ) {

        If ( Test-Path -LiteralPath "${File}" ) {
            $oFile = ( Get-Item -Force -LiteralPath "${File}" )
        }

    }
    Else {
        $oFile = $File
    }

    $oFile
}

Function Get-FileLiteralPath {
Param($File)

	$sFile = $null

	If ( $File -eq $null ) {
		$oFile = $null
	}
	ElseIf ( $File -is [String] ) {
		$oFile = Get-FileObject($File)
    }
	ElseIf ( -Not ( Get-Member -InputObject $File -name "FullName" -MemberType Properties ) ) {
		$oFile = Get-FileObject($File)
	}
	Else {
		$oFile = $File
	}

	If ( $oFile -ne $null ) {
        If ( Get-Member -InputObject $oFile -name "FullName" -MemberType Properties ) {
		    $sFile = $oFile.FullName
        }
	}
	
	$sFile
}

Function Get-ItemFileSystemParent {
Param( [Parameter(ValueFromPipeline=$true)] $Piped, $File=$null)

Begin { }

Process {

    $oFile = Get-FileObject ( $Piped )

    If ( $oFile ) {
        If ( $oFile.Parent ) {
            $oFile.Parent
        }
        ElseIf ( $oFile.Directory ) {
            $oFile.Directory
        }
    }
}

End { If ( $File.Count -gt 0 ) { $File | Get-ItemFileSystemParent -File:$null } }

}

Function Test-HiddenOrSystemFile ( $File ) {
    $oFile = Get-FileObject $File
    $screen = ( [IO.FileAttributes]::System + [IO.FileAttributes]::Hidden )

    ( ( $oFile.Attributes -band $screen ) -ne 0 )
}

Function Test-SystemArtifactItem {
Param ( $File )

    $oFile = Get-FileObject $File
    
    If ( $oFile ) {
        ( $oFile.Name -eq 'Thumbs.db' )
    }
    Else {
        $false
    }
}

Function Get-SystemArtifactItems {
Param ( $LiteralPath )

    Get-ChildItem -LiteralPath $LiteralPath -Force |% { If ( Test-SystemArtifactItem -File $_ ) { $_ } }

}

Function Test-DifferentFileContent {
Param ( $From, $To, [Int] $DiffLevel=2, [switch] $Verbose=$false )

    # We go through some rigamarole here because each side of the comparison MAY be
    # a valid file path whose content we can hash, OR it MAY be a string of a path
    # to a file that does not (yet) exist.

	$oFrom = Get-FileObject($From)
	$oTo = Get-FileObject($To)
	
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
			$sFrom = Get-FileLiteralPath($oFrom)
			$sTo = Get-FileLiteralPath($oTo)
			
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

    $Differentiated
}

# WAS/IS: Resolve-UNC-Path/Get-UNCPathResolved
Function Get-UNCPathResolved {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $ReturnObject=$false )

Begin {}

Process {
    $output = $null

    $FileObject = Get-FileObject($File)

    $Drive = $null
    $Root = $null

    If ( -Not ( $FileObject -eq $null )) {
        If ( Get-Member -InputObject $FileObject -Name "Root" -MemberType Properties ) {
            $Root = $FileObject.Root
        } ElseIf ( Get-Member -InputObject $FileObject -Name "Directory" -MemberType Properties ) {
            $Parent = $FileObject.Directory
            $Root = $Parent.Root
        }
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
            $File | Get-Member -Type NoteProperty | ForEach-Object {
                If ( -Not ( $output | Get-Member -Type NoteProperty -Name $_.Name ) ) {
                    $output | Add-Member -Type NoteProperty -Name $_.Name -Value ( $File | Select -ExpandProperty $_.Name )
                }
            }
        }
        $output
    }
}

End {}

}

$global:csaShares = $null
Function Get-LocalPathShares {
    If ( $global:csaShares -eq $null ) {
        $sHost = $env:COMPUTERNAME
        $global:csaShares = ( Get-WMIObject -ComputerName "${sHost}" -Query "SELECT * FROM Win32_Share" )
    }
    $global:csaShares
}

# WAS/IS: Resolve-UNC-Path-To-Local-If-Local/Get-LocalPathFromUNC
Function Get-LocalPathFromUNC {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin {
    $sHost = $env:COMPUTERNAME
    $aShares = Get-LocalPathShares
    $sShareLocalPath = $null
    $sLocalFullName = $null
}

Process {
    If ( $File -is [string] ) {
        $File = Get-FileObject($File)
    }

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

# WAS/IS: Get-File-FileSystem-Location/Get-ItemFileSystemLocation
Function Get-ItemFileSystemLocation {
Param( [Parameter(ValueFromPipeline=$true)] $Piped, $File=$null )

Begin { }

Process {

    $oFile = Get-FileObject -File ( $Piped )
    If ( $oFile ) {
        If ( Get-Member -InputObject $oFile -name "Directory" -MemberType Properties ) {
            $oLoc = ( $oFile.Directory | Add-Member -Force -NotePropertyMembers @{Leaf=( $oFile.Name ); Location=( $oFile.Directory.FullName ); RelativePath=@( $oFile.Directory.Name, $oFile.Name ) } -PassThru )
        }
        Else {
            $oLoc = ( $oFile | Add-Member -Force -NotePropertyMembers @{Leaf="."; Location=( $oFile.FullName ); RelativePath=@( $oFile.Name ) } -PassThru )
        }
        $oLoc
    }
}

End { If ( $File.Count -gt 0 ) { $File | Get-ItemFileSystemLocation -File:$null } }

}


Function Get-ItemFileSystemSearchPath {
Param ( [Parameter(ValueFromPipeline=$true)] $Piped, $File=$null, [ValidateSet('Highest', 'Nearest', '')] [string] $Order=$null, $Depth=0 )

    Begin { }

    Process {
        If ( $Depth -lt 9999) { # Sanity check
            $Dir = ( $Piped | Get-ItemFileSystemLocation )

            If ( $Order -ne "Highest" ) { $Dir }
            If ( $Dir.Parent ) {
                $Dir.Parent | Get-ItemFileSystemSearchPath -File:$null -Depth:($Depth+1) -Order:$Order
            }
            If ( $Order -eq "Highest" ) { $Dir }
        }
    }

    End { If ( $File.Count -gt 0 ) { $File | Get-ItemFileSystemSearchPath -File:$null -Depth:($Depth+1) -Order:$Order } }
}

Function Get-ItemFileSystemSearchFor {
Param ( [Parameter(ValueFromPipeline=$True)] $Piped, $Name=$null, [switch] $Wildcard=$false, [switch] $Regex=$false, [switch] $All=$false )

    Begin { $KeepOn = $true }

    Process {
        If ( $KeepOn ) {
            $Location = Get-FileObject($Piped)
            $TestPath = ( $Location.FullName | Join-Path -ChildPath $Name )
            If ( Test-Path -LiteralPath $TestPath ) {
                Get-Item -Force -LiteralPath $TestPath
                $KeepOn = $All
            }
            If ( $Wildcard ) {
                If ( Test-Path -Path $TestPath ) {
                    Get-Item -Force -Path $TestPath
                    $KeepOn = $All
                }
            }
            If ( $Regex ) {
                Get-ChildItem -LiteralPath $Location.FullName |% {
                    If ( $_.Name -match $Name ) {
                        $_
                        $KeepOn = $All
                    }
                }
            }

        }
    }

    End { }
}

Function Get-ItemPropertiesDirectoryLocation {
Param ( [Parameter(ValueFromPipeline=$True)] $Piped, $Name=$null, [ValidateSet('Highest', 'Nearest', '')] [string] $Order=$null, [switch] $Wildcard=$false, [switch] $Regex=$false, [switch] $All=$false )

    Begin { }

    Process {
        $Piped | Get-ItemFileSystemSearchPath -Order:$Order | Get-ItemFileSystemSearchFor -Name:$Name -Wildcard:$Wildcard -Regex:$Regex -All:$All
    }

    End { }

}

Export-ModuleMember -Function Get-FileObject
Export-ModuleMember -Function Get-FileLiteralPath
Export-ModuleMember -Function Test-HiddenOrSystemFile
Export-ModuleMember -Function Test-SystemArtifactItem
Export-ModuleMember -Function Get-SystemArtifactItems
Export-ModuleMember -Function Test-DifferentFileContent
Export-ModuleMember -Function Get-UNCPathResolved
Export-ModuleMember -Function Get-LocalPathFromUNC
Export-ModuleMember -Function Get-ItemFileSystemLocation
Export-ModuleMember -Function Get-ItemFileSystemParent
Export-ModuleMember -Function Get-ItemFileSystemSearchPath
Export-ModuleMember -Function Get-ItemFileSystemSearchFor
Export-ModuleMember -Function Get-ItemPropertiesDirectoryLocation
