#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

Function My-Script-Directory {
Param ( $Command, $File=$null )

    $Source = ( $Command.Source | Get-Item -Force )
    $Path = ( $Source.Directory | Get-Item -Force )

    If ( $File -ne $null ) {
        $Path = ($Path.FullName + "\" + $File)
    }

    $Path
}

$global:gZipArchivesModuleCmd = $MyInvocation.MyCommand

Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gZipArchivesModuleCmd -File "ColdStorageSettings.psm1" )
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gZipArchivesModuleCmd -File "ColdStorageData.psm1" )
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gZipArchivesModuleCmd -File "ColdStorageFiles.psm1" )
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gPackagingConventionsCmd -File "ColdStorageBagItDirectories.psm1" )
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gZipArchivesModuleCmd -File "ColdStorageRepositoryLocations.psm1" )
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gZipArchivesModuleCmd -File "ColdStorageInteraction.psm1" )

######################################################################################################
## ZIP ###############################################################################################
######################################################################################################

Function Test-ZippedBagIntegrity {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [String[]] $Skip=@() )

Begin { }

Process {

    $oFile = Get-FileObject -File $File
    $sFileName = $oFile.Name
    If ( -Not ( $Skip | Select-String -Pattern "^zip$" ) ) {
        $Algorithm = "MD5"

        $OldMD5 = ($File | Get-ZippedBagProfessedMD5 )
        $oChecksum = ( Get-FileHash -LiteralPath $oFile.FullName -Algorithm MD5 )
        $NewMD5 = $oChecksum.hash

        If ( $OldMD5 -ieq $NewMD5 ) {
            "OK-Zip/${Algorithm}: ${sFileName}" | Write-Output
        }
        Else {
            "ERR-Zip/${Algorithm}: ${sFileName} with checksum ${NewMD5}" | Write-Warning
        }
    }
    Else {
        $Algorithm = "SKIPPED"
        "OK-Zip/${Algorithm}: ${sFileName}" | Write-Output
    }
}

End { }

}

Function Get-ZippedBagProfessedMD5 {

Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    $oFile = Get-FileObject -File $File
    $reMD5 = "^.*_md5_([A-Za-z0-9]+)[.]zip$"

    If ( $oFile.Name -imatch $reMD5 ) {
        Write-Output ( $oFile.Name -ireplace $reMD5,'$1' )
    }
}

End { }

}

# WAS: Get-Bag-Zip-Name-Prefix
Function Get-ZippedBagNamePrefix {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $Extension=$null )

Begin { }

Process {
    $oFile = Get-FileObject -File $File

    # Fully qualified file system path to the containing parent
    $sFilePath = ( Get-ItemFileSystemParent $oFile ).FullName
    
    # Fully qualified UNC path to the containing parent
    $oFileUNCPath = ( $sFilePath | Get-UNCPathResolved -ReturnObject )
    $sFileUNCPath = $oFileUNCPath.FullName

    # Slice off the root directory up to the node name of the repository container
    $oRepository = Get-FileObject -File ( $oFileUNCPath | Get-FileRepositoryLocation )
    $sRepository = $oRepository.FullName
    $sRepositoryNode = ( $File | Get-FileRepositoryPrefix -Fallback )
    
    $sFileName = $oFile.Name

    $reUNCRepo = [Regex]::Escape($sRepository)
    $sZipPrefix = ( $sFileUNCPath -ireplace "^${reUNCRepo}","${sRepositoryNode}" )
        
    $sZipPrefix = ( $sZipPrefix -replace "[^A-Za-z0-9]+","-" )

    $sZippedBagNamePrefix = ( "${sZipPrefix}-${sFileName}" )

    # SAFEGUARD: avoid "The specified path, file name, or both are too long." exceptions...
    # "The fully qualified file name must be less than 260 characters, and the directory name must be less than 248 characters."
    # If the prefix is long enough that the prefix + metadata suffixes + file extension will push it over,
    # trim it down and use an MD5 hash to help keep the naming unique.

    $nMaxPrefixLen = 185 ; $nMaxPrefixTrim = ( $nMaxPrefixLen - 35 )
    If ( $sZippedBagNamePrefix.Length -gt $nMaxPrefixLen ) {
            
        $stream = [System.IO.MemoryStream]::new()
        $writer = [System.IO.StreamWriter]::new($stream)
        $writer.write($sZippedBagNamePrefix)
        $writer.Flush()
        $stream.Position = 0
        $oZipHashedSlugHash = ( Get-FileHash -InputStream $stream -Algorithm:MD5 )
        $sZipHashedSlugHash = $oZipHashedSlugHash.Hash

        $sZippedBagNamePrefix = ( '{0}--{1}' -f ( $sZippedBagNamePrefix.Substring(0, $nMaxPrefixTrim ) ), $sZipHashedSlugHash.ToLower() )

    }
    
    If ( $Extension -ne $null ) {
        $sZippedBagNamePrefix = ( '{0}.{1}' -f $sZippedBagNamePrefix, $Extension )
    }

    $sZippedBagNamePrefix | Write-Output

}

