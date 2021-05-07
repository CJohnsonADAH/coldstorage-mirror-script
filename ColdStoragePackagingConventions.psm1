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

$global:gPackagingConventionsCmd = $MyInvocation.MyCommand

Import-Module $( My-Script-Directory -Command $global:gPackagingConventionsCmd -File "ColdStorageFiles.psm1" )
Import-Module $( My-Script-Directory -Command $global:gPackagingConventionsCmd -File "ColdStorageScanFilesOK.psm1" )
Import-Module $( My-Script-Directory -Command $global:gPackagingConventionsCmd -File "ColdStorageBagItDirectories.psm1" )
Import-Module $( My-Script-Directory -Command $global:gPackagingConventionsCmd -File "ColdStorageRepositoryLocations.psm1" )

#############################################################################################################
## PUBLIC FUNCTIONS: PIPELINE FOR PACKAGING #################################################################
#############################################################################################################

Function Select-CSPackagesOK {

    [Cmdletbinding()]

param (
    [Switch]
    $Quiet,

    [String]
    $Exclude="^$",

    [Switch]
    $Force=$false,

    [Switch]
    $Rebag=$false,

    [Int[]]
    $OKCodes=@( 0 ),

    [Int[]]
    $ContinueCodes=@( 0 ),

    [String[]]
    $Skip=@( ),

    [Switch]
    $ShowWarnings=$false,

    [Parameter(ValueFromPipeline=$true)]
    $File
)

    Begin {
        if ( $Exclude.Length -eq 0 ) {
            $Exclude = "^$"
        }
    }

    Process {
        $ToScan = @()

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
            #FIXME: Write-Bagged-Item-Notice -FileName $File.Name -Item:$File -Message "BagIt formatted directory" -ERCode:$ERCode -Verbose -Line ( Get-CurrentLine )
            
            # Pass it thru iff we have requested rebagging
            If ( $Rebag ) { $ToScan += , $File }
        }
        ElseIf ( Test-ERInstanceDirectory($File) ) {
            If ( -not ( $BaseName -match $Exclude ) ) {
                $ERMeta = ( $File | Get-ERInstanceData )
                $ERCode = $ERMeta.ERCode

                # chdir $DirName

                if ( Test-BagItFormattedDirectory($File) ) {
                    # FIXME: Write-Bagged-Item-Notice -FileName $DirName -Item:$File -ERCode $ERCode -Quiet:$Quiet -Line ( Get-CurrentLine )
                }
                else {
                    # FIXME: Write-Unbagged-Item-Notice -FileName $DirName -ERCode $ERCode -Quiet:$Quiet -Verbose -Line ( Get-CurrentLine )
                    $ToScan += , $File
                }
            }
            Else {
                # FIXME: Write-Bagged-Item-Notice -Status "SKIPPED" -FileName $DirName -Item:$File -ERCode $ERCode -Quiet:$Quiet -Line ( Get-CurrentLine )
            }

            # chdir $Anchor
        }
        ElseIf ( Test-IndexedDirectory($File) ) {
            # FIXME: Write-Unbagged-Item-Notice -FileName $File.Name -Message "indexed directory. Scan it, bag it and tag it." -Verbose -Line ( Get-CurrentLine )
            $ToScan += , $File
        }
        Else {
            Get-ChildItem -File -LiteralPath $File.FullName | ForEach {
                If ( Test-UnbaggedLooseFile($_) ) {
                    $LooseFile = $_.Name
                    # FIXME: Write-Unbagged-Item-Notice -FileName $File.Name -Message "loose file. Scan it, bag it and tag it." -Verbose -Line ( Get-CurrentLine )

                    $ToScan += , $_
                }
                Else {
                    # FIXME: Write-Bagged-Item-Notice -FileName $File.Name -Item:$File -Message "loose file -- already bagged." -Verbose -Line ( Get-CurrentLine )
                }
            }
        }
        $ToScan | Select-CSFilesOK -Skip:$Skip -OKCodes:$OKCodes -ContinueCodes:$ContinueCodes -ShowWarnings:$ShowWarnings | Write-Output
    }

    End {
    }
}

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

