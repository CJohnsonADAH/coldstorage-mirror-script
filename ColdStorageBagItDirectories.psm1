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

Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageFiles.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Test-BagItFormattedDirectory {
Param ( $File )

    $result = $false # innocent until proven guilty

    $oFile = Get-FileObject -File $File
    If ( $oFile -ne $null ) {
        $BagDir = $oFile.FullName
        if ( Test-Path -LiteralPath $BagDir -PathType Container ) {
            $PayloadDir = ( "${BagDir}" | Join-Path -ChildPath "data" )
            if ( Test-Path -LiteralPath $PayloadDir -PathType Container ) {
                $BagItTxt = ( "${BagDir}" | Join-Path -ChildPath "bagit.txt" )
                if ( Test-Path -LiteralPath $BagItTxt -PathType Leaf ) {
                    $result = $true
                }
            }
        }
        ( "[Test-BagItFormattedDirectory] Result={0} -- File: '{1}'" -f $result,$File ) | Write-Debug
    }
    Else {
        ( "[Test-BagItFormattedDirectory] Result={0} -- File Not Found: '{1}'" -f $result,$File ) | Write-Debug
    }

    $result | Write-Output
}

Function Select-BagItFormattedDirectories {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process { If ( Test-BagItFormattedDirectory($File) ) { $File } }

End { }
}

Function Select-BagItPayloadDirectory {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    If ( $File -ne $null ) {
        $sPath = ( ( Get-FileObject($File).FullName ) | Join-Path -ChildPath "data" )
        Get-Item -Force -LiteralPath "${sPath}"
    }
}

End { }

}

Function Select-BagItPayload {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    $File | Select-BagItPayloadDirectory |% {
        $sPath = $_.FullName
        Get-ChildItem -Force -Recurse -LiteralPath "${sPath}"
    }
}

End { }

}

Export-ModuleMember -Function Test-BagItFormattedDirectory
Export-ModuleMember -Function Select-BagItFormattedDirectories
Export-ModuleMember -Function Select-BagItPayloadDirectory
Export-ModuleMember -Function Select-BagItPayload
