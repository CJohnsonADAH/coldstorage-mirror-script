#############################################################################################################
## DEPENDENCIES #############################################################################################
#############################################################################################################

Function Get-CSScriptDirectory {
Param ( $File=$null )
    $ScriptPath = ( Split-Path -Parent $PSCommandPath )
    If ( $File -ne $null ) { $ScriptPath = ( Join-Path "${ScriptPath}" -ChildPath "${File}" ) }
    ( Get-Item -Force -LiteralPath "${ScriptPath}" )
}

$global:gPackagingConventionsCmd = $MyInvocation.MyCommand

    $modSource = ( $global:gPackagingConventionsCmd.Source | Get-Item -Force )
    $modPath = ( $modSource.Directory | Get-Item -Force )

# Depdencies - Script
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath:"ColdStorageData.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath:"ColdStorageFiles.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath:"ColdStorageScanFilesOK.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath:"ColdStorageBagItDirectories.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath:"ColdStorageRepositoryLocations.psm1" )
Import-Module -Verbose:$false $( $modPath.FullName | Join-Path -ChildPath:"ColdStorageZipArchives.psm1" )

Function Get-CSItemPackageProgressId { 909 }

#############################################################################################################
## PUBLIC FUNCTIONS: PIPELINE FOR PACKAGING #################################################################
#############################################################################################################

Function Select-CSPackagesOKOrApproved {

    [CmdletBinding()]

Param ( [Parameter(ValueFromPipeline=$true)] $Item, [Switch] $Quiet, [Switch] $Force, [Switch] $Rebag, $Skip )

    Begin { }

    Process {

        $Item | Select-CSPackagesOK -Quiet:$Quiet -Force:$Force -Rebag:$Rebag -ContinueCodes:@( 0..255 ) -Skip:$Skip -ShowWarnings | Select-WhereWeShallContinue -Force:$Force

    }

    End { }

}

