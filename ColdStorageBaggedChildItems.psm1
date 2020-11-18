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
Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStoragePackagingConventions.psm1" )
Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageBagItDirectories.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Get-BaggedChildItemCandidates {
Param( $LiteralPath=$null, $Path=$null, [switch] $Zipped=$false )

    If ( $Zipped ) {
        If ( $LiteralPath -ne $null ) {
            $Zips = Get-ChildItem -LiteralPath $LiteralPath -File | Select-ZippedBags
        }
        Else {
            $Zips = Get-ChildItem -Path $Path -File | Select-ZippedBags
        }
        $Zips
    }

    If ( $LiteralPath -ne $null ) {
        $Dirs = Get-ChildItem -LiteralPath $LiteralPath -Directory
    }
    Else {
        $Dirs = Get-ChildItem -Path $Path -Directory
    }
    $Dirs
}

Function Get-BaggedChildItem {
Param( $LiteralPath=$null, $Path=$null, [switch] $Zipped=$false )

    Get-BaggedChildItemCandidates -LiteralPath:$LiteralPath -Path:$Path -Zipped:$Zipped |% {
        $Item = Get-FileObject -File $_
        If ( Test-BagItFormattedDirectory($Item) ) {
            $Item
        }
        ElseIf ( Test-ZippedBag $Item ) {
            $Item
        }
        ElseIf ( Test-IndexedDirectory -File $Item ) {
            # NOOP - Do not descend into an unbagged indexed directory
        }
        ElseIf ( Test-Path -LiteralPath $Item.FullName -PathType Container ) {
            # Descend to next directory level
            Get-BaggedChildItem -LiteralPath $Item.FullName
        }
    }

}

Function Get-UnbaggedChildItem {
Param( $LiteralPath=$null, $Path=$null )

    If ( $LiteralPath -ne $null ) {
        $Items = Get-ChildItem -LiteralPath $LiteralPath
    }
    ElseIf ( $Path -ne $null ) {
        $Items = Get-ChildItem -Path $Path
    }
    Else {
        Write-Verbose "Using PWD ${PWD} as directory."
        $Items = Get-ChildItem -LiteralPath $PWD
    }

    $Items | % {
        Write-Debug ( "Considering: " + $_.FullName )

        $Item = Get-FileObject -File $_

        If ( Test-BagItFormattedDirectory $Item ) {
            # NOOP
        }
        ElseIf ( Test-IndexedDirectory -File $Item ) {
            $Item
        }
        ElseIf ( Test-UnbaggedLooseFile -File $Item ) {
            $Item
        }
        ElseIf ( $Item -is [System.IO.DirectoryInfo] ) {
            Get-UnbaggedChildItem -LiteralPath $_.FullName
        }
    }

}

Export-ModuleMember -Function Get-BaggedChildItemCandidates
Export-ModuleMember -Function Get-BaggedChildItem
Export-ModuleMember -Function Get-UnbaggedChildItem