End { }

}

Function Get-ZippedBagNameWithTimestamp {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $TS=$null, [switch] $WhatIf=$false )

    Begin {
        $sTSFormat = 'yyyyMMddHHmmss'
        $sTSPattern = 'z{0}'
    }

    Process {

        $sTS = $TS
        If ( $TS -eq $null ) {
            $sTS = ( Get-Date ).ToString($sTSFormat)
        }
        ElseIf ( $TS -is [DateTime] ) {
            $sTS = ( $TS.ToString( $sTSFormat ) )
        }
        ElseIf ( $TS -is [String] ) {
            $sTS = $TS
        }

        If ( $File -is [string] ) {
            $FileName = ( $File | Split-Path -Leaf )
        }
        Else {
            $FileName = $File.Name
        }

        $FileNameParts = ( $FileName -split '[.]',2 )
        If ( $sTS -ne $null ) {
            $FileSlugParts = ( $FileNameParts[0] -split '_' )
            $FileSlugParts = @( $FileSlugParts ) + @( ( $sTSPattern -f $sTS ) )
            $FileSlug = ( $FileSlugParts -join "_" )
            $FileNameParts[0] = ( $FileSlug )
        }
        $FileName = ( $FileNameParts -join '.' )
        
        $FileName | Write-Output

    }

    End { }

}


Function Get-ZippedBagNameWithChecksum {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $Hash=$null, $HashAlgorithm="md5", [switch] $WhatIf=$false )

    Begin { }

    Process {
        $sHash = $null
        $sAlgorithm = $HashAlgorithm
        $oHash = $Hash

        If ( $File | Get-Member -Name CSZippedBagChecksum ) {
            $sHash = $File.CSZippedBagChecksum
            If ( $File | Get-Member -Name CSZippedBagChecksumAlgorithm ) {
                $sAlgorithm = $File.CSZippedBagChecksumAlgorithm
            }
        }
        Else {

            If ( $oHash -is [ScriptBlock] ) {
                $oHash = ( $oHash.Invoke() )
            }
            ElseIf ( $oHash -is [String] ) {
                $oHash = [PSCustomObject] @{ "Algorithm"=$sAlgorithm; "Hash"=$Hash; "Path"=$File.FullName }
            }

            If ( $oHash -eq $null ) {
                $sHash = $null
            }
            ElseIf ( $oHash | Get-Member -Name Hash ) {
                # If the hash is a Get-FileHash object, COPY the (already computed) hash
                $sHash = $oHash.Hash

                If ( $oHash | Get-Member -Name Algorithm ) {
                    $sAlgorithm = $oHash.Algorithm
                }

            }
            ElseIf ( $oHash | Get-Member -Name FullName ) {
                # If the "hash" is a file reference, COMPUTE the hash from the file's contents
                $oHash = ( Get-FileHash -LiteralPath $Hash.FullName -Algorithm:$sAlgorithm )
                If ( $oHash ) {
                    $sHash = $oHash.Hash
                }

            }
        }

        If ( $File -is [string] ) {
            $FileName = ( $File | Split-Path -Leaf )
        }
        Else {
            $FileName = $File.Name
        }

        $FileNameParts = ( $FileName -split '[.]',2 )
        If ( $sHash -ne $null ) {
            $Pattern = ( '_{0}_[0-9a-fA-F]+$' -f $HashAlgorithm )
            $FileSlug = ( $FileNameParts[0] -replace $Pattern,'' )

            $FileNameParts[0] = ( '{0}_{1}_{2}' -f $FileSlug, $sAlgorithm.ToLower(), $sHash.ToLower() )
        }
        $FileName = ( $FileNameParts -join '.' )
        
        $FileName | Write-Output

    }

    End { }

}