Function Select-CSPackagesOK {

    [Cmdletbinding()]

param (
    [Switch]
    $Quiet,

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

    Begin { }

    Process {

        If ( -Not $File ) {
            Return
        }

        $ToScan = @()

        $Anchor = $PWD

        $oFile = Get-FileObject($File)
        $DirName = $oFile.FullName

        If ( Test-ERInstanceDirectory($File) ) {
            $ERMeta = ( $oFile | Get-ERInstanceData )
            $ERCode = $ERMeta.ERCode
        }
        Else {
            $ERCode = $null
        }

        If ( Test-BagItFormattedDirectory($oFile) ) {
            #FIXME: Write-Bagged-Item-Notice -FileName $File.Name -Item:$File -Message "BagIt formatted directory" -ERCode:$ERCode -Verbose -Line ( Get-CurrentLine )
            
            # Pass it thru iff we have requested rebagging OR we have invoked with -Force
            If ( $Rebag -or $Force ) { $ToScan += , $oFile }
        }
        ElseIf ( Test-ERInstanceDirectory($oFile) ) {
            If ( $Rebag -or $Force ) {
                $ToScan += , $oFile
            }
            ElseIf ( Test-BagItFormattedDirectory($oFile) ) {
                # FIXME: Write-Bagged-Item-Notice -FileName $DirName -Item:$File -ERCode $ERCode -Quiet:$Quiet -Line ( Get-CurrentLine )
            }
            Else {
                # FIXME: Write-Unbagged-Item-Notice -FileName $DirName -ERCode $ERCode -Quiet:$Quiet -Verbose -Line ( Get-CurrentLine )
                $ToScan += , ( $oFile | Add-Member -MemberType NoteProperty -Name ERMeta -Value $ERMeta -PassThru )
            }
        }
        ElseIf ( Test-IndexedDirectory($oFile) ) {
            # FIXME: Write-Unbagged-Item-Notice -FileName $File.Name -Message "indexed directory. Scan it, bag it and tag it." -Verbose -Line ( Get-CurrentLine )
            $ToScan += , $File
        }
        Else {
            Get-ChildItem -File -LiteralPath $oFile.FullName | ForEach {
                If ( $Rebag -or $Force ) {
                    $ToScan += , $_
                }
                ElseIf ( Test-UnbaggedLooseFile($_) ) {
                    $LooseFile = $_.Name
                    # FIXME: Write-Unbagged-Item-Notice -FileName $File.Name -Message "loose file. Scan it, bag it and tag it." -Verbose -Line ( Get-CurrentLine )

                    $ToScan += , $_
                }
                Else {
                    # FIXME: Write-Bagged-Item-Notice -FileName $File.Name -Item:$File -Message "loose file -- already bagged." -Verbose -Line ( Get-CurrentLine )
                }
            }
        }
        
        $ToScan | Select-CSFilesOK -Skip:$Skip -OKCodes:$OKCodes -ContinueCodes:$ContinueCodes -ShowWarnings:$ShowWarnings | Write-Output # -Verbose:$Verbose 

    }

    End { }

}

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Test-IndexedDirectory {
Param( $File, [switch] $UnbaggedOnly=$false )

    $FileObject = Get-FileObject($File)
    $FilePath = $FileObject.FullName

    $result = $false
    If ( Test-Path -LiteralPath "${FilePath}" ) {
        $NewFilePath = ( Join-Path "${FilePath}" -ChildPath "index.html" )
        $result = ( Test-Path -LiteralPath "${NewFilePath}" )
    }
    
    If ( $UnbaggedOnly ) {
        $hasBagItPayloadName = ( $FileObject.Name -eq "data" )
        $result = ( $result -and ( -Not ( $hasBagItPayloadName -and ( Test-BaggedIndexedDirectory -File:$FileObject.Parent ) ) ) )
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
Param (
    [Parameter(ValueFromPipeline=$true)] $File,
    [switch] $Recurse,
    [switch] $Force=$false,
    [switch] $ReturnContainer=$false,
    [switch] $Profile=$false
)

    Begin {
        $Result = @( )
        If ( $Profile ) { $tN = @( Get-Date ) }
    }

    Process {

        If ( $Profile ) { $tN += , ( Get-Date ) }

        $oJustZippedNotes = ( $File | Get-Member -MemberType NoteProperty -Name "Zip" )
        If ( $oJustZippedNotes ) {
            $oFile = Get-FileObject( $oJustZippedNotes |% { $PropName = $_.Name ; $File.${PropName} } )
        }
        Else {
            $oFile = Get-FileObject($File)
        }

        If ( $Profile ) { $tN += , ( Get-Date ) }

        # 1. Does this have a Package property .CSPackageZip? If so, return that.
        $oZipNotes = ( $oFile | Get-Member -MemberType NoteProperty -Name "CSPackageZip" )
        If ( $oZipNotes ) {
            $Result += , ( Get-FileObject( $oZipNotes |% { $PropName = $_.Name ; $oFile.${PropName} } ) )
        }

        # 2. Is this a direct reference to a zipped package? If so, return this.
        ElseIf ( Test-ZippedBag -LiteralPath $oFile ) {
            $Result += , $oFile
        }

        # 3. Is this a container of a bunch of zipped packages? If so, return those packages.
        ElseIf ( $oFile | Test-ZippedBagsContainer ) {
            $Result += ( Get-ChildItem -LiteralPath $oFile.FullName -Filter "*.zip" |? { Test-ZippedBag -LiteralPath $_ } )
        }

        # 4. Exclude items in the zipped bags container if they didn't pass Test-ZippedBag
        ElseIf ( $oFile | Get-ItemFileSystemLocation | Test-ZippedBagsContainer ) {
            # NOOP - We should not do anything with items in the zipped bags container that failed other tests.
        }

        # 5. If we have previously checked this package for zips, but earlier steps turned up nothing, there may be no ZIP
        ElseIf ( ( $oFile | Get-Member -Name:CSPackageCheckedZipped ) -and ( $oFile.CSPackageCheckedZipped ) ) {
            # NOOP - We previously checked this package for zips, but earlier steps turned up no zips
        }

        # 6. Try to get packaging information on this item, recursing into child items if requested.
        Else {

            $oPackage = ( $oFile | Get-ItemPackage -Ascend -CheckZipped )
            If ( $oPackage.Count -gt 0 ) {
                $oPackageZippedBag = ( $oPackage | Get-ItemPackageZippedBag )

                If ( $oPackageZippedBag.Count -eq 0 ) {
                    If ( $Force ) {
                        "[Get-ItemPackageZippedBag -Force] We should CREATE a zipped bag..." | Write-Warning
                        $CSZipPackages = $( Get-CSScriptDirectory -File "coldstorage-zip-packages.ps1" )
                        $Zip = ( $oPackage | & "${CSZipPackages}" )
                        If ( $Zip ) {
                            $Zip | Get-ItemPackageZippedBag | Write-Output
                        }
                        #$oPackage 
                    }
                }

                $Result += $oPackageZippedBag

            }
            ElseIf ( $Recurse ) {
                $Result += ( $oFile | Get-ChildItemPackages -Recurse:$Recurse -CheckZipped | Get-ItemPackageZippedBag )
            }
        }

        If ( $Profile ) { $tN += , ( Get-Date ) }

        If ( $Result.Count -gt 0 ) {
            If ( -Not $ReturnContainer ) {
                $Result | Write-Output
                $Result = @( )
            }
        }

    }

    End {
        If ( $Profile ) { $tN += , ( Get-Date ) }

        If ( $Result.Count -gt 0 ) {
            $Result | Select-ZippedBagsContainers | Write-Output
        }

    }

}

Function Select-ZippedBagsContainers {
Param ( [Parameter(ValueFromPipeline=$true)] $Zip )

    Begin {
        $Containers = @( )
    }

    Process {
        $oZip = Get-FileObject($Zip)
        $Containers += , $oZip.Directory
    }

    End {
        $Containers | Sort-Object -Unique -Property FullName | Write-Output
    }

}

#############################################################################################################
## LOOSE FILES: Typically found in ER Processed directory and DA directories. ###############################
#############################################################################################################

Function Test-LooseFile {
Param(
    [Parameter(ValueFromPipeline=$true)] $File
)

    Begin { }

    Process {

        $oFile = Get-FileObject($File)

        $result = $false
        If ( $oFile -ne $null ) {
            If ( Test-Path -LiteralPath $oFile.FullName -PathType Leaf ) {
                $result = $true

                $Context = $oFile.Directory
                $sContext = $Context.FullName

                If ( $Context | Test-ColdStoragePropsDirectory -NoPackageTest ) {
                    $result = $false
                }
                ElseIf ( Test-IndexedDirectory($sContext) ) {
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
                ElseIf ( $oFile | Test-InBaggedCopyContainerSubdirectory ) {
                    $result = $false
                }
                ElseIf ( Test-HiddenOrSystemFile($oFile) ) {
                    $result = $false
                }
            }

        }
    
        $result
    }

    End { }

}

Function Get-PathToBaggedCopyOfLooseFile {
    Param (
        [Switch]
        $FullName,

        [Switch]
        $Wildcard,

        $Timestamp=$null,

        [Parameter(ValueFromPipeline=$true)]
        $File
    )

    Begin { }

    Process {
        $Prefix = ""
        if ( $FullName ) {
            $Prefix = $File.Directory.FullName
            $Prefix = "${Prefix}\"
        }
        $FileName = $File.Name
        $FileName = ( $FileName -replace "[^A-Za-z0-9]", "_" )
        
        if ( $Wildcard ) {
            # 4 = YYYY, 2 = mm, 2 = dd, 2 = HH, 2 = MM, 2 = SS
            $Suffix = ( "[0-9]" * ( 4 + 2 + 2 + 2 + 2 + 2) )
        } else {
            $TS = $Timestamp
            If ( $TS -eq $null ) {
                $TS = ( Get-Date )
            }
            $DateStamp = ( $TS.ToString( "yyyyMMddHHmmss" ) )
            $Suffix = "${DateStamp}"
        }
        $Suffix = "_bagged_${Suffix}"

        "${Prefix}${FileName}${Suffix}"
    }

    End { }
}

Function Test-UnbaggedLooseFile {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $oFile = ( $File | Get-FileObject )
    
        $result = $false
        If ( -Not ( $oFile -eq $null ) ) {
            If ( $oFile | Test-LooseFile ) {
                $result = $true
                $bag = ( Get-BaggedCopyOfLooseFile -File $oFile )
                       
                if ( $bag.Count -gt 0 ) {
                    $result = $false
                }
            }
        }
    
        $result | Write-Output
    }

    End { }

}

Function Get-LooseFileOfBaggedCopy {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $Context=$null, [Int] $DiffLevel=0, [switch] $ShowWarnings=$false )

    Begin { $sContext = $( If ( $Context ) { $Context } Else { "Get-LooseFileOfBaggedCopy" } ) }

    Process {
		$Output = @{ }
        $oFile = Get-FileObject($File)
        If ( Test-BagItFormattedDirectory -File $oFile ) {
            $BagDir = $oFile.FullName
            $Payload = Get-ChildItem -LiteralPath ( $BagDir | Join-Path -ChildPath "data" ) -Force
            
            If ($Payload.Count -eq 1 -and ( Test-Path -LiteralPath $Payload.FullName -PathType Leaf ) ) {

                $oContainer = $oFile.Parent
                If ( $oContainer ) {
                    $Counterpart = $null
                    $BagContainers = ( Get-BaggedCopyContainerSubdirectories )
                    $BagContainers | ForEach-Object {
                        If ( '.' -eq $_ ) {
                            $sContainer = $oContainer.FullName
                        }
                        ElseIf ( $oContainer.Name -eq $_ ) {
                            $sContainer = $oContainer.Parent.FullName
                        }

                        $Counterpart = ( $sContainer | Join-Path -ChildPath $Payload.Name | Get-FileObject )

                        If ( $Counterpart ) {

                            # We found a viable counterpart. But let's give other tests a chance to disqualify it.
                            If ( $DiffLevel -gt 0 ) {

                                If ( Test-DifferentFileContent -From $Payload -To $Counterpart -DiffLevel $DiffLevel ) {
                                
                                    $Counterpart = $null

                                    If ( $ShowWarnings ) {
                                    
                                        ( "[$sContext] {0} bag payload {1} matches to a loose file's name, but contents differ!" -f $oFile.FullName,$Payload.Name ) | Write-Warning                                

                                    }

                                }
                                                        
                            }

                            If ( $Counterpart ) {
								If ( -Not $Output.Contains( $Counterpart.FullName ) ) {
									$Counterpart
									$Output[ $Counterpart.FullName ] = $Counterpart
								}
                            }
                        }
                    }

                    If ( ( $Counterpart -eq $null ) -and $ShowWarnings ) {

                        ( "[$sContext] {0} bag payload {1} does not match to a loose file." -f $oFile.FullName,$Payload.Name ) | Write-Warning

                    }

                }
                ElseIf ( $ShowWarnings ) {

                    ( "[$sContext] {0} bag does not have an identifiable parent directory." -f $oFile.FullName ) | Write-Warning
                
                }

            }
            ElseIf ( $ShowWarnings ) {

                ( "[$sContext] {0} payload contains more than one single file." -f $oFile.FullName ) | Write-Warning

            }
        }
        ElseIf ( $ShowWarnings ) {

            ( "[$sContext] {0} is not a bagged directory." -f $oFile.FullName ) | Write-Warning

        }
        
    }

    End { }
}

Function Add-BaggedCopyContainer {
    Param (
        [Parameter(ValueFromPipeline=$true)] $Path
    )

    Begin { $BagContainers = ( Get-BaggedCopyContainerSubdirectories -ExcludeDots ) }

    Process {
        
        If ( $Path -ne $null ) {

            $LiteralPath = ( $Path | Get-FileLiteralPath )
            
            $FoundContainers = ( $BagContainers |? { Test-Path -LiteralPath ( Join-Path $LiteralPath -ChildPath $_ ) } )
            If ( $FoundContainers.Count -gt 0 ) {
                $FoundContainers | Select-Object -First 1 |% { Get-Item -LiteralPath ( Join-Path $LiteralPath -ChildPath $_ ) -Force }
            }
            Else {
                $BagContainers | Select-Object -First 1 |% { New-Item -ItemType Directory -Path ( Join-Path $LiteralPath -ChildPath $_ ) } 
            }

        }

    }

    End { }
}

Function Get-BaggedCopyContainerSubdirectories {
    Param (
        [switch] $ExcludeDots=$false
    )

    If ( -Not $ExcludeDots ) {
        "." | Write-Output
    }

    ".bagged" | Write-Output

}

Function Test-InBaggedCopyContainerSubdirectory {
Param (
    [Parameter(ValueFromPipeline=$true)] $File=$null
)

    Begin {
        $BagContainers = ( Get-BaggedCopyContainerSubdirectories -ExcludeDots )
    }
    
    Process {
        If ( $File -ne $null ) {
            $Count = ( $File.FullName | Split-PathEntirely |? { $_ -in $BagContainers } )
            ( $Count.Count -gt 0 )
        }

    }

    End { }

}

Function Get-BaggedCopyOfLooseFile {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {

    $result = $null

    If ( Test-LooseFile($File) ) {
        $oFile = Get-FileObject($File)
        $Parent = $oFile.Directory
        
        $BagContainers = ( Get-BaggedCopyContainerSubdirectories )
        $BagContainers | ForEach-Object {
            $Wildcard = ( $oFile | Get-PathToBaggedCopyOfLooseFile -Wildcard )
            $Container = ( Join-Path $Parent.FullName -ChildPath $_ )

            If ( Test-Path -LiteralPath $Container -PathType Container ) {
                $match = ( Get-ChildItem -Directory $Container | Select-BaggedCopiesOfLooseFiles -Wildcard $Wildcard | Select-BaggedCopyMatchedToLooseFile -File $oFile )
                If ( $match.Count -gt 0 ) {
                    $result = $match
                }
            }
        }
    }

    $result

    }

    End { }

}

Function Test-BaggedCopyOfLooseFile {
Param ( [Parameter(ValueFromPipeline=$true)] $File, $Context = $null, $DiffLevel=0 )

    $result = $false # innocent until proven guilty

    $oFile = Get-FileObject -File $File
    If ( Test-BagItFormattedDirectory( $oFile ) ) {
        
        $LooseFile = ( $oFile | Get-LooseFileOfBaggedCopy -DiffLevel:$DiffLevel -Context:$Context )
        If ( $LooseFile ) {
            $result = $true
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

Function ConvertTo-321LooseFileFunctionFileReference {
Param( [Parameter(ValueFromPipeline=$true)] $Item, $Output )

    Begin { }

    Process {
        $Result = @( )

        If ( $Output -eq 'object' ) {
            $Result += @( $Item | Get-FileObject )
        }
        ElseIf ( $Output -eq 'literalpath' ) {
            $Result += @( $Item | Get-FileLiteralPath )
        }
        ElseIf ( $Item -is [string] ) {
            $Result += @( $Item )
        }
        Else {
            $Result += @( $Item | Get-FileLiteralPath )
        }

        $Result | Write-Output
    }

    End { }

}

Function Get-321LooseFileChecksumSidecarsContainers {
Param( [Parameter(ValueFromPipeline=$true)] $Item, $Output="string" )

    Begin { }

    Process {
        $o = ( $Item | Get-FileObject )
        
        $Name = $o.Name

        $Parent = ( $o | Get-ItemFileSystemParent )
        $ContainerNames = ( Get-BaggedCopyContainerSubdirectories )
            
        $Containers = ( $ContainerNames |% { $Parent.FullName | Join-Path -ChildPath $_ } | Sort-Object -Property:Length -Descending )

        $Containers | ConvertTo-321LooseFileFunctionFileReference -Output:$Output | Write-Output

    }

    End { }

}
Function Get-321LooseFileChecksumSidecarsContainer {
Param( [Parameter(ValueFromPipeline=$true)] $Item, $Algorithm='*', $Output="string", [switch] $Detect, [switch] $Create=$false )

    Begin { }

    Process {
        $Containers = ( $Item | Get-321LooseFileChecksumSidecarsContainers -Output:string )

        If ( $Detect ) {

            $Detected = ( $Containers |? { Test-Path -LiteralPath:$_ -PathType:Container } |? {
                Push-Location -LiteralPath:$_
                $WC = ( $Item | Get-321LooseFileChecksumSidecarFilesWildcard )
                Test-Path -Path:$WC -PathType:Leaf
                Pop-Location
            } )

            $N = ( $Detected | Measure-Object ).Count

            If ( $N -gt 0  ) {
                $Detected | Select-Object -First:1 |% { If ( $Output -eq 'object' ) { $_ | Get-FileObject } Else { $_ } } | Write-Output
            }
            ElseIf ( $Create ) {
                $Containers | Select-Object -First:1 |% {

                    If ( -Not ( Test-Path -LiteralPath:$_ -PathType:Container ) ) {
                        
                        New-Item -Path:$_ -ItemType:Directory |% {
                            '[{0}] Created NEW sidecar container directory "{1}"' -f ( Get-CSDebugContext -Function:$MyInvocation ), $_.FullName | Write-Verbose
                            If ( $Output -eq 'object' ) { $_ | Write-Output } Else { $_ | Get-FileLiteralPath | Write-Output }
                        }

                    }
                    Else {

                        Get-Item -LiteralPath:$_ -Force

                    }

                }
            }

        }
        Else {

            If ( $Create ) {
                $Containers | Select-Object -First:1 |% {
                
                    If ( -Not ( Test-Path -LiteralPath:$_ -PathType:Container ) ) {
                        New-Item -Path:$_ -ItemType:Directory |% { '[{0}] Created NEW sidecar container directory "{1}"' -f ( Get-CSDebugContext -Function:$MyInvocation ), $_.FullName | Write-Verbose }
                    }

                }
            }

            $Containers | Select-Object -First:1 | ConvertTo-321LooseFileFunctionFileReference -Output:$Output | Write-Output
        }

    }

    End { }
}
Function New-321LooseFileChecksumSidecarsContainer {
Param( [Parameter(ValueFromPipeline=$true)] $Item, $Output="object", [switch] $IfNotExists=$false )

    Begin { }

    Process {
        
        $o = @( )
        $Item | Get-321LooseFileChecksumSidecarsContainers -Output:"string" |% {

            If ( ( $o | Measure-Object ).Count -eq 0 ) {
            
                If ( Test-Path -LiteralPath:$_ -PathType:Container ) {

                    If ( $IfNotExists ) {

                        $o = @( $o ) + @( Get-Item -LiteralPath:$_ -Force )

                    }

                }
                Else {
                    $o = @( $o ) + @( New-Item -Path:$_ -ItemType:Directory )
                }

            }

        }
        $o | ConvertTo-321LooseFileFunctionFileReference -Output:$Output | Write-Output

    }

    End { }

}
Function Get-321LooseFileChecksumSidecarFilesWildcard {
Param( [Parameter(ValueFromPipeline=$true)] $Item, $Algorithm='*' )
    
    Begin { }

    Process {
        $Name = ( $Item | Get-FileObject ).Name
        $Name = ( $Name -replace '[\[\]]', '_' )

        "{0}.{1}" -f $Name, $Algorithm | Write-Output
    }

    End { }

}
Function Add-321LooseFileChecksumSidecarFile {
Param( [Parameter(ValueFromPipeline=$true)] $Item, $Algorithm='md5', $Value=$null, [switch] $Compute=$false, [switch] $Force=$false )

    Begin { }

    Process {
        $Container = ( $Item | Get-321LooseFileChecksumSidecarsContainer -Algorithm:$Algorithm -Detect -Create -Output:"object" )
        $SidecarName = ( $Item | Get-321LooseFileChecksumSidecarFilesWildcard -Algorithm:$Algorithm )

        $PayloadPath = ( "{0}/{1}" -f ( Get-BagItFormattedDirectoryPayload ), $Item.Name )

        $Checksum = $null
        If ( -Not $Compute ) {
            $Checksum = $Value
        }
        Else {
            $o = ( $Item | Get-FileObject )
            If ( $o ) {
                $ItemHash = ( Get-FileHash -LiteralPath:$o.FullName -Algorithm:$Algorithm )
            
                If ( $ItemHash ) {
                    $Checksum = $ItemHash.Hash
                }
                Else {
                    "[{0}] Get-FileHash({1}) on '{2}' failed!" -f ( Get-CSDebugContext -Function:$MyInvocation ), $Algorithm, $o.FullName | Write-Error
                }
            }
            Else {
                "[{0}] Get-FileObject on '{1}' failed!" -f ( Get-CSDebugContext -Function:$MyInvocation ), $Item | Write-Error
            }
        }

        $SidecarFile = ( $Container.FullName | Join-Path -ChildPath:$SidecarName )
        If ( $PayloadPath -and ( $Checksum -ne $null ) ) {
            If ( $Force -or ( -Not ( Test-Path -LiteralPath:$SidecarFile -PathType:Leaf ) ) ) {
                $Checksum = $Checksum.ToLower()
                "{0}  {1}" -f $Checksum, $PayloadPath | Out-File -Encoding:utf8 -LiteralPath:$SidecarFile
                "[{0}] sidecar file '{1}' added, contents: '{2}  {3}'" -f ( Get-CSDebugContext -Function:$MyInvocation ), $SidecarFile, $Checksum, $PayloadPath | Write-Verbose
            }
            Else {
                "[{0}] sidecar file '{1}' already exists; use -Force to overwrite" -f ( Get-CSDebugContext -Function:$MyInvocation ), $SidecarFile | Write-Verbose
            }
        }
        Else {
            "[{0}] PayloadPath='{1}', Checksum='{2}'. Use -Value to specify a checksum or -Compute to compute it" -f ( Get-CSDebugContext -Function:$MyInvocation ), $PayloadPath, $Checksum | Write-Warning
        }


    }

    End { }

}

Function Get-321LooseFileChecksumSidecarFile {
Param( [Parameter(ValueFromPipeline=$true)] $Item, $Algorithm='*', $Output='object' )

    Begin { }

    Process {
        $Container = ( $Item | Get-321LooseFileChecksumSidecarsContainer -Algorithm:$Algorithm -Detect -Output:"object" )

        $AlgoExclude = @( 'tag', 'json' )
        If ( $Algorithm.Count -eq 1 ) {
            $AlgoWC = $Algorithm
            $AlgoInclude = $null
        }
        Else {
            $AlgoWC = '*'
            $AlgoInclude = @( $Algorithm )
        }

        $SidecarName = ( $Item | Get-321LooseFileChecksumSidecarFilesWildcard -Algorithm:$AlgoWC )

        # Container will always be a LiteralPath which should be interpreted without wildcards. SidecarName may be a literal filename, or may be a wildcard
        $oo = @( )
        If ( $Container ) {
            Push-Location -LiteralPath:$Container.FullName
            If ( Test-Path -Path:$SidecarName -PathType:Leaf ) {
                $oo += @( Get-Item -Path:$SidecarName -Force )
            }
            Pop-Location
        }

        $oo |? {

            $File = $_

            $OK = ( $AlgoInclude -eq $null )
            If ( -Not $OK ) {

                $AlgoInclude |% {
                    $WC = ( '*.{0}' -f $_ )
                    "INCLUDE: {0} ({1} LIKE {2} :: {3})" -f $_, $File.Name, $WC, ( $File.Name -notlike $WC ) | Write-Debug
                    $OK = ( $OK -or ( $File.Name -like $WC ) )
                }

            }
            $OK | Write-Output

        } |? {

            $File = $_

            $OK = ( $AlgoExclude -eq $null )
            If ( -Not $OK ) {
                $OK = $true
                $AlgoExclude |% {
                    $WC = ( '*.{0}' -f $_ )
                    "EXCLUDE: {0} ({1} NOT LIKE {2} :: {3})" -f $_, $File.Name, $WC, ( $File.Name -notlike $WC ) | Write-Debug
                    $OK = ( $OK -and ( $File.Name -notlike $WC ) )
                }
            }
            $OK | Write-Output

        } | ConvertTo-321LooseFileFunctionFileReference -Output:$Output | Write-Output

    }

    End { }
}

Function Get-321LooseFileBagLocationTransient {
Param( [Parameter(ValueFromPipeline=$true)] $Item, $Output='string', [switch] $Slug=$false, [switch] $RelPath=$false )

    Begin { }

    Process {
    
            $Result = ( $Item | Get-FileObject | Get-ItemPackageMetadata -Name:"Bag-Directory" )
            If ( $Result -ne $null ) {
            
                If ( $Slug ) {
                    # NOOP
                }
                ElseIf ( $RelPath ) {
                    $Container = ( $Item | Get-321LooseFileChecksumSidecarsContainer -Output:"object" )
                    $Result = ( $Container.Name | Join-Path -ChildPath $Result )
                }
                Else {
                
                    $Container = ( $Item | Get-321LooseFileChecksumSidecarsContainer -Output:"string" )
                    $Result = ( $Container | Join-Path -ChildPath $Result )

                }

            }
            Else {

                "[{0}] Package '{1}' has no Item Package Metadata File ({2})" -f ( Get-CSDebugContext -Function:$MyInvocation ), ( $Item | Get-FileLiteralPath ), ( $Item | Get-ItemPackageMetadataFilePath ) | Write-Verbose

            }

            $Result | ConvertTo-321LooseFileFunctionFileReference -Output:$Output

    }

    End { }
}



#############################################################################################################
#############################################################################################################
#############################################################################################################

Function Test-BagItManifestFile {
Param( [Parameter(ValueFromPipeline=$true)] $File, $Bag )

    Begin {
        $Payload = ( $Bag | Select-BagItPayloadDirectory )
        $ExcludeRegex = ( "^([.]?bagged-[0-9]+|logs|manifest[.]html|package[.]json)$" )
    }

    Process {
        If ( $File ) {
            $IsPayload = ( $Payload -ne $null -and ( $File.Name -eq $Payload.Name ) )
            $IsExcluded = ( $File.Name -match $ExcludeRegex )
            $IsDirectory = ( Test-Path -LiteralPath $File.FullName -PathType Container )

            ( -Not ( $IsDirectory -or ( $IsPayload -or $IsExcluded ) ) ) | Write-Output
        }
    }

    End { }

}

Function New-BagItManifestContainer {
Param( [Parameter(ValueFromPipeline=$true)] $Bag, [switch] $WhatIf=$false )

    Begin { }

    Process {
        $oFile = ( $Bag | Get-FileObject | Get-ItemFileSystemLocation )

        # Let's check out the contents of the BagIt top-level directory for viable creation dates.
        $CreationTime = ( Get-ChildItem -LiteralPath $oFile.FullName |? { $_ | Test-BagItManifestFile -Bag:$oFile } |% { $_.CreationTime } ) | Sort-Object -Descending | Select-Object -First 1

        # If for any reason we don't have a creation time, fall back to the current time
        If ( $CreationTime.Count -eq 0 ) {
            $CreationTime = ( Get-Date )
        }

        # 1st, let's construct a short (date only) name for this path:
        $ContainerName = ( "bagged-{0}" -f ( $CreationTime.ToString("yyyyMMdd") ) )
        $Here = ( $oFile.FullName | Join-Path -ChildPath $ContainerName )
        $There = ( $oFile | Select-BagItPayloadDirectory | Get-FileLiteralPath | Join-Path -ChildPath $ContainerName )

        # 2nd, if there is a possible name collision in this directory or the payload directory, get more specific:
        If ( ( Test-Path -LiteralPath $Here ) -Or ( Test-Path -LiteralPath $There ) ) {
            $ContainerName = ( "bagged-{0}" -f ( $CreationTime.ToString("yyyyMMddHHmmss") ) )
            $Here = ( $oFile.FullName | Join-Path -ChildPath $ContainerName )
            $There = ( $oFile | Select-BagItPayloadDirectory | Get-FileLiteralPath | Join-Path -ChildPath $ContainerName )
        }

        # 3rd, create the container with New-Item and pass thru to output
        New-Item -Path $Here -ItemType Directory -WhatIf:$WhatIf | Write-Output
    }

    End { }

}

Function Undo-CSBagPackage {
Param ( [Parameter(ValueFromPipeline=$true)] $Package, [switch] $PassThru=$false )

    Begin { }

    Process {1
        $oFile = Get-FileObject($Package)
        If ( $oFile ) {

            If ( Test-BagItFormattedDirectory -File $oFile ) {
                
                $PayloadDirectory = ( $oFile | Select-BagItPayloadDirectory )
                If ( Test-BaggedCopyOfLooseFile -File $oFile -DiffLevel 2 ) {
                    
                    $LooseFile = Get-LooseFileOfBaggedCopy -File $oFile -DiffLevel:0

                    Remove-Item -LiteralPath $oFile.FullName -Recurse -Force

                    If ( $PassThru ) {
                        If ( Test-Path -LiteralPath $LooseFile.FullName ) {
                            $LooseFile | Write-Output
                        }
                    }

                }
                Else {

                    $oManifest = ( $oFile | New-BagItManifestContainer )

                    Get-ChildItem -LiteralPath $oFile -Force |? { $_.FullName -ne $PayloadDirectory.FullName } |% {
                        $BagItem = $_
                        If ( ( $BagItem.FullName -ne $oManifest.FullName ) -and ( -Not ( $BagItem.Name -like "bagged-*" ) ) ) {
                            # 1st pass - move to old manifest directory, if available...
                            If ( $oManifest -and ( Test-Path -LiteralPath $oManifest.FullName -PathType Container ) ) {
                                Move-Item -LiteralPath $_.FullName -Destination $oManifest.FullName
                            }
                            # ... or delete, if for some reason not available.
                            Else {
                                Remove-Item -LiteralPath $_.FullName
                            }
                        }

                    }

                    Get-ChildItem -LiteralPath $oFile -Force |% {
                        $BagItem = $_
                        If ( $BagItem.FullName -eq $PayloadDirectory.FullName ) {
                            # 2nd pass - empty payload contents into parent directory and remove data directory
                            Get-ChildItem -LiteralPath $BagItem.FullName |% {
                                Move-Item -LiteralPath $_.FullName -Destination $oFile -Force
                            }
                            Remove-Item -LiteralPath $BagItem.FullName -Force
                        }
                    }

                    If ( $PassThru ) {
                        $oFile | Write-Output
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

Function Add-ItemPackageMirrorData {
Param(
    [Parameter(ValueFromPipeline=$true)] $Package,
    [switch] $Force=$false,
    [switch] $PassThru=$false
)

    Begin { }

    Process {
        If ( $Package ) {

            $NotYetChecked = -Not ( [bool] $Package.CSPackageCheckedMirror )

            If ( $Force -or $NotYetChecked ) {
                $bMirrorCopy = $false
                $oMirrorCopy = $null
                $sMirrorCopy = $null

                # Is it mirrored at all?
                $cold = ( $File | Get-MirrorMatchedItem -ColdStorage )

                If ( $cold.Count -gt 0 ) {
                    $bMirrorCopy = ( Test-Path -LiteralPath $cold )
                    If ( $bMirrorCopy ) {
                        $oMirrorCopy = ( Get-Item -Force -LiteralPath $cold )
                        $sMirrorCopy = $oMirrorCopy.FullName
                    }
                }

                $Package | Add-Member -MemberType NoteProperty -Name "CSPackageMirrored" -Value $bMirrorCopy -Force
                $Package | Add-Member -MemberType NoteProperty -Name "CSPackageMirrorLocation" -Value $sMirrorCopy -Force
                $Package | Add-Member -MemberType NoteProperty -Name "CSPackageMirrorCopy" -Value $oMirrorCopy -Force

            }
        }

        If ( $PassThru ) {
            $Package | Write-Output
        }

    }

    End { }
}

Function Add-ItemPackageCloudCopyData {
Param(
    [Parameter(ValueFromPipeline=$true)] $Package,
    $CloudCopy=-1,
    [switch] $Force=$false,
    [switch] $PassThru=$false
)

    Begin { }

    Process {

        $NotYetChecked = -Not ( [bool] $Package.CSPackageCheckedCloud )

        If ( $CloudCopy -ne -1 ) {
            $oCloudCopy = [PSCustomObject] $CloudCopy

            $Package.CSPackageCheckedCloud = $true
            $Package | Add-Member -MemberType NoteProperty -Name "CSPackageCloudCopy" -Value $oCloudCopy -Force
            $Package | Add-Member -MemberType NoteProperty -Name "CloudCopy" -Value $oCloudCopy -Force
            
        }
        ElseIf ( $Force -or $NotYetChecked ) {
            $aZipped = $Package.CSPackageZip
            If ( $aZipped.Name ) {

                $oListing = ( $Package | Get-CloudStorageListing -All -Side:"local" -ReturnObject )
                $aListing = ( $oListing | Get-TablesMerged )
                    
                $aZipped |% {
                    $itemZipped = $_
                    $itemZippedName = ( $itemZipped.Name -replace "[.]json$","" )
                    $bCloudCopy = ( $bCloudCopy -or ( $aListing.ContainsKey( $itemZippedName ) ) )
                    If ( $aListing.ContainsKey( $itemZippedName ) ) {
                        $Copy = $aListing[ $itemZippedName ]
                        If ( $oCloudCopy -eq $null ) {
                            $oCloudCopy = $Copy
                        }
                        Else {
                            $oCloudCopy = @( $oCloudCopy ) + @( $Copy )
                        }
                    }
                }
            }

            $Package | Add-Member -MemberType NoteProperty -Name "CSPackageCloudCopy" -Value $oCloudCopy -Force
            $Package | Add-Member -MemberType NoteProperty -Name "CloudCopy" -Value $oCloudCopy -Force

        }

        If ( $PassThru ) {
            $Package | Write-Output
        }

    }

    End { }
}

Function Add-ItemPackageBagData {
Param(
    [Parameter(ValueFromPipeline=$true)] $Package,
    $Contents=@( ),
    $Sidecars=@( ),
    [switch] $Bagged=$false,
    $BagLocation=$null
)
    Begin { }

    Process {

        $mContents = ( $Contents | Measure-Object -Sum Length )
        #$mContents = ( $aContents |% { $File | Add-Member -MemberType NoteProperty -Name "CSFileSize" -Value ( 0 + ( $File | Select Length).Length ) } | Measure-Object -Sum CSFileSize )

        $Package | Add-Member -MemberType:NoteProperty -Name:"CSPackageSidecars" -Value:$Sidecars -Force
        $Package | Add-Member -MemberType:NoteProperty -Name:"CSPackageBagged" -Value:( [bool] $Bagged ) -Force
        $Package | Add-Member -MemberType:NoteProperty -Name:"CSPackageBagLocation" -Value:$BagLocation -Force
        $Package | Add-Member -MemberType:NoteProperty -Name:"CSPackageContents" -Value:$mContents.Count -Force
        $Package | Add-Member -MemberType:NoteProperty -Name:"CSPackageFileSize" -Value:$mContents.Sum -Force
    }

    End { }

}

Function Add-ItemPackageZipData {
Param(
    [Parameter(ValueFromPipeline=$true)] $Package,
    $Zip,
    [switch] $PassThru=$false
)

    Begin { }

    Process {
        $Package | Add-Member -MemberType:NoteProperty -Name:"CSPackageCheckedZipped" -Value:$true -Force
        $Package | Add-Member -MemberType:NoteProperty -Name:"CSPackageZip" -Value:$Zip -Force
        If ( $Zip -ne $null ) {
            $Package | Add-Member -MemberType:NoteProperty -Name:"CSPackageZipCanonical" -Value:( @( $Zip ) |% { Get-Item -LiteralPath:( $_ | ConvertTo-CSCanonicalPath ) } ) -Force
        }
        Else {
            $Package | Add-Member -MemberType:NoteProperty -Name:"CSPackageZipCanonical" -Value:( $null ) -Force
        }

        If ( $PassThru ) {
            $Package | Write-Output
        }
    }

    End { }

}


Function Test-CSNonpackagedItem {
Param (
    [Parameter(ValueFromPipeline=$true)] $File
)

    Begin { }

    Process {
    
        If ( $File -ne $null ) {
            $IsNonpackaged = $false

            If ( $File | Get-ItemFileSystemLocation | Test-ColdStorageRepositoryPropsDirectory ) {
                $IsNonpackaged = $true
                $IsNonpackaged | Add-Member -MemberType NoteProperty -Name CSNonpackagedReason -Value ( "Props directory: {0}" -f $File.FullName ) -Force
            }
            ElseIf ( $File | Get-ItemFileSystemLocation | Test-ColdStoragePropsDirectory -NoPackageTest ) {
                $IsNonpackaged = $true
                $IsNonpackaged | Add-Member -MemberType NoteProperty -Name CSNonpackagedReason -Value ( "Props directory: {0}" -f $File.FullName ) -Force
            }
            ElseIf ( ( Test-Path $File.FullName -PathType Container ) -and ( $File.Name -like '.metadata' ) ) {
                $IsNonpackaged = $true
                $IsNonpackaged | Add-Member -MemberType NoteProperty -Name CSNonpackagedReason -Value ( "Metadata directory: {0}" -f $File.FullName ) -Force
            }
            ElseIf ( Test-ZippedBag -LiteralPath $File.FullName ) {
                $IsNonpackaged = $true
                $IsNonpackaged | Add-Member -MemberType NoteProperty -Name CSNonpackagedReason -Value ( "Zipped bag: {0}" -f $File.FullName ) -Force
            }

            $IsNonpackaged | Write-Output

        }

    }

    End { }

}

Function Test-CSBaggedPackageItem {
Param (
    [Parameter(ValueFromPipeline=$true)] $File
)

    Begin { }

    Process {
        
        If ( $File -ne $null ) {

            $IsBaggedPackageItem = $false

            If ( Test-ERInstanceDirectory -File $File ) {
                $IsBaggedPackageItem = $true
            }
            ElseIf ( Test-BaggedIndexedDirectory -File $File ) {
                $IsBaggedPackageItem = $true
            }
            ElseIf ( Test-BagItFormattedDirectory -File $File ) {
                $IsBaggedPackageItem = $true
            }

            $IsBaggedPackageItem | Write-Output

        }

    }

    End { }
}

Function Get-CSPackageItemBagging {
Param (
    [Parameter(ValueFromPipeline=$true)] $File,
    [switch] $CheckZipped=$false
)

    Begin { }

    Process {

        If ( $File -ne $null ) {

            $aContents = @( )
            
            $bBagged = ( Test-BagItFormattedDirectory -File $File )
            $oBagLocation = $null

            If ( Test-ERInstanceDirectory -File $File ) {
                $aContents = ( @( $File ) + @( Get-ChildItem -Force -Recurse -LiteralPath $File.FullName ) )
            }
            ElseIf ( Test-BaggedIndexedDirectory -File $File ) {
                $aContents = ( @( $File ) + @( Get-ChildItem -Force -Recurse -LiteralPath $File.FullName ) )
            }
            ElseIf ( Test-BagItFormattedDirectory -File $File ) {
                $aContents = ( @( $File ) + @( Get-ChildItem -Force -Recurse -LiteralPath $File.FullName ) )
            }

            If ( $aContents.Count -gt 0 ) {
                If ( $bBagged ) {
                    $oBagLocation = $File
                    If ( $CheckZipped ) {
                        $aZipped = ( $File | Get-ZippedBagOfUnzippedBag -AllPossible )
                    }
                }
            }

            @{ "Bag"=$oBagLocation; "Contents"=$aContents; "Zip"=$aZipped } | Write-Output

        }

    }

    End { }
}

Function Add-ItemPackageContentsAndZip {
Param(
    [Parameter(ValueFromPipeline=$true)] $Package,
    [switch] $Bagged=$false,
    [switch] $CheckZipped=$false,
    $Contents=@( ),
    $Zip=$null,
    [switch] $PassThru=$false
)

    Begin { }

    Process {
        $Package | Add-Member -MemberType:NoteProperty -Name:CSIPCAZPackageContents -Value:$Contents -Force

        If ( ( $Bagged -and $CheckZipped ) -and ( $Zip -eq $null ) ) {
            $Zip = ( $Package | Get-ZippedBagOfUnzippedBag -AllPossible )
        }

        If ( $CheckZipped -and ( $Zip -ne $null ) ){
            $Package | Add-Member -MemberType:NoteProperty -Name:CSIPCAZPackageZip -Value:$Zip -Force
        }

        If ( $PassThru ) {
            $Package | Write-Output
        }
    }

    End { }

}

Function Get-ItemPackage {
Param (
    [Parameter(ValueFromPipeline=$true)] $Item,
    [switch] $At=$false,
    [switch] $Recurse=$false,
    [switch] $Ascend=$false,
    $AscendTop=$null,
	[switch] $Force=$false,
    [switch] $FromZip=$false,
    [switch] $CheckZipped=$false,
    [switch] $CheckMirrored=$false,
    [switch] $CheckCloud=$false,
    [switch] $ShowWarnings=$false,
    [switch] $Profile=$false,
    [switch] $Progress=$false
)

    Begin {
        If ( $Profile ) { $tN = @( Get-Date ) }
    }

    Process {
        If ( $Profile ) { $tN += , ( Get-Date ) }

        $File = ( $Item | Get-FileObject )

        If ( $FromZip ) {
            If ( $File | Get-Member -Name Bag ) {
                If ( $File | Get-Member -Name Zip ) {
                    $File = ( $File.Bag | Get-FileObject )
                }
            }
        }

        Write-Debug ( "Entered Get-ItemPackage: {0} -At:{1} -Recurse:{2} -Ascend:{3} -AscendTop:{4} -CheckZipped:{5} -ShowWarnings:{6}" -f $File.FullName, $At, $Recurse, $Ascend, $AscendTop, $CheckZipped, $ShowWarnings )

        If ( $Progress ) { Write-Progress -Id:( Get-CSItemPackageProgressId ) -Activity "Getting preservation packages" -Status $File.FullName }
        If ( $Profile ) { $tN += , ( Get-Date ) ; Write-Progress -Id:068 -Activity "Getting preservation packages" -Status:( "{0}: {1}" -f ( $tN[-1] - $tN[-2] ), $File.FullName ) }

        If ( ( $File.Name -eq "." ) -or ( $File.Name -eq ".." ) ) {
            Continue
        }

        $oFile = ( $File.FullName | Get-FileObject )
        If ( $oFile -ne $null ) {
            $oFile | Add-Member -MemberType:NoteProperty -Name:CSPackageContentFiles -Value:@( ) -Force
            $oFile | Add-Member -MemberType:NoteProperty -Name:CSPackageContentWarnings -Value:@( ) -Force
        }
        Else {
            If ( $File.FullName -ne $null ) {
                $diagFullName = $File.FullName
            }
            Else {
                $diagFullName = "${File}"
            }
            "[Get-ItemPackage] '{0}' came out of Get-FileObject as NULL!!" -f $diagFullName | Write-Warning
        }

        $Sidecars = @( )

        $nonpackaged = ( $File | Test-CSNonpackagedItem )
        If ( $nonpackaged ) {
            $oFile.CSPackageContentWarnings += @( "SKIPPED -- {0}" -f $nonpackaged.CSNonpackagedReason )
        }
        ElseIf ( Test-BaggedCopyOfLooseFile -File $File -DiffLevel 1 ) {

            If ( $At -and $Force ) {
				$oFile = ( $File | Get-LooseFileOfBaggedCopy | Get-ItemPackage -At:$At -Force:$Force -Recurse:$Recurse -Ascend:$Ascend -AscendTop:$AscendTop -CheckZipped:$CheckZipped -CheckMirrored:$CheckMirrored -CheckCloud:$CheckCloud )
			}
			ElseIf ( $Ascend ) {
                $oFile.CSPackageContentFiles = ( $File | Get-LooseFileOfBaggedCopy )
            }
            Else {
                $oFile.CSPackageContentWarnings += @( "SKIPPED -- BAGGED COPY OF LOOSE FILE: {0}" -f $File.FullName )
            }

            $oBagLocation = $File
            If ( $oBagLocation -and $CheckZipped ) {
                $aZipped = ( $oBagLocation | Get-ZippedBagOfUnzippedBag -AllPossible )
            }

        }
        ElseIf ( $File | Test-CSBaggedPackageItem ) {
            $t = ( $File | Get-CSPackageItemBagging -CheckZipped:$CheckZipped )
            $oFile.CSPackageContentFiles = @( $t['Contents'] )
            If ( $t[ 'Bag' ] ) {
                $oBagLocation = $t[ 'Bag' ]
                If ( $CheckZipped ) {
                    $aZipped = @( $t[ 'Zip' ] )                    
                }
            }

        }
        ElseIf ( Test-IndexedDirectory -File $File -UnbaggedOnly:$Ascend ) {
            $oFile.CSPackageContentFiles = @( $File ) + @( Get-ChildItem -Force -Recurse -LiteralPath $File.FullName )
        }
        ElseIf ( Test-LooseFile -File $File ) {
            
            $oBagLocation = ( Get-BaggedCopyOfLooseFile -File $File )
            $oFile.CSPackageContentFiles = @( $File )
            
            $Sidecars = ( $oFile | Get-321LooseFileChecksumSidecarFile -Algorithm:'*' )
            
            If ( $CheckZipped ) {
                If ( $oBagLocation ) {
                    $aZipped = ( $oBagLocation | Get-ZippedBagOfUnzippedBag -AllPossible )
                }
                ElseIf ( $Sidecars.Count -gt 0 ) {
                    
                    # The bagged directory version of this package exists only transiently, and a lot of code for sorting out zip file names
                    # depends on the assumption that the bagged directory version of the package currently exists. I don't want to recreate
                    # it on the fly nearly every time Get-ItemPackage is called on an unbundled loose file, so instead let's see if we can get
                    # a file recorded in the *,package.json metadata
                    "[{0}] Retrieving ZIP location from package metadata file" -f ( Get-CSDebugContext -Function:$MyInvocation ) | Write-Verbose
                    $metaLocationZip = ( $oFile | Get-ItemPackageMetadata -Name:"Location-Zip" )
                    If ( $metaLocationZip ) {
                        $Wildcards = ( $metaLocationZip |% { $Prefix = ( $_ -replace '[.]zip$','' ) ; ( "{0}*" -f $Prefix ) } | Sort-Object -Unique )
                        
                        $aZipped = ( $Wildcards |% {
                            $Parent = ( $_ | Split-Path -Parent )
                            $Wildcard = ( $_ | Split-Path -Leaf )

                            Push-Location -LiteralPath:$Parent
                            If ( Test-Path -Path:$Wildcard -PathType:Leaf ) {
                                Get-Item -Path:$Wildcard -Force
                            }
                            Pop-Location
                        } )
                    }

                }

            }

        }
        ElseIf ( $Recurse -and ( Test-Path -LiteralPath $File.FullName -PathType Container ) ) {
            ( "RECURSE INTO DIRECTORY: {0}" -f $File.FullName ) | Write-Verbose
            Get-ChildItemPackages -File $File.FullName -Recurse:$Recurse -CheckZipped:$CheckZipped -CheckCloud:$CheckCloud -CheckMirrored:$CheckMirrored -ShowWarnings:$ShowWarnings -Progress:$Progress
        }
        ElseIf ( $Ascend ) {
            $oFile.CSPackageContentWarnings += @( "RECURSE -- ASCEND FROM: {0}" -f $File.FullName )
        }
        Else {
            $oFile.CSPackageContentWarnings += @( "SKIPPED -- MISC: {0}" -f $File.FullName )
        }

        If ( $ShowWarnings ) {
            $oFile.CSPackageContentWarnings | Write-Warning
        }

        If ( $oFile.CSPackageContentFiles.Count -gt 0 ) {
            If ( $Profile ) { $tN += , ( Get-Date ) ; Write-Progress -Id:068 -Activity:"Getting preservation packages" -Status:( "{0}: Preparing return object: {1}" -f ( $tN[-1] - $tN[-2] ), $oFile.FullName ) }

            $Package = $oFile

            $oRepository = ( $oFile | Get-FileRepositoryLocation )
            
            $Package | Add-Member -MemberType:NoteProperty -Name:"CSPackageRepository" -Value:$oRepository -Force
            
            $sCanonicalLocation = ( $Package | ConvertTo-CSCanonicalPath )
            $Package | Add-Member -MemberType:NoteProperty -Name:"CSPackageCanonicalLocation" -Value:$sCanonicalLocation -Force

            $bBagged = $( If ( $oBagLocation ) { $true } Else { $false } )
            $Package | Add-ItemPackageBagData -Contents:$oFile.CSPackageContentFiles -Sidecars:$Sidecars -Bagged:$bBagged -BagLocation:$oBagLocation 

            $oCloudCopy = $null

            If ( $Profile ) { $tN += , ( Get-Date ) ; Write-Progress -Id:068 -Activity:"Getting preservation packages" -Status:( "{0}: Adding zip data to return object: {1}" -f ( $tN[-1] - $tN[-2] ), $oFile.FullName ) }
            
            If ( $CheckZipped ) {
                "[{0}] CheckZipped={1} ; Add-ItemPackageZipData -Zip:{2}" -f ( Get-CSDebugContext -Function:$MyInvocation ), $CheckZipped, ( '["{0}"]' -f ( ( $aZipped |% { $_.FullName } ) -join '", "' ) ) | Write-Debug
                $Package | Add-ItemPackageZipData -Zip:$aZipped
            }

            If ( $Profile ) { $tN += , ( Get-Date ) ; Write-Progress -Id:068 -Activity:"Getting preservation packages" -Status:( "{0}: Adding mirror data to return object: {1}" -f ( $tN[-1] - $tN[-2] ), $oFile.FullName ) }

            If ( $CheckMirrored ) {
                $Package | Add-ItemPackageMirrorData
            }

            If ( $Profile ) { $tN += , ( Get-Date ) ; Write-Progress -Id:068 -Activity:"Getting preservation packages" -Status:( "{0}: Adding cloud data to return object: {1}" -f ( $tN[-1] - $tN[-2] ), $oFile.FullName ) }

            If ( $CheckCloud ) {
                $Package | Add-ItemPackageCloudCopyData
            }

            $aPackageChecked = @{
                "Bagged"=( $Package.CSPackageCheckedBagged -or ( [bool] $true ) )
                "Mirrored"=( $Package.CSPackageCheckedMirrored -or ( [bool] $CheckMirrored ) )
                "Zipped"=( $Package.CSPackageCheckedZipped -or ( [bool] $CheckZipped ) )
                "Cloud"=( $Package.CSPackageCheckedCloud -or ( [bool] $CheckCloud ) )
            }

            $PackageChecked = ( $Package.CSPackageChecked )
            @( "Bagged", "Mirrored", "Zipped", "Cloud" ) | ForEach-Object {
                $CheckedPropertyName = ( "CSPackageChecked{0}" -f $_ )
                $Package | Add-Member -MemberType NoteProperty -Name:$CheckedPropertyName -Value:$aPackageChecked[ $_ ] -Force    
                If ( $aPackageChecked[ $_ ] ) {
                    $PackageChecked = @( $PackageChecked ) + @( "$_".ToLower() )
                }
            }
            $Package | Add-Member -MemberType NoteProperty -Name "CSPackageChecked" -Value:( $PackageChecked | Select-Object -Unique ) -Force

            If ( $Profile ) { $tN += , ( Get-Date ) ; Write-Progress -Id:068 -Activity:"Getting preservation packages" -Status:( "{0}: Outputting return object: {1}" -f ( $tN[-1] - $tN[-2] ), $Package.FullName ) }

            $Package | Write-Output
        }
        ElseIf ( $Ascend ) {
            $Parent = ( $File | Get-ItemFileSystemParent )

            If ( $Parent ) {                
                $Top = $( If ( $AscendTop ) { $AscendTop } Else { $File | Get-FileRepositoryLocation } )
                ( "ASCEND UP TO DIRECTORY: {0} -> {1} | {2}" -f $File.FullName,$Parent.FullName,$Top.FullName ) | Write-Verbose
                If ( $Parent.FullName -ne $Top.FullName ) {
                    $Parent | Get-ItemPackage -Ascend:$Ascend -AscendTop:$Top -CheckZipped:$CheckZipped -CheckMirrored:$CheckMirrored -CheckCloud:$CheckCloud -ShowWarnings:$ShowWarnings -Progress:$Progress
                }
            }
        }

        If ( $Profile ) { $tN += , ( Get-Date ) ; Write-Progress -Id:068 -Activity "Getting preservation packages" -Status:( "{0}: Exiting GetItemPackage" -f ( $tN[-1] - $tN[-2] ), $File.FullName ) }
        ( "Exited Get-ItemPackage: {0} -Recurse:{1} -Ascend:{2} -AscendTop:{3} -CheckZipped:{4} -ShowWarnings:{5}" -f $File.FullName, $Recurse, $Ascend, $AscendTop, $CheckZipped, $ShowWarnings ) | Write-Debug

    }

    End {
        If ( $Profile ) { $tN += , ( Get-Date ) ; Write-Progress -Id:068 -Activity "Getting preservation packages" -Status:( "DONE" ) -Completed }

    }
}

Function Get-ChildItemPackages {

Param (
    [Parameter(ValueFromPipeline=$true)] $File,
    [switch] $Recurse=$false,
    [switch] $At=$false,
    [switch] $CheckZipped=$false,
    [switch] $CheckMirrored=$false,
    [switch] $CheckCloud=$false,
    [switch] $ShowWarnings=$false,
    [switch] $Progress=$false
)

    Begin { If ( $Progress ) { Write-Progress -Id:( Get-CSItemPackageProgressId ) -Activity "Getting preservation packages" -Status "-" } }

    Process {

        $oFile = ( Get-FileObject -File $File )
        Write-Debug ( "Get-ChildItemPackages({0} -> {1})" -f $File, $oFile.Name )
        If ( $Progress ) { Write-Progress -Id:( Get-CSItemPackageProgressId ) -Activity "Getting preservation packages" -Status $oFile.FullName }

        If ( $oFile -eq $null ) {
            Write-Error ( "No such item: {0}" -f $File )
        }
        ElseIf ( $At -or ( Test-BagItFormattedDirectory -File $oFile ) ) {
            Get-Item -LiteralPath $oFile.FullName -Force | Get-ItemPackage -Recurse:$Recurse -CheckZipped:$CheckZipped -CheckMirrored:$CheckMirrored -CheckCloud:$CheckCloud -ShowWarnings:$ShowWarnings -Progress:$Progress

        }
        Else {

            Get-ChildItem -LiteralPath $oFile.FullName -Force | Get-ItemPackage -Recurse:$Recurse -CheckZipped:$CheckZipped -CheckMirrored:$CheckMirrored -CheckCloud:$CheckCloud -ShowWarnings:$ShowWarnings -Progress:$Progress

        }

    }

    End { If ( $Progress ) { Write-Progress -Id:( Get-CSItemPackageProgressId ) -Activity "Getting preservation packages" -Status "-" -Completed } }

}

Function Get-CSPackagePathRelativeToRepository {
Param( [Parameter(ValueFromPipeline=$true)] $Package )

    Begin { }

    Process {
        $oPackage = ( Get-FileObject -File $Package )
        $oRepository = ( Get-FileRepositoryProps -File $oPackage )
        If ( $oRepository ) {
            $oPackage.FullName | Resolve-PathRelativeTo -Base:$oRepository.Location | Write-Output
        }
    }

    End { }

}


Function ConvertTo-CSCanonicalPath {
Param( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {

        $oFile = ( $File | Get-FileObject )
        $sCanonicalLocation = $oFile.FullName

        $oRepositoryProps = ( $oFile | Get-FileRepositoryProps )
        If ( $oRepositoryProps ) {
            If ( $oRepositoryProps.Canonical ) {
                $sRelPath = ( $oFile | Get-CSPackagePathRelativeToRepository )
                $sCanonicalContainer = ( $oRepositoryProps.Canonical | ConvertTo-ColdStorageSettingsFilePath )
                $sCanonicalLocation = ( Join-Path $sCanonicalContainer -ChildPath:$sRelPath )
                $sCanonicalLocation = ( Get-Item -LiteralPath:$sCanonicalLocation -Force ).FullName
            }
        }
        
        $sCanonicalLocation | Write-Output

    }

    End { }

}

Function Get-ItemPackageMetadataDateTimeFormat {
    "yyyy-MM-ddTHH:mm:ss.ffffZ" | Write-Output
}
Function ConvertTo-ItemPackageMetadataDateTime {
Param ( [Parameter(ValueFromPipeline=$true)] $DateTime )

    Begin { }

    Process {
        $DateTime.ToUniversalTime().ToString( ( Get-ItemPackageMetadataDateTimeFormat ) )
    }

    End { }
}

Function Get-ItemPackageMetadataFilePath {
Param ( [Parameter(ValueFromPipeline=$true)] $Package )
    Begin { }

    Process {

        $pack = $Package
        If ( ( -Not ( $Package -is [object] ) ) -or ( -Not ( $Package | Get-Member -Name:CSPackageBagged ) ) ) {
            "[{0}] Bare path or file object piped in. Call Get-ItemPackage to secure packaging-convention metadata." -f ( Get-CSDebugContext -Function:$MyInvocation ) | Write-Debug
            $pack = ( $Package | Get-ItemPackage -At )
        }

        If ( $pack | Test-LooseFile ) {

            $SidecarLocation = ( $pack | Get-321LooseFileChecksumSidecarsContainer )
            If ( $SidecarLocation ) {
                $packName = ( $pack.Name -replace '[\[\]]','_' )
                Join-Path $SidecarLocation -ChildPath:( "{0}.package.json" -f $packName ) | Write-Output
            }

        }
        ElseIf ( $pack.CSPackageBagged ) {
        
            $BagLocation = ( $pack.CSPackageBagLocation )
            ( Join-Path $BagLocation.FullName -ChildPath "package.json" ) | Write-Output

        }
        
    }

    End { }
}

Function Get-ItemPackageMetadataFile {
Param ( [Parameter(ValueFromPipeline=$true)] $Package )

    Begin { }

    Process {
        $jsonFile = ( $Package | Get-ItemPackageMetadataFilePath )
        "JSON: {0}" -f $jsonFile|Write-Debug
        If ( $jsonFile -ne $null ) {

            "Test-Path -LiteralPath:{0} -PathType:Leaf :: {1}" -f $jsonFile, ( Test-Path -LiteralPath:$jsonFile -PathType:Leaf ) |Write-Debug
            If ( Test-Path -LiteralPath:$jsonFile -PathType:Leaf ) {
                Get-Item -LiteralPath $jsonFile -Force
            }

        }
        
    }

    End { }
}

Function New-ItemPackageMetadataFile {
Param ( [Parameter(ValueFromPipeline=$true)] $Package )

    Begin { }

    Process {
        $pack = $Package
        If ( ( -Not ( $Package -is [object] ) ) -or ( -Not ( $Package.CSPackageBagged ) ) ) {
            $pack = ( $Package | Get-ItemPackage -At )
        }

        $jsonFile = ( $pack | Get-ItemPackageMetadataFilePath )
        If ( $jsonFile -ne $null ) {

            If ( -Not ( Test-Path -LiteralPath $jsonFile -PathType Leaf ) ) {
                
                $jsonItem = ( New-Item -Path $jsonFile )
                If ( $jsonItem ) {
                    $sRepository = ( $pack | Get-ItemFileSystemParent ).FullName
                    If ( $pack | Get-Member -Name:CSPackageRepository ) {
                        If ( $pack.CSPackageRepository.FullName ) {
                            $sRepository = $pack.CSPackageRepository.FullName
                        }
                    }
                    Push-Location $sRepository
                    $sLocation = ( Resolve-Path $pack.FullName -Relative )
                    Pop-Location

                    $metadata = [ordered] @{
                        "Time-Documented"=( Get-Date ).ToUniversalTime().ToString( ( Get-ItemPackageMetadataDateTimeFormat ) ) ;
                        "User-Documented"=$env:USERNAME ;
                        "Host-Documented"=$env:COMPUTERNAME ;
                        "Repository"=$sRepository
                        "Location"=$sLocation
                    }
                    If ( $pack.FullName -ne $pack.CSPackageBagLocation.FullName ) {
                        $metadata["Location-Bag"] = ( $pack.CSPackageBagLocation.FullName )
                    }
                    [PSCustomObject] $metadata | ConvertTo-Json | Out-File $jsonItem.FullName -Encoding utf8

                    $jsonItem | Write-Output

                }

            }

        }
    }

    End { }

}

Function Get-ItemPackageMetadata {
Param ( [Parameter(ValueFromPipeline=$true)] $Package, $Name=$null )

    Begin { }

    Process {
        $jsonItem = ( $Package | Get-ItemPackageMetadataFile )
        If ( $jsonItem ) {
        
            $json = ( Get-Content -LiteralPath $jsonItem.FullName )
            $meta = ( $json | ConvertFrom-Json )

            If ( $meta ) {
                If ( $Name -ne $null ) {
                    If ( $meta | Get-Member -Name $Name ) {
                        $meta.$Name | Write-Output
                    }
                }
                Else {
                    $meta | Write-Output
                }

            }


        }

    }

    End { }

}

Function Add-ItemPackageMetadata {
Param ( [Parameter(ValueFromPipeline=$true)] $Package, $Name, $Value, [switch] $Append=$false, [switch] $Force=$false )

    Begin { }

    Process {
        $file = ( $Package | Get-ItemPackageMetadataFile )
        $meta = ( $Package | Get-ItemPackageMetadata )
        
        $dirty = $false
        If ( $meta | Get-Member -Name:$Name ) {
            
            If ( $Force ) {
                If ( $Append ) {
                    $meta.$Name = @( $meta.$Name ) + @( $Value )
                }
                Else {
                    $meta.$Name = $Value
                }
                $dirty = $true
            }

        }
        Else {
            $meta | Add-Member -MemberType:NoteProperty -Name:$Name -Value:$Value
            $dirty = $true
        }

        If ( $dirty ) {
            $meta | Add-Member -MemberType:NoteProperty -Name:"Time-MetaUpdated" -Value:( Get-Date ).ToUniversalTime().ToString( ( Get-ItemPackageMetadataDateTimeFormat ) ) -Force
            $meta | ConvertTo-Json | Out-File -Encoding:utf8 -LiteralPath:$file.FullName
        }

    }

    End { }

}

Function Remove-ItemPackageMetadata {
Param ( [Parameter(ValueFromPipeline=$true)] $Package, $Name=$null, [switch] $Force=$false )

    Begin { }

    Process {

        $file = ( $Package | Get-ItemPackageMetadataFile )

        If ( $Name -ne $null ) {
            $meta = ( $Package | Get-ItemPackageMetadata )
            $dirty_meta = $null
            If ( $meta | Get-Member -Name:$Name ) {
                $dirty_meta = ( $meta | Select-Object -Property:* -ExcludeProperty:$Name )
            }

            If ( $dirty_meta -ne $null ) {
                $dirty_meta | Add-Member -MemberType:NoteProperty -Name:"Time-MetaUpdated" -Value:( Get-Date ).ToUniversalTime().ToString( ( Get-ItemPackageMetadataDateTimeFormat ) ) -Force
                $dirty_meta | ConvertTo-Json | Out-File -Encoding:utf8 -LiteralPath:$file.FullName
            }

        }
        Else {
            # FIXME - NOOP
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

Function Add-ERInstanceData {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $PassThru=$false )

    Begin { }

    Process {
        $ERData = $null
        If ( Test-ERInstanceDirectory -File $File ) {
            $ERData = ( $File | Get-ERInstanceData )
        }
        $File | Add-Member -MemberType NoteProperty -Name CSPackageERMeta -Value $ERData -PassThru:$PassThru -Force
    }

    End { }
}

Function Get-ERInstanceData {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

Begin { }

Process {
    $BaseName = $File.Name
    
    $DirParts = $BaseName.Split("_")

    $ERMeta = [PSCustomObject] @{
        CURNAME=( $DirParts[0] )
        ERType=( $DirParts[1] )
        ERCreator=( $DirParts[2] )
        ERCreatorInstance=( $DirParts[3] )
        Slug=( $DirParts[4] )
    }
    $ERMeta | Add-Member -MemberType NoteProperty -Name ERCode -Value ( "{0}-{1}-{2}" -f $ERMeta.ERType, $ERMeta.ERCreator, $ERMeta.ERCreatorInstance )

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

    Begin { Push-Location; Set-Location -LiteralPath $RelativeTo }

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
Param( [Parameter(ValueFromPipeline=$true)] $Directory, [switch] $RelativeHref=$false, [switch] $Force=$false, [switch] $PassThru=$false, [string] $Context=$null )

    Begin { $MyCommand = $MyInvocation.MyCommand ; $sContext = $( If ( $Context ) { $Context } Else { $MyCommand } ) }

    Process {
        if ( $Directory -eq $null ) {
            $Path = ( Get-Location )
        } else {
            $Path = ( $Directory )
        }
        $UNC = ( Get-Item -Force -LiteralPath "${Path}" | Get-UNCPathResolved -ReturnObject )
        $indexHtmlPath = ( "${UNC}" | Join-Path -ChildPath "index.html" )

        If ( ( -Not $Force ) -And ( Test-MirrorMatchedItem -File "${Path}" -Reflection ) ) {

            $originalLocation = ( "${Path}" | Get-MirrorMatchedItem -Original )
            If ( Test-Path -LiteralPath "${originalLocation}" -PathType Container ) {
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
            Else {
                ( "[{0}] This seems to be a mirror-image location, but the expected original source location ({1}) does not exist!" -f $sContext,$originalLocation ) | Write-Warning
                ( "[{0}] Use the -Force flag to force index.html to be generated locally in this directory ({1})" -f $sContext,$Path ) | Write-Warning
            }

        }
        ElseIf ( Test-Path -LiteralPath "${Path}" ) {

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
                | Out-File -LiteralPath $indexHtmlPath -NoClobber:(-Not $Force) -Encoding utf8
                
            }
            Else {
                ( "[{0}] index.html already exists in {1}. To force index.html to be regenerated, use -Force flag." -f $sContext,$Directory ) | Write-Warning
            }
        }

        If ( Test-Path -LiteralPath "${indexHtmlPath}" -PathType Leaf ) {
            If ( $PassThru ) {
                "${indexHtmlPath}" | Get-FileObject | Get-ItemFileSystemLocation
            }
        }

    }

    End { }

}

Export-ModuleMember -Function Select-CSPackagesOKOrApproved
Export-ModuleMember -Function Select-CSPackagesOK
Export-ModuleMember -Function Test-IndexedDirectory
Export-ModuleMember -Function Test-BaggedIndexedDirectory
Export-ModuleMember -Function Test-ZippedBag
Export-ModuleMember -Function Select-ZippedBags
Export-ModuleMember -Function Get-ItemPackageZippedBag
Export-MOduleMember -Function Select-ZippedBagsContainers
Export-ModuleMember -Function Test-LooseFile
Export-ModuleMember -Function Test-UnbaggedLooseFile
Export-ModuleMember -Function Get-PathToBaggedCopyOfLooseFile
Export-ModuleMember -Function Get-BaggedCopyOfLooseFile
Export-ModuleMember -Function Get-LooseFileOfBaggedCopy
Export-ModuleMember -Function Test-BaggedCopyOfLooseFile
Export-ModuleMember -Function Select-BaggedCopiesOfLooseFiles
Export-ModuleMember -Function Select-BaggedCopyMatchedToLooseFile
Export-ModuleMember -Function Add-BaggedCopyContainer
Export-ModuleMember -Function Get-BaggedCopyContainerSubdirectories
Export-ModuleMember -Function ConvertTo-321LooseFileFunctionFileReference
Export-ModuleMember -Function Test-InBaggedCopyContainerSubdirectory
Export-ModuleMember -Function Get-321LooseFileChecksumSidecarsContainers
Export-ModuleMember -Function Get-321LooseFileChecksumSidecarsContainer
Export-ModuleMember -Function New-321LooseFileChecksumSidecarsContainer
Export-ModuleMember -Function Add-321LooseFileChecksumSidecarFile
Export-ModuleMember -Function Get-321LooseFileChecksumSidecarFile
Export-ModuleMember -Function Get-321LooseFileBagLocationTransient
Export-ModuleMember -Function Test-BagItManifestFile
Export-ModuleMEmber -Function New-BagItManifestContainer
Export-ModuleMember -Function Undo-CSBagPackage
Export-ModuleMember -Function Test-ERInstanceDirectory
Export-ModuleMember -Function Select-ERInstanceDirectories
Export-ModuleMember -Function Add-ERInstanceData
Export-ModuleMember -Function Get-ERInstanceData
Export-ModuleMember -Function Test-CSNonpackagedItem
Export-ModuleMember -Function Get-ItemPackage
Export-ModuleMember -Function Get-ChildItemPackages
Export-ModuleMember -Function ConvertTo-ItemPackageMetadataDateTime
Export-ModuleMember -Function Get-ItemPackageMetadataFilePath
Export-ModuleMember -Function Get-ItemPackageMetadataFile
Export-ModuleMember -Function New-ItemPackageMetadataFile
Export-ModuleMember -Function Get-ItemPackageMetadata
Export-ModuleMember -Function Add-ItemPackageMetadata
Export-ModuleMember -Function Remove-ItemPackageMetadata
Export-ModuleMember -Function ConvertTo-HTMLDocument
Export-ModuleMember -Function ConvertTo-HTMLList
Export-ModuleMember -Function ConvertTo-HTMLLink
Export-ModuleMember -Function Add-FileURI
Export-ModuleMember -Function Add-IndexHTML
Export-ModuleMember -Function Get-CSPackageItemBagging
Export-ModuleMember -Function Test-CSBaggedPackageItem
Export-ModuleMember -Function ConvertTo-CSCanonicalPath
Export-ModuleMember -Function Get-CSPackagePathRelativeToRepository
Export-ModuleMember -Function Add-ItemPackageCloudCopyData
Export-ModuleMember -Function Add-ItemPackageZipData
