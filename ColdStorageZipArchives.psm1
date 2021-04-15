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
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gZipArchivesModuleCmd -File "ColdStorageFiles.psm1" )
Import-Module -Verbose:$false $( My-Script-Directory -Command $global:gZipArchivesModuleCmd -File "ColdStorageRepositoryLocations.psm1" )

######################################################################################################
## ZIP ###############################################################################################
######################################################################################################

Function Test-ZippedBagIntegrity {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {

    $oFile = Get-FileObject -File $File
    $sFileName = $oFile.Name
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
Param ( [Parameter(ValueFromPipeline=$true)] $File )

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
    $sRepositoryNode = ( $oRepository.Parent.Name, $oRepository.Name ) -join "-"

    $sFileName = $oFile.Name

    $reUNCRepo = [Regex]::Escape($sRepository)
    $sZipPrefix = ( $sFileUNCPath -ireplace "^${reUNCRepo}","${sRepositoryNode}" )
        
    $sZipPrefix = ( $sZipPrefix -replace "[^A-Za-z0-9]+","-" )

    "${sZipPrefix}-${sFileName}" # > stdout

}

End { }

}

# WAS/IS: Get-Zipped-Bag-Of-Bag/Get-ZippedBagOfUnzippedBag
Function Get-ZippedBagOfUnzippedBag {

Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    $oFile = Get-FileObject($File)
    If ( Test-BagItFormattedDirectory -File $oFile.FullName ) {
        $Containers = ( $oFile.FullName | Get-ZippedBagsContainer -All )
        $Prefix = ( Get-ZippedBagNamePrefix -File $oFile.FullName )
        $SearchPaths = ( $Containers.FullName | Join-Path -ChildPath "${Prefix}_z*_md5_*.zip" )
        $SearchPaths |% { Get-ChildItem -Path $_ }
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
            $oZipDir = ( Get-ChildItem "ZIP" -LiteralPath $Loc.FullName )
            $oZipDir
            $KeepOn = ( $All -Or ( -Not $oZipDir ) )
        }
    }

    If ( -Not $oZipDir ) {
        If ( -Not $NoCreate ) {
            ( $Locations | New-ZippedBagContainer )
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

Function Test-ZippedBagsContainer {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { 
    
}

Process {
    $oFile = ( Get-FileObject $File )
    $Parent = ( $File | Get-ItemFileSystemParent | Get-UNCPathResolved )
    $Repository = ( $File | Get-FileRepositoryLocation ).FullName

    $result = ( ( $Parent -ieq $Repository ) -and ( $oFile.Name -eq "ZIP" ) )
    $result | Write-Output
}

End { }

}

Export-ModuleMember -Function Test-ZippedBagIntegrity
Export-ModuleMember -Function Get-ZippedBagProfessedMD5
Export-ModuleMember -Function Get-ZippedBagNamePrefix
Export-ModuleMember -Function Get-ZippedBagOfUnzippedBag
Export-ModuleMember -Function New-ZippedBagsContainer
Export-ModuleMember -Function Add-ZippedBagsContainer
Export-ModuleMember -Function Get-ZippedBagsContainer
Export-ModuleMember -Function Test-ZippedBagsContainer