Function Get-ZippedBagNameWithMetadata {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $Repository, $TS=$null, $Hash=$null, $HashAlgorithm="md5" )

    Begin { }

    Process {

        $sZipPrefix = ( Get-ZippedBagNamePrefix -File $File )
        $sZipNameSimple = ( '{0}.zip' -f $sZipPrefix )

        $sZipNameWithTimestamp = ( $sZipNameSimple | Get-ZippedBagNameWithTimestamp -TS:$TS )       
        $sZipNameWithMetadata = ( $sZipNameWithTimestamp | Get-ZippedBagNameWithChecksum -Hash:$Hash -HashAlgorithm:$HashAlgorithm )
         
        $Repository | Join-Path -ChildPath:$sZipNameWithMetadata

    }

    End { }

}

# WAS/IS: Get-Zipped-Bag-Of-Bag/Get-ZippedBagOfUnzippedBag
Function Get-ZippedBagOfUnzippedBag {

Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $BinaryOnly=$false )

Begin { }

Process {
    $oFile = Get-FileObject($File)
    If ( Test-BagItFormattedDirectory -File $oFile.FullName ) {
        $Containers = ( $oFile.FullName | Get-ZippedBagsContainer -All )
        $Prefix = ( Get-ZippedBagNamePrefix -File $oFile.FullName )
        If ( $Containers.FullName -ne $null ) {
            $ChildWildCard = ( "{0}_z*_md5_*.zip" -f "${Prefix}" )
            $ChildWildCardJson = ( "{0}.json" -f "${ChildWildCard}" )
            $SearchPaths = ( $Containers.FullName | Join-Path -ChildPath $ChildWildCard )
            If ( -Not $BinaryOnly ) {
                $SearchPaths = @( $SearchPaths ) + @( ( $Containers.FullName | Join-Path -ChildPath $ChildWildCardJson ) )
            }
        }
        Else {
            $SearchPaths = @()
        }
        $SearchPaths |% { Get-ChildItem -Path $_ }
    }
}

End { }

}

Function Add-ZippedBagOfPreservationPackage {

Param (
	[Parameter(ValueFromPipeline=$true)] $Package,
	$LogFile=$null,
	[switch] $Force=$false,
	[switch] $PassThru=$false,
	[switch] $WhatIf
)

    Begin { }

    Process {

		$oPackage = $Package
		If ( $Package.CSPackageBagLocation -and ( $Package.CSPackageBagLocation.Count -gt 0 ) ) {
			$Package.CSPackageBagLocation | Sort-Object -Property LastWriteTime -Descending | Select-Object -First:1 |% {
				$oPackage = $_
			}
		}
		
        $oFile = ( $oPackage | Get-FileObject )

        $oZip = @( )
        If ( -Not $Force ) {
            
            $oZip = ( $oFile | Get-ZippedBagOfUnzippedBag )

        }

        If ( $oZip.Count -eq 0 ) {

            $oRepository = ( $oFile | Get-ZippedBagsContainer -NoCreate:$WhatIf )
            $sRepository = $oRepository.FullName

            If ( $sRepository ) {
            
                $sAlgorithm='MD5'
                $oTS = ( Get-Date )

                $sZipName = ( Get-ZippedBagNamePrefix -File $oFile -Extension:'zip' )
                $sZipPath = ( $sRepository | Join-Path -ChildPath:$sZipName )

				$oPackage = ( $oFile | Get-ItemPackage -At )
                $CAResult = ( $oFile.FullName | Compress-ArchiveWith7z -WhatIf:$WhatIf -DestinationPath:$sZipPath | Write-CSOutputWithLogMaybe -Package:$oPackage -Command:("'{0}' | Compress-ArchiveWith7z"  -f $oFile.FullName ) -Log:$LogFile )
                $CACompleted = ( Get-Date )

                If ( $CAResult[0] -eq 0 ) {
                
                    $oZip = ( $sZipPath | Get-FileObject )
                    $oZip | Add-Member -MemberType NoteProperty -Name:CSCompressArchiveResult -Value:$CAResult -Force
                    $oZip | Add-Member -MemberType NoteProperty -Name:CSCompressArchiveExitCode -Value:$CAResult[0] -Force
                    $oZip | Add-Member -MemberType NoteProperty -Name:CSCompressArchiveOutput -Value:( $CAResult | Select-Object -Skip:1 ) -Force
                    $oZip | Add-Member -MemberType NoteProperty -Name:CSCompressArchiveTimestamp -Value:$CACompleted -Force

                    If ( $Package | Get-Member -Name:CSPackageZip ) {
                        $oZip = @( $oZip ) + ( $Package.CSPackageZip )
                    }

                    $Package | Add-Member -MemberType:NoteProperty -Name:CSPackageZip -Value:@( $oZip ) -Force
                    $oFile | Add-Member -MemberType:NoteProperty -Name:CSPackageZip -Value:@( $oZip ) -PassThru:$PassThru -Force

                }
                Else {
                    $CAResult | Write-Warning
                }

            }
        }

    }

    End { }

}