Function Get-ItemPackageZippedBag {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Recurse )

    Begin { }

    Process {
        $oFile = Get-FileObject($File)
        
        # 1. Does this have a Package property .CSPackageZip? If so, return that.
        $oZipNotes = ( $oFile | Get-Member -MemberType NoteProperty -Name "CSPackageZip" )
        If ( $oZipNotes ) {
            $oZipNotes |% { $PropName = $_.Name ; $oFile.${PropName} }
        }

        # 2. Is this a direct reference to a zipped package? If so, return this.
        ElseIf ( Test-ZippedBag -LiteralPath $oFile ) {
            $oFile
        }

        # 3. Is this a container of a bunch of zipped packages? If so, return those packages.
        ElseIf ( $oFile | Test-ZippedBagsContainer ) {
            ( Get-ChildItem -LiteralPath $oFile.FullName -Filter "*.zip" )
        }

        # 4. Try to get packaging information on this item, recursing into child items if requested.
        Else {
            $oPackage = ( $oFile | Get-ItemPackage -Ascend -CheckZipped )
            If ( $oPackage.Count -gt 0 ) {
                $oPackage | Get-ItemPackageZippedBag
            }
            ElseIf ( $Recurse ) {
                $oFile | Get-ChildItemPackages -Recurse:$Recurse -CheckZipped | Get-ItemPackageZippedBag
            }
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

Function Undo-CSBagPackage {
Param ( [Parameter(ValueFromPipeline=$true)] $Package )

    Begin { }

    Process {
        $oFile = Get-FileObject($Package)
        If ( $oFile ) {

            If ( Test-BagItFormattedDirectory -File $oFile ) {
                
                $PayloadDirectory = ( $oFile | Select-BagItPayloadDirectory )
                If ( Test-BaggedCopyOfLooseFile -File $oFile -DiffLevel 2 ) {
                    Remove-Item -LiteralPath $oFile.FullName -Recurse -Force
                }
                Else {
                    $Dates = ( Get-ChildItem -LiteralPath . |% { $_.CreationTime.ToString("yyyyMMdd") } ) | Sort-Object -Descending
                    $sDate = ($Dates[0])
                    $OldManifest = ( $oFile.FullName | Join-Path -ChildPath "bagged-${sDate}" )
                    $oManifest = ( New-Item -Path $OldManifest -ItemType Directory )

                    Get-ChildItem -LiteralPath $oFile |% {
                        $BagItem = $_
                        If ( $BagItem.FullName -eq $PayloadDirectory.FullName ) {
                            # 1st pass - skip
                        }
                        ElseIf ( $BagItem.FullName -eq $oManifest.FullName ) {
                            # 1st pass - mark Hidden
                            $BagItem.Attributes = ( $BagItem.Attributes -bor [System.IO.FileAttributes]::Hidden )
                        }
                        Else {
                            # 1st pass - move to old manifest directory
                            Move-Item -LiteralPath $_.FullName -Destination $oManifest.FullName
                        }

                    }

                    Get-ChildItem -LiteralPath $oFile |% {
                        $BagItem = $_
                        If ( $BagItem.FullName -eq $PayloadDirectory.FullName ) {
                            # 2nd pass - empty payload contents into parent directory and remove data directory
                            Get-ChildItem -LiteralPath $BagItem.FullName |% {
                                Move-Item -LiteralPath $_.FullName -Destination $oFile
                            }
                            Remove-Item -LiteralPath $BagItem.FullName
                        }
                    }

                }

            }
            Else {

                Write-Warning ( "Undo-CSBagPackage: Not a BagIt-formatted directory: {0}" -f $oFile.FullName )

            }

        }
        Else {
            Write-Warning ( "Undo-CSBagPackage: Unrecognized file: {0}" -f $Package )
        }

    }

    End { }
}


Function Get-ItemPackage {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Recurse=$false, [switch] $Ascend=$false, $AscendTop=$null, [switch] $CheckZipped=$false, [switch] $ShowWarnings=$false )

    Begin { }

    Process {
        $File = Get-FileObject($File)
        Write-Debug ( "Entered Get-ItemPackage: {0} -Recurse:{1} -Ascend:{2} -AscendTop:{3} -CheckZipped:{4} -ShowWarnings:{5}" -f $File.FullName, $Recurse, $Ascend, $AscendTop, $CheckZipped, $ShowWarnings )

        If ( ( $File.Name -eq "." ) -or ( $File.Name -eq ".." ) ) {
            Continue
        }

        $bBagged = ( Test-BagItFormattedDirectory -File $File )
        $aZipped = $false
        $aContents = @( )
        $aWarnings = @( )
        If ( $File | Test-ColdStorageRepositoryPropsDirectory ) {
            $aWarnings += @( "SKIPPED -- PROPS DIRECTORY: {0}" -f $File.FullName )
        }
        ElseIf ( Test-ZippedBag -LiteralPath $File.FullName ) {
            $aWarnings += @( "SKIPPED -- ZIPPED BAG: {0}" -f $File.FullName )
        }
        ElseIf ( Test-ERInstanceDirectory -File $File ) {
            $aContents = @( $File ) + @( Get-ChildItem -Force -Recurse -LiteralPath $File.FullName )
            If ( $bBagged -and $CheckZipped ) {
                $aZipped = ( $File | Get-ZippedBagOfUnzippedBag )
            }
        }
        ElseIf ( Test-IndexedDirectory -File $File ) {
            $aContents = @( $File ) + @( Get-ChildItem -Force -Recurse -LiteralPath $File.FullName )
        }
        ElseIf ( Test-BaggedCopyOfLooseFile -File $File -DiffLevel 1 ) {
            $aWarnings += @( "SKIPPED -- BAGGED COPY OF LOOSE FILE: {0}" -f $File.FullName )
        }
        ElseIf ( Test-BaggedIndexedDirectory -File $File ) {
            $aContents = ( @( $File ) + @( Get-ChildItem -Force -Recurse -LiteralPath $File.FullName ) )
            If ( $bBagged -and $CheckZipped ) {
                $aZipped = ( $File | Get-ZippedBagOfUnzippedBag )
            }
        }
        ElseIf ( Test-BagItFormattedDirectory -File $File ) {
            $aContents = ( @( $File ) + @( Get-ChildItem -Force -Recurse -LiteralPath $File.FullName ) )
            If ( $bBagged -and $CheckZipped ) {
                $aZipped = ( $File | Get-ZippedBagOfUnzippedBag )
            }
        }
        ElseIf ( Test-LooseFile -File $File ) {
            $oBaggedCopy = ( Get-BaggedCopyOfLooseFile -File $File )
            $bBagged = $( If ( $oBaggedCopy ) { $true } Else { $false } )
            If ( $bBagged -and $CheckZipped ) {
                $aZipped = ( $oBaggedCopy | Get-ZippedBagOfUnzippedBag )
            }
            $aContents = @( $File )
        }
        ElseIf ( $Recurse -and ( Test-Path -LiteralPath $File.FullName -PathType Container ) ) {
            ( "RECURSE INTO DIRECTORY: {0}" -f $File.FullName ) | Write-Verbose
            $aContents = @( )
            Get-ChildItemPackages -File $File.FullName -Recurse:$Recurse -CheckZipped:$CheckZipped -ShowWarnings:$ShowWarnings
        }
        ElseIf ( $Ascend ) {
            $aWarnings += @( "RECURSE -- ASCEND FROM: {0}" -f $File.FullName )
            $Parent = ( $File | Get-ItemFileSystemParent )

            If ( $Parent ) {                
                $Top = $( If ( $AscendTop ) { $AscendTop } Else { $File | Get-FileRepositoryLocation } )
                ( "ASCEND UP TO DIRECTORY: {0} -> {1} | {2}" -f $File.FullName,$Parent.FullName,$Top.FullName ) | Write-Verbose
                If ( $Parent.FullName -ne $Top.FullName ) {
                    $Parent | Get-ItemPackage -Ascend:$Ascend -AscendTop:$Top -CheckZipped:$CheckZipped -ShowWarnings:$ShowWarnings
                }
            }
        }
        Else {
            $aContents = @( )
            $aWarnings += @( "SKIPPED -- MISC: {0}" -f $File.FullName )
        }

        If ( $ShowWarnings ) {
            $aWarnings | Write-Warning
        }

        If ( $aContents.Count -gt 0 ) {
            $Package = $File
            $mContents = ( $aContents | Measure-Object -Sum Length )
            #$mContents = ( $aContents |% { $File | Add-Member -MemberType NoteProperty -Name "CSFileSize" -Value ( 0 + ( $File | Select Length).Length ) } | Measure-Object -Sum CSFileSize )
                
            Add-Member -InputObject $Package -MemberType NoteProperty -Name "CSPackageBagged" -Value $bBagged -Force
            Add-Member -InputObject $Package -MemberType NoteProperty -Name "CSPackageContents" -Value $mContents.Count -Force
            Add-Member -InputObject $Package -MemberType NoteProperty -Name "CSPackageFileSize" -Value $mContents.Sum -Force
            If ( $aZipped -ne $false ) {
                Add-Member -InputObject $Package -MemberType NoteProperty -Name "CSPackageZip" -Value $aZipped -Force
            }
            $Package | Write-Output
        }

        Write-Debug ( "Exited Get-ItemPackage: {0} -Recurse:{1} -Ascend:{2} -AscendTop:{3} -CheckZipped:{4} -ShowWarnings:{5}" -f $File.FullName, $Recurse, $Ascend, $AscendTop, $CheckZipped, $ShowWarnings )

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

            Get-ChildItem -LiteralPath $oFile.FullName | Get-ItemPackage -Recurse:$Recurse -CheckZipped:$CheckZipped -ShowWarnings:$ShowWarnings

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


#############################################################################################################
## BUNDLED DIRECTORIES: index.html FOR BOUND SUBDIRECTORIES #################################################
#############################################################################################################

Add-Type -Assembly System.Web

Function ConvertTo-HTMLDocument {
Param ( [Parameter(ValueFromPipeline=$true)] $BodyBlock, [String] $Title )

    Begin {
        $NL = [Environment]::NewLine
        $DocType = "<!DOCTYPE html>"

        $Soup = @()

        $Soup += , $DocType
        $Soup += , "<html>"
        $Soup += , "<head>"
        $Soup += , ( "<title>{0}</title>" -f $Title )
        $Soup += , "</head>"

        $Soup += , "<body>"
        $Soup += , ( "<h1>{0}</h1>" -f $Title )
    }

    Process {
        $Soup += , $BodyBlock
    }

    End {
        $Soup += , "</body>"
        $Soup += , "</html>"

        ( $Soup -join "${NL}" ) | Write-Output
    }

}

Function ConvertTo-HTMLList {
Param ( [Parameter(ValueFromPipeline=$true)] $LI, $ListTag="ul", $ItemTag="li" )

    Begin {
        $ListTagElement = ( $ListTag.Trim("<>") -split "\s+" | Select-Object -First 1 )
        $OpenList=( "<{0}>" -f $ListTag );
        $CloseList = ( "</{0}>" -f $ListTagElement )

        $ItemTagElement = ( $ItemTag.Trim("<>") -split "\s+" | Select-Object -First 1 )
        $OpenItem = ( "  <{0}>" -f $ItemTag )
        $CloseItem = ( "</{0}>" -f $ItemTagElement )

        $OpenList | Write-Output
    }

    Process {
        ( '{0}{1}{2}' -f $OpenItem,$LI,$CloseItem ) | Write-Output
    }

    End {
        $CloseList | Write-Output
    }

}

Function ConvertTo-HTMLLink {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $RelativeTo, [switch] $RelativeHref=$false, [String] $Tag='<a href="{0}">{1}</a>' )

    Begin { Push-Location; Set-Location $RelativeTo }

    Process {
        $URL = $File.FileURI

        $FileName = ($File | Resolve-Path -Relative)
        $FileBaseName = ( $File.Name )
        $FileSlug = ( $File.BaseName )

        If ( $RelativeHref ) {
            $RelativeURL = (($FileName.Split("\") | % { [URI]::EscapeDataString($_) }) -join "/")
            $HREF = [System.Web.HttpUtility]::HtmlEncode($RelativeURL)
        }
        Else {
            $HREF = [System.Web.HttpUtility]::HtmlEncode($URL)
        }

        $TEXT = [System.Web.HttpUtility]::HtmlEncode($FileName)

        ( $Tag -f $HREF, $TEXT, $FileBaseName, $FileSlug ) | Write-Output
    }

    End { Pop-Location }

}

Function Add-FileURI {
Param( [Parameter(ValueFromPipeline=$true)] $File, $RelativeTo=$null, [switch] $PassThru=$false )

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
        If ( $PassThru ) {
            $File
        }
    }

    End { }

}

Function Add-IndexHTML {
Param( [Parameter(ValueFromPipeline=$true)] $Directory, [switch] $RelativeHref=$false, [switch] $Force=$false, [string] $Context=$null )

    Begin { $MyCommand = $MyInvocation.MyCommand ; $sContext = $( If ( $Context ) { $Context } Else { $MyCommand } ) }

    Process {
        if ( $Directory -eq $null ) {
            $Path = ( Get-Location )
        } else {
            $Path = ( $Directory )
        }

        If ( ( -Not $Force ) -And ( Test-MirrorMatchedItem -File "${Path}" -Reflection ) ) {
            $originalLocation = ( "${Path}" | Get-MirrorMatchedItem -Original )
            ( "[{0}] This is a mirror-image location. Setting Location to: {1}." -f $sContext,$originalLocation ) | Write-Warning
            $originalLocation | Add-IndexHTML -RelativeHref:$RelativeHref -Force:$Force -Context:$Context

            $originalIndexHTML = ( Get-Item -Force -LiteralPath ( $originalLocation | Join-Path -ChildPath "index.html" ) )
            If ( $originalIndexHTML ) {
                If ( Test-Path -LiteralPath "${Path}" -PathType Container ) {
                    ( "[{0}] Copying HTML from {1} to {2}." -f $sContext,$originalIndexHTML,$Path ) | Write-Warning
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
            
                Get-ChildItem -Recurse -LiteralPath "${UNC}" `
                | Get-UNCPathResolved -ReturnObject `
                | Add-FileURI -PassThru `
                | Sort-Object -Property FullName `
                | ConvertTo-HTMLLink -RelativeTo $UNC -RelativeHref:${RelativeHref} `
                | ConvertTo-HTMLList `
                | ConvertTo-HTMLDocument -Title ( "Contents of: {0}" -f [System.Web.HttpUtility]::HtmlEncode($UNC) ) `
                | Out-File -FilePath $indexHtmlPath -NoClobber:(-Not $Force) -Encoding utf8

            }
            Else {
                ( "[{0}] index.html already exists in {1}. To force index.html to be regenerated, use -Force flag." -f $sContext,$Directory ) | Write-Warning
            }
        }
    }

    End { }

}

Export-ModuleMember -Function Select-CSPackagesOK
Export-ModuleMember -Function Test-IndexedDirectory
Export-ModuleMember -Function Test-BaggedIndexedDirectory
Export-ModuleMember -Function Test-ZippedBag
Export-ModuleMember -Function Select-ZippedBags
Export-ModuleMember -Function Get-ItemPackageZippedBag
Export-ModuleMember -Function Test-LooseFile
Export-ModuleMember -Function Test-UnbaggedLooseFile
Export-ModuleMember -Function Get-PathToBaggedCopyOfLooseFile
Export-ModuleMember -Function Get-BaggedCopyOfLooseFile
Export-ModuleMember -Function Test-BaggedCopyOfLooseFile
Export-ModuleMember -Function Select-BaggedCopiesOfLooseFiles
Export-ModuleMember -Function Select-BaggedCopyMatchedToLooseFile
Export-ModuleMember -Function Undo-CSBagPackage
Export-ModuleMember -Function Test-ERInstanceDirectory
Export-ModuleMember -Function Select-ERInstanceDirectories
Export-ModuleMember -Function Get-ERInstanceData
Export-ModuleMember -Function Get-ItemPackage
Export-ModuleMember -Function Get-ChildItemPackages
Export-ModuleMember -Function ConvertTo-HTMLDocument
Export-ModuleMember -Function ConvertTo-HTMLList
Export-ModuleMember -Function ConvertTo-HTMLLink
Export-ModuleMember -Function Add-FileURI
Export-ModuleMember -Function Add-IndexHTML
