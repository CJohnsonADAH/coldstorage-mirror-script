﻿#############################################################################################################
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
        $Repository = ( $oFile.FullName | Get-ZippedBagsContainer )
        $Prefix = ( Get-ZippedBagNamePrefix -File $oFile.FullName )
        Get-ChildItem -Path "${Repository}\${Prefix}_z*_md5_*.zip"
    }
}

End { }

}

# WAS/IS: Get-Zipped-Bag-Location/Get-ZippedBagsContainer
Function Get-ZippedBagsContainer {

Param ( [Parameter(ValueFromPipeline=$true)] $File, $Repository=@( ) )

Begin { }

Process {
    $File | Get-FileRepositoryLocation |% {
        $sRepoDir = $_.FullName
        $sZipDir = "${sRepoDir}\ZIP"
        If ( -Not ( Test-Path -LiteralPath $sZipDir ) ) {
            $oZipDir = ( New-Item -ItemType Directory -Path "${sZipDir}" )
        }
        Else {
            $oZipDir = ( Get-Item -Force -LiteralPath "${sZipDir}" )
        }
        $oZipDir
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
Export-ModuleMember -Function Get-ZippedBagsContainer
Export-ModuleMember -Function Test-ZippedBagsContainer