# WAS/IS: Get-Zipped-Bag-Location/Get-ZippedBagsContainer
Function New-ZippedBagsContainer {
Param ( [Parameter(ValueFromPipeline=$true)] $Location, [switch] $All=$false )

    Begin { $KeepOn=$true }

    Process {
        $Props = ( $Location.FullName | Get-ItemColdStorageProps -Cascade )
        $ZipUniverse = $Props["Zip"]
        $JunctionDestination = $null
        If ( $ZipUniverse ) {
            $ZipUniverse = ( $ZipUniverse | ConvertTo-ColdStorageSettingsFilePath | Get-LocalPathFromUNC )
            $JunctionDestination = ( $Props.Cascade | Select-Object -First 1 | Split-MirrorMatchedPath -Stem |% { $ZipUniverse | Join-Path -ChildPath $_ } )
            If ( $JunctionDestination ) {
                $JunctionDestination = $JunctionDestination | Join-Path -ChildPath "ZIP"
            }
        }

        $oZipDir = $null
        If ( $KeepOn ) {
            $sZipDir = ( $Location.FullName | Join-Path -ChildPath "ZIP" )
            If ( $JunctionDestination -eq $null ) {
                $oZipDir = ( New-Item -ItemType Directory -Path "${sZipDir}" )
            }
            Else {
                If ( -Not ( Test-Path -LiteralPath "${JunctionDestination}" ) ) {
                    $oZipJunct = ( New-Item -ItemType Directory -Path "${JunctionDestination}" )
                }
                $oZipDir = ( New-Item -ItemType Junction -Path "${sZipDir}" -Value "${JunctionDestination}" )
            }
            $oZipDir ; $KeepOn = ( $All -Or ( -Not $oZipDir ) )
        }
    }

    End { }

}

Function Add-ZippedBagsContainer {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $Repository=@( ), [switch] $All=$false )

    Begin { }

    Process {
        # OPTION 1. Look for the nearest .coldstorage location for this repository.
        $Locations = ( $File | Get-ItemPropertiesDirectoryLocation -Name ".coldstorage" -Order Nearest -All:$All )

        $Locations | Select-Object -First 1 |% {
            $Loc = $_
            $oZipDir = ( Get-ChildItem "ZIP" -LiteralPath $Loc.FullName )
            If ( -Not $oZipDir ) {
                $Loc | New-ZippedBagsContainer
            }
        }
    }

    End { }

}

