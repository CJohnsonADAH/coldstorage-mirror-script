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
Import-Module $( My-Script-Directory -Command $MyInvocation.MyCommand -File "ColdStorageRepositoryLocations.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Test-IndexedDirectory {
Param( $File )

    $FileObject = Get-FileObject($File)
    $FilePath = $FileObject.FullName

    $result = $false
    if ( Test-Path -LiteralPath "${FilePath}" ) {
        $NewFilePath = "${FilePath}\index.html"
        $result = Test-Path -LiteralPath "${NewFilePath}"
    }
    
    $result
}

Function Test-BaggedIndexedDirectory {
Param( $File )

    $FileObject = Get-FileObject($File)
    $FilePath = $FileObject.FullName

    $result = $false
    if ( Test-BagItFormattedDirectory($File) ) {
        $payloadPath = "${FilePath}\data"
        $result = Test-IndexedDirectory($payloadPath)
    }
    
    $result
}

Function Test-ZippedBag {

Param ( $LiteralPath )

    $oFile = Get-FileObject -File $LiteralPath

    ( ( $oFile -ne $null ) -and ( $oFile.Name -like '*_md5_*.zip' ) )
}

Function Select-ZippedBags {

Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    $oFile = Get-FileObject -File $File
    If ( Test-ZippedBag -LiteralPath $oFile ) {
        $oFile
    }
}

End { }

}


#############################################################################################################
## LOOSE FILES: Typically found in ER Processed directory and DA directories. ###############################
#############################################################################################################

Function Test-LooseFile ( $File ) {
    
    $oFile = Get-FileObject($File)

    $result = $false
    If ( -Not ( $oFile -eq $null ) ) {
        If ( Test-Path -LiteralPath $oFile.FullName -PathType Leaf ) {
            $result = $true

            $Context = $oFile.Directory
            $sContext = $Context.FullName

            If ( Test-IndexedDirectory($sContext) ) {
                $result = $false
            }
            ElseIf  ( Test-BaggedIndexedDirectory($sContext) ) {
                $result = $false
            }
            ElseIf ( Test-ERInstanceDirectory($Context) ) {
                $result = $false
            }
            ElseIf ( Test-ZippedBag($oFile) ) {
                $result = $false
            }
            ElseIf ( Test-HiddenOrSystemFile($oFile) ) {
                $result = $false
            }
        }
    }
    
    $result
}

Function Get-PathToBaggedCopyOfLooseFile {
    Param (
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

Function Test-UnbaggedLooseFile {
Param ( $File )

    $oFile = Get-FileObject($File)
    
    $result = $false
    If ( -Not ( $oFile -eq $null ) ) {
        If ( Test-LooseFile($File) ) {
            $result = $true
            $bag = Get-BaggedCopyOfLooseFile -File $oFile
                       
            if ( $bag.Count -gt 0 ) {
                $result = $false
            }
        }
    }
    
    $result
}

Function Get-BaggedCopyOfLooseFile ( $File ) {
    $result = $null

    If ( Test-LooseFile($File) ) {
        $oFile = Get-FileObject($File)
        $Parent = $oFile.Directory
        $Wildcard = ( $oFile | Get-PathToBaggedCopyOfLooseFile -Wildcard )
        $match = ( Get-ChildItem -Directory $Parent | Select-BaggedCopiesOfLooseFiles -Wildcard $Wildcard | Select-BaggedCopyMatchedToLooseFile -File $oFile )

        if ( $match.Count -gt 0 ) {
            $result = $match
        }
    }

    $result
}

Function Test-BaggedCopyOfLooseFile {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $Context = $null, $DiffLevel=0 )

    $result = $false # innocent until proven guilty

    $oFile = Get-FileObject -File $File
    if ( Test-BagItFormattedDirectory( $oFile ) ) {
        $BagDir = $oFile.FullName
        $payload = ( Get-ChildItem -Force -LiteralPath "${BagDir}\data" )

        if ($payload.Count -eq 1 -and ( Test-Path -LiteralPath $payload.FullName -PathType Leaf ) ) {
            $result = $true
            If ( $DiffLevel -gt 0 ) {
                $sCounterpart = ( "{0}\{1}" -f ( $File.Parent.FullName, $payload.Name ) )
                $Counterpart = ( Get-FileObject -File $sCounterpart )

                If ( $Counterpart -eq $null ) {
                    $result = $false
                }
                ElseIf ( Test-DifferentFileContent -From $payload -To $Counterpart -DiffLevel $DiffLevel ) {
                    $result = $false
                }

            }

        }
    }
    
    $result
}

Function Select-BaggedCopiesOfLooseFiles {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [string] $Wildcard = '*' )

Begin { }

Process {
    If ( $File.Name -Like $Wildcard ) {
        If ( Test-BaggedCopyOfLooseFile($File) ) {
            $File
        }
    }
}

End { }
}