Function Get-ZippedBagsContainer {

Param ( [Parameter(ValueFromPipeline=$true)] $File, $Repository=@( ), [switch] $NoCreate=$false, [switch] $All=$false )

Begin { }

Process {
    # OPTION 1. Look for the nearest .coldstorage location for this repository.
    $Locations = ( $File | Get-ItemPropertiesDirectoryLocation -Name ".coldstorage" -Order Nearest -All:$All )

    # OPTION 2. Look in the big collective pool for this repository.
    $Locations = ( [array] $Locations + ( $File | Get-FileRepositoryLocation ) )

    $KeepOn = $true
    $oZipDir = $null
    $Locations |% {
        $Loc = $_
        If ( $KeepOn ) {
            If ( $Loc.FullName -ne $null ) {
                $oZipDir = ( Get-ChildItem "ZIP" -LiteralPath $Loc.FullName )
            }
            Else {
                $oZipDir = ( Get-Item -LiteralPath "." )
            }

            $oZipDir
            $KeepOn = ( $All -Or ( -Not $oZipDir ) )
        }
    }

    If ( -Not $oZipDir ) {
        If ( -Not $NoCreate ) {
            ( $Locations | New-ZippedBagsContainer )
        }
    }

}

End {
    $Repository |% {
        $Location = Get-ColdStorageZipLocation -Repository:$_
        If ( $Location ) {
            $Location | Get-ZippedBagsContainer
        }
    }
}

}

Function New-ZippedBagContainer {

Param ( [Parameter(ValueFromPipeline=$true)] $File, $Repository=@( ) )

    Begin { }

    Process {

        # We have failed to find a good nearby .coldstorage\ZIP location for this repository.
        # So let's go to PLAN B, the expected location for the big collective pool for this repository.
        $Locations = @( $File | Get-FileRepositoryLocation )

        $oZipDir = $null
        $Locations |% {
            $Loc = $_
            $oZipDir = ( Get-ChildItem "ZIP" -LiteralPath $Loc.FullName )
            If ( -Not $oZipDir ) {
                $Candidate = ( Join-Path $Loc.FullName -ChildPath "ZIP" )
                $oZipDir = ( New-Item -ItemType Directory $Candidate )
            }
            $oZipDir
        }

    }

    End { }

}

Function Test-ZippedBagsContainer {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { 
    
}

Process {
    $oFile = ( Get-FileObject $File )
    $Parent = ( $File | Get-ItemFileSystemParent | Get-UNCPathResolved )
    $Repository = ( ( $File | Get-FileRepositoryLocation ).FullName | Get-UNCPathResolved )

    $isNamedZIP = ( $oFile.Name -eq "ZIP" )
    $isGlobalZIP = ( ( $Parent -ieq $Repository ) -and $isNamedZIP )
    $isLocalZIP = ( ( $Parent | Test-ColdStoragePropsDirectory -NoPackageTest ) -and $isNamedZIP )

    ( $isGlobalZIP -or $isLocalZIP ) | Write-Output
}

End { }

}

Function Compress-ArchiveWith7z {
Param (
	[switch] $WhatIf=$false,
	[Parameter(ValueFromPipeline=$true)] $LiteralPath,
	$DestinationPath 
)

    $ZipExe = Get-ExeFor7z
    $add = "a"
    $zip = "-tzip"
    $batch = "-y"

    $sLiteralPath = Get-FileLiteralPath($LiteralPath)
    $Output = ( & "${ZipExe}" "${add}" "${zip}" "${batch}" "${DestinationPath}" "${sLiteralPath}" )
    $ExitCode = $LastExitCode
    ( @( $ExitCode ) + @( $Output ) ) | Write-Output
}

Export-ModuleMember -Function Test-ZippedBagIntegrity
Export-ModuleMember -Function Get-ZippedBagProfessedMD5
Export-ModuleMember -Function Get-ZippedBagNamePrefix
Export-ModuleMember -Function Get-ZippedBagNameWithTimestamp
Export-ModuleMember -Function Get-ZippedBagNameWithChecksum
Export-ModuleMember -Function Get-ZippedBagNameWithMetadata
Export-ModuleMember -Function Get-ZippedBagOfUnzippedBag
Export-ModuleMember -Function Add-ZippedBagOfPreservationPackage
Export-ModuleMember -Function New-ZippedBagsContainer
Export-ModuleMember -Function Add-ZippedBagsContainer
Export-ModuleMember -Function Get-ZippedBagsContainer
Export-ModuleMember -Function Test-ZippedBagsContainer
Export-ModuleMember -Function Compress-ArchiveWith7z