Function Select-BaggedCopyMatchedToLooseFile {
Param ( [Parameter(ValueFromPipeline=$true)] $Bag, $File, $DiffLevel=0 )

Begin { }

Process {
    If ( Test-LooseFile($File) ) {
        $oBag = Get-FileObject -File $Bag
        $Payload = ( Get-Item -Force -LiteralPath $oBag.FullName | Select-BagItPayload )
        If ( Test-BaggedCopyOfLooseFile($Bag) ) {
            If ( $Payload.Count -eq 1 ) {
                $oFile = Get-FileObject -File $File
                
                $Mismatched = $false
                If ( $Payload.Name -ne $oFile.Name ) {
                    $Mismatched = $true
                }
                ElseIf ( $Payload.Length -ne $oFile.Length ) {
                    $Mismatched = $true
                }
                ElseIf ( $DiffLevel -gt 0 ) {
                    If ( Test-DifferentFileContent -From $Payload -To $File -DiffLevel $DiffLevel ) {
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

Function Get-ChildItemPackages {

Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Recurse=$false, [switch] $CheckZipped=$false, [switch] $ShowWarnings=$false )

    Begin { }

    Process {
        $oFile = ( Get-FileObject -File $File )
        Write-Debug ( "Get-ChildItemPackages({0} -> {1})" -f $File, $oFile.Name )
        
        If ( $oFile -eq $null ) {
            Write-Error ( "No such item: {0}" -f $File )
        }
        Else {

        Get-ChildItem -LiteralPath $oFile.FullName |% {

            If ( ( $_.Name -eq "." ) -or ( $_.Name -eq ".." ) ) {
                Continue
            }

            $bBagged = ( Test-BagItFormattedDirectory -File $_ )
            $aZipped = $false
            $aContents = @( )
            $aWarnings = @( )
            If ( $_ | Test-ColdStorageRepositoryPropsDirectory ) {
                $aWarnings += @( "SKIPPED -- PROPS DIRECTORY: {0}" -f $_.FullName )
            }
            ElseIf ( Test-ZippedBag -LiteralPath $_.FullName ) {
                $aWarnings += @( "SKIPPED -- ZIPPED BAG: {0}" -f $_.FullName )
            }
            ElseIf ( Test-ERInstanceDirectory -File $_ ) {
                $aContents = @( $_ ) + @( Get-ChildItem -Force -Recurse -LiteralPath $_.FullName )
                If ( $bBagged -and $CheckZipped ) {
                    $aZipped = ( $_ | Get-ZippedBagOfUnzippedBag )
                }
            }
            ElseIf ( Test-IndexedDirectory -File $_ ) {
                $aContents = @( $_ ) + @( Get-ChildItem -Force -Recurse -LiteralPath $_.FullName )
            }
            ElseIf ( Test-BaggedCopyOfLooseFile -File $_ -DiffLevel 1 ) {
                $aWarnings += @( "SKIPPED -- BAGGED COPY OF LOOSE FILE: {0}" -f $_.FullName )
            }
            ElseIf ( Test-BaggedIndexedDirectory -File $_ ) {
                $aContents = ( @( $_ ) + @( Get-ChildItem -Force -Recurse -LiteralPath $_.FullName ) )
                If ( $bBagged -and $CheckZipped ) {
                    $aZipped = ( $_ | Get-ZippedBagOfUnzippedBag )
                }
            }
            ElseIf ( Test-BagItFormattedDirectory -File $_ ) {
                $aContents = ( @( $_ ) + @( Get-ChildItem -Force -Recurse -LiteralPath $_.FullName ) )
                If ( $bBagged -and $CheckZipped ) {
                    $aZipped = ( $_ | Get-ZippedBagOfUnzippedBag )
                }
            }
            ElseIf ( Test-LooseFile -File $_ ) {
                $oBaggedCopy = ( Get-BaggedCopyOfLooseFile -File $_ )
                $bBagged = $( If ( $oBaggedCopy ) { $true } Else { $false } )
                If ( $bBagged -and $CheckZipped ) {
                    $aZipped = ( $oBaggedCopy | Get-ZippedBagOfUnzippedBag )
                }
                $aContents = @( $_ )
            }
            ElseIf ( $Recurse -and ( Test-Path -LiteralPath $_.FullName -PathType Container ) ) {
                ( "RECURSE INTO DIRECTORY: {0}" -f $_.FullName ) | Write-Verbose
                $aContents = @( )
                Get-ChildItemPackages -File $_.FullName -Recurse:$Recurse -CheckZipped:$CheckZipped -ShowWarnings:$ShowWarnings
            }
            Else {
                $aContents = @( )
                $aWarnings += @( "SKIPPED -- MISC: {0}" -f $_.FullName )
            }

            If ( $ShowWarnings ) {
                $aWarnings | Write-Warning
            }

            If ( $aContents.Count -gt 0 ) {
                $Package = $_
                $mContents = ( $aContents | Measure-Object -Sum Length )
                #$mContents = ( $aContents |% { $_ | Add-Member -MemberType NoteProperty -Name "CSFileSize" -Value ( 0 + ( $_ | Select Length).Length ) } | Measure-Object -Sum CSFileSize )
                
                Add-Member -InputObject $Package -MemberType NoteProperty -Name "CSPackageBagged" -Value $bBagged
                Add-Member -InputObject $Package -MemberType NoteProperty -Name "CSPackageContents" -Value $mContents.Count
                Add-Member -InputObject $Package -MemberType NoteProperty -Name "CSPackageFileSize" -Value $mContents.Sum
                If ( $aZipped -ne $false ) {
                    Add-Member -InputObject $Package -MemberType NoteProperty -Name "CSPackageZip" -Value $aZipped
                }
                $Package | Write-Output
            }

        }

        }

    }

    End { }

}


#############################################################################################################
## ER INSTANCE DIRECTORIES: Typically found in ER Unprocessed directory #####################################
#############################################################################################################

Function Test-ERInstanceDirectory {
Param ( $File )

    $result = $false # innocent until proven guilty

    $LiteralPath = Get-FileLiteralPath -File $File
    If ( $LiteralPath -ne $null ) {
        If ( Test-Path -LiteralPath $LiteralPath -PathType Container ) {
            $BaseName = $File.Name
            $result = ($BaseName -match "^[A-Za-z0-9]{2,3}_ER")
        }
    }
    
    $result
}

Function Select-ERInstanceDirectories {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process { if ( Test-ERInstanceDirectory($File) ) { $File } }

End { }
}

Function Get-ERInstanceData {
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

    $ERMeta
}

End { }
}

Export-ModuleMember -Function Test-IndexedDirectory
Export-ModuleMember -Function Test-BaggedIndexedDirectory
Export-ModuleMember -Function Test-ZippedBag
Export-ModuleMember -Function Select-ZippedBags
Export-ModuleMember -Function Test-LooseFile
Export-ModuleMember -Function Test-UnbaggedLooseFile
Export-ModuleMember -Function Get-PathToBaggedCopyOfLooseFile
Export-ModuleMember -Function Get-BaggedCopyOfLooseFile
Export-ModuleMember -Function Test-BaggedCopyOfLooseFile
Export-ModuleMember -Function Select-BaggedCopiesOfLooseFiles
Export-ModuleMember -Function Select-BaggedCopyMatchedToLooseFile
Export-ModuleMember -Function Test-ERInstanceDirectory
Export-ModuleMember -Function Select-ERInstanceDirectories
Export-ModuleMember -Function Get-ERInstanceData
Export-ModuleMember -Function Get-ChildItemPackages