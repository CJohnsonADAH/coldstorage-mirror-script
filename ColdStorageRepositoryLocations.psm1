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

$global:gRepoLocsModuleCmd = $MyInvocation.MyCommand

Import-Module -Verbose:$false  $( My-Script-Directory -Command $global:gRepoLocsModuleCmd -File "ColdStorageSettings.psm1" )
Import-Module -Verbose:$false  $( My-Script-Directory -Command $global:gRepoLocsModuleCmd -File "ColdStorageFiles.psm1" )

#############################################################################################################
## DATA #####################################################################################################
#############################################################################################################

$ColdStorageData = "\\ADAHColdStorage\ADAHDATA"
$ColdStorageDataER = "${ColdStorageData}\ElectronicRecords"
$ColdStorageDataDA = "${ColdStorageData}\Digitization"
$ColdStorageER = "\\ADAHColdStorage\ElectronicRecords"
$ColdStorageDA = "\\ADAHColdStorage\Digitization"
$ColdStorageBackup = "\\ADAHColdStorage\Share\ColdStorageMirroredBackup"

$global:gColdStorageMirrors = @{
    Processed=( "ER", "\\ADAHFS3\Data\Permanent", "${ColdStorageDataER}\Processed", "${ColdStorageDataER}\Processed" )
    Unprocessed=( "ER", "\\ADAHFS1\PermanentBackup\Unprocessed", "${ColdStorageDataER}\Unprocessed", "${ColdStorageDataER}\Unprocessed" )
    Working_ER=( "ER", "${ColdStorageDataER}\Working-Mirror", "\\ADAHFS3\Data\ArchivesDiv\PermanentWorking", "${ColdStorageDataER}\Working-Mirror" )
    Masters=( "DA", "${ColdStorageDataDA}\Masters", "\\ADAHFS3\Data\DigitalMasters", "${ColdStorageDataDA}\Masters" )
    Access=( "DA", "${ColdStorageDataDA}\Access", "\\ADAHFS3\Data\DigitalAccess", "${ColdStorageDataDA}\Access" )
    Working_DA=( "DA", "${ColdStorageDataDA}\Working-Mirror", "\\ADAHFS3\Data\DigitalWorking", "${ColdStorageDataDA}\Working-Mirror" )
}
$mirrors = $global:gColdStorageMirrors
$RepositoryAliases = @{
    Processed=( "${ColdStorageER}\Processed", "${ColdStorageDataER}\Processed" )
    Working_ER=( "${ColdStorageER}\Working-Mirror", "${ColdStorageDataER}\Working-Mirror" )
    Unprocessed=( "${ColdStorageER}\Unprocessed", "${ColdStorageDataER}\Unprocessed" )
    Masters=( "${ColdStorageDA}\Masters", "${ColdStorageDataDA}\Masters" )
    Access=( "${ColdStorageDA}\Access", "${ColdStorageDataDA}\Access" )
    Working_DA=( "${ColdStorageDA}\Working-Mirror", "${ColdStorageDataDA}\Working-Mirror" )
    
}

#############################################################################################################
## PUBLIC FUNCTIONS #########################################################################################
#############################################################################################################

Function Get-ColdStorageRepositories {
Param ( $Groups=@(), [Parameter(ValueFromPipeline=$true)] $Repository=$null, [switch] $Tag=$false )

    Begin { }

    Process {
        $out = $global:gColdStorageMirrors

        If ( $Groups.Count -ge 1 ) {
        # Filter according to groups
            $filteredOut = @{}
            $out.Keys |% { $Key = $_; $row = $out[$Key]; If ( $Groups -ieq $row[0] ) { Write-Debug ( "FILTERED IN: {0}" -f $Key ); $filteredOut[$Key] = $row } Else { Write-Debug ( "FILTERED OUT: {0}" -f $Key ) } }
            $out = $filteredOut
        }

        If ( $Tag ) {
            $filteredOut = @{}
            $out.Keys |% {
                $Key = $_
                $row = $out[$Key]
                $hLocations = @{
                    "Reflection"=$row[1];
                    "Original"=$row[2];
                    "ColdStorage"=$row[3];
                    "Trashcan"=( $Key | Get-ColdStorageTrashLocation )
                }
                $filteredOut[$Key] = [PSCustomObject] @{
                    "Collection"=$row[0];
                    "Locations"=[PSCustomObject] $hLocations
                }
            }
            $out = $filteredOut
        }

        If ( $Repository ) {
            $out = ( $out[$Repository] )
        }

        ( $out ) | Write-Output
    }

    End { }
}

Function Get-ColdStorageLocation {
Param ( [Parameter(ValueFromPipeline=$true)] $Repository, [switch] $ShowWarnings=$false )

    Process {
        If ( $Repository ) {
            If ( $mirrors.ContainsKey($Repository) ) {
                $aRepo = $mirrors[$Repository]

                If ( ( $aRepo[1] -Like "${ColdStorageER}\*" ) -Or ( $aRepo[1] -Like "${ColdStorageDA}\*" ) -Or ( $aRepo[1] -Like "${ColdStorageData}\*" ) ) {
                    $aRepo[1]
                }
                Else {
                    $aRepo[2]
                }
            }
            Else {
                $Mesg = ( "No such Repository: {0}" -f $Repository )
                If ( Test-Path -LiteralPath $Repository ) {
                    $FileType = $( If ( Test-Path -LiteralPath $Repository -PathType Container ) { "FOLDER" } Else { "FILE" } ) 
                    $Mesg = ( "{0} <-- THIS IS A {1} NAME, did you mean to use: -Items {2}` ?" -f $Mesg, $FileType, $Repository)
                }

                ( $Mesg ) | Write-Warning
            }
        }
        Else {
            ( "Repository name is empty." ) | Write-Warning
        }
    }

}

Function Get-ColdStorageZipLocation {
Param ( $Repository )

    $BaseDir = Get-ColdStorageLocation -Repository $Repository

    If ( Test-Path -LiteralPath "${BaseDir}\ZIP" ) {
        Get-Item -Force -LiteralPath "${BaseDir}\ZIP"
    }
}

Function Get-ColdStorageTrashLocation {
Param ( [Parameter(ValueFromPipeline=$true)] $Repository )

    Begin {
        $mirrors = ( Get-ColdStorageRepositories )
        
    }

    Process {
        If ( $Repository -ne $null ) {
            If ( $mirrors.ContainsKey($Repository) ) {
                $location = $mirrors[$Repository]
                $slug = $location[0]
            }
            Else {
                Write-Warning ( "Get-ColdStorageTrashLocation: Requested repository [{0}] does not exist." -f $Repository )
            }
        }
        Else {
            Write-Warning "Get-ColdStorageTrashLocation: no valid repository found (null Repository parameter)"
        }

        "${ColdStorageBackup}\${slug}_${Repository}"
    }

    End { }
}

Function Get-FileRepositoryCandidates {
Param ( $Key, [switch] $UNC=$false )

    $mirrors = ( Get-ColdStorageRepositories )

    $repo = $mirrors[$Key][1..2]
    $aliases = $RepositoryAliases[$Key]

    ( $repo + $aliases) |% {
        $sTestRepo = ( $_ ).ToString()
        If ( $oTestRepo = Get-FileObject -File $sTestRepo ) {

            $sTestRepo # > stdout

            If ( -Not ( $UNC ) ) {
                $sLocalTestRepo = ( $oTestRepo | Get-LocalPathFromUNC ).FullName
                If ( $sTestRepo.ToUpper() -ne $sLocalTestRepo.ToUpper() ) {
                    $sLocalTestRepo # > stdout
                }
            }

        }
    }

}

Function Get-FileRepository {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $Slug=$false )

Begin { $mirrors = ( Get-ColdStorageRepositories ) }

Process {
    
    # get self if $File is a directory, parent if it is a leaf node
    $oDir = ( Get-ItemFileSystemLocation $File | Get-UNCPathResolved -ReturnObject )

    $oRepos = ( $mirrors.Keys |% {
        $sKey = $_;
        $oCands = ( Get-FileRepositoryCandidates -Key $_ );

        If ($oCands -ieq $oDir.FullName) {

            If ($Slug) { $sKey }
            Else { $oDir.FullName }
    } } )

    $oRepos
    If ( ( $oRepos.Count -lt 1 ) -and ( $oDir.Parent ) ) {
        $oDir.Parent | Get-FileRepository -Slug:$Slug
    }

}

End { }

}

Function Get-ColdStorageRepositoryDirectoryProps {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $oFile = Get-FileObject($File)
        $sContainer = $oFile.FullName
        If ( Test-Path -LiteralPath "${sContainer}\.coldstorage" -PathType Container ) {
            Get-ChildItem -LiteralPath "${sContainer}\.coldstorage" |% {
                If ( $_.Name -like "*.json" ) {
                    $Source = $_
                    $Source | Get-Content | ConvertFrom-Json |
                        Add-Member -PassThru -MemberType NoteProperty -Name Location -Value $oFile |
                        Add-Member -PassThru -MemberType NoteProperty -Name SourceLocation -Value ( $Source.Directory ) |
                        Add-Member -PassThru -MemberType NoteProperty -Name Source -Value ( $Source )
                }
            }
        }
    }

    End { }
}

Function Get-FileRepositoryProps {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $oFile = Get-FileObject($File)
        
        $Parent = $( If ( $oFile.Directory ) { $oFile.Directory } ElseIf ( $oFile.Parent ) { $oFile.Parent } )
        
        $Props = ( $Parent | Get-FileRepositoryProps )
        If ( $Props ) {
            $Props
        }
        Else {
            ( $oFile | Get-ColdStorageRepositoryDirectoryProps )
        }

    }

    End { }

}

Function Get-FileRepositoryLocation {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $Props = ( $File | Get-FileRepositoryProps )
        If ( $Props ) {
            $Props.Location
        }
    }

    End { }
}

Function Get-FileRepositoryName {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $Props = ( $File | Get-FileRepositoryProps )
        If ( $Props ) {
            $Props.Repository
        }
    }

    End { }
}

Function Get-FileRepositoryPrefix {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $Props = ( $File | Get-FileRepositoryProps )
        If ( $Props ) {
            $Props.Prefix
        }
    }

    End { }
}

Function New-ColdStorageRepositoryDirectoryProps {
Param ( [Parameter(ValueFromPipeline=$true)] $Table, $File, [switch] $Force = $false )

    $Props = ( $File | Get-ColdStorageRepositoryDirectoryProps )
    If ( $Props -and -Not ( $Force ) ) {
        Write-Warning "[coldstorage settle] This is already settled as a repository directory."
        $Props | Write-Warning
    }
    Else {
        $oFile = Get-FileObject($File)

        $Parent = $oFile.FullName
        $csName = ".coldstorage"
        $csDir = "${Parent}\${csName}"
        If ( Test-Path -LiteralPath "${csDir}" -PathType Container ) {
            $PropsDir = ( Get-Item -Force -LiteralPath "${csDir}" )
        }
        Else {
            $PropsDir = ( New-Item -ItemType Directory -Path "${Parent}" -Name "${csName}" -Verbose )
        }

        If ( $PropsDir ) {
            $sPropsDir = $PropsDir.FullName
            $Table | ConvertTo-Json > "${sPropsDir}\props.json"
            Get-Content "${sPropsDir}\props.json"
        }
        Else {
            "[coldstorage settle] Could not locate or create a props directory" | Write-Warning
        }
    }
}

Function Test-ColdStoragePropsDirectory {
Param ( [Parameter(ValueFromPipeline=$true)] $File, [switch] $NoPackageTest=$false, [switch] $ShowWarnings=$false )

    Begin { }

    Process {
        $oFile = Get-FileObject($File)

        $result = $false
        If ( $oFile.Name -eq ".coldstorage" ) {
            $Packed = $( If ( $NoPackageTest ) { $null } Else { $oFile | Get-ItemPackage -Ascend -ShowWarnings:$ShowWarnings } )
            $result = ( -Not $Packed )
        }

        $result | Write-Output
    }

    End { }
}

Function Test-ColdStorageRepositoryPropsDirectory {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $oFile = Get-FileObject($File)

        $result = $false
        If ( $oFile.Name -eq ".coldstorage" ) {
            $Props = ( $oFile | Get-FileRepositoryProps )
            If ( $Props ) {

                If ( $oFile.FullName -eq $Props.SourceLocation.FullName ) {
                    $result = $true
                }

            }
        }

        $result | Write-Output
    }

    End { }
}

Function Test-ColdStorageRepositoryPropsFile {
Param ( [Parameter(ValueFromPipeline=$true)] $File )

    Begin { }

    Process {
        $oFile = Get-FileObject($File)
        
        $result = $false

        If ( $oFile.Directory ) {
            If ( $oFile.Directory.Name -eq ".coldstorage" ) {
                $Props = ( $oFile | Get-FileRepositoryProps )
                If ( $Props ) {

                    If ( $oFile.FullName -eq $Props.Source.FullName ) {
                        $result = $true
                    }
                }
            }
        }

        $result

    }

    End { }
}

#############################################################################################################
## PUBLIC FUNCTIONS: MIRRORED LOCATIONS #####################################################################
#############################################################################################################

Function Split-PathEntirely {
Param( [Parameter(ValueFromPipeline=$true)] $LiteralPath, [switch] $Resolve=$false )

    Begin { }

    Process {
        $sPath = $( If ( $LiteralPath -is [String] ) { $LiteralPath } Else { Get-FileLiteralPath($LiteralPath) } )

        $Parent = ( $LiteralPath | Split-Path -Parent -Resolve:$Resolve )
        $Child = ( $LiteralPath | Split-Path -Leaf -Resolve:$Resolve )

        If ( $Parent ) {
            $Parent = ( $Parent | Split-PathEntirely -Resolve:$Resolve)

            $Parent | Write-Output
        }
        $Child | Write-Output

    }

    End { }

}

Function Split-MirrorMatchedPath {
Param( [Parameter(ValueFromPipeline=$true)] $LiteralPath, $Props=$null, [switch] $Root=$false, [switch] $Stem=$false, [switch] $Canonicalize=$false, $Depth=0 )

    Begin {
        $Parts=@()
        If ( $Root ) {
            $Parts += , 0
        }
        If ( $Stem ) {
            $Parts += , 1
        }

        If ( $Parts.Count -eq 0 ) {
            $Parts += , 1
        }
    }

    Process {
        If ( $Props -eq $null ) {
            $Props = ( $LiteralPath | Get-FileRepositoryProps )
        }
        If ( $Props -ne $null ) {
            $RepositoryRoot = ( $Props.SourceLocation | Split-Path -Parent )
        }
        Else {
            $RepositoryRoot = $null
        }

        $sPath = Get-FileLiteralPath($LiteralPath)

        If ( $sPath -ine $RepositoryRoot ) {
            $sParent = ( $sPath | Split-Path -Parent )
            $sChild = ( $sPath | Split-Path -Leaf )
            If ( $Depth -eq 0 ) {
                "\ ${RepositoryRoot}" | Write-Debug
            }
            ( "{0} {1}" -f ("." * ($Depth+1)), $sChild ) | Write-Debug

            $Rest = @( $null, $sParent )
            If ( $sParent ) {
                If ( $sParent -ine $RepositoryRoot ) {
                    $Rest = ( $sParent | Split-MirrorMatchedPath -Root -Stem -Depth:($Depth+1) -Props:$Props -Canonicalize:$Canonicalize )
                }
                Else {
                    $Rest = @( $sParent, "." )
                }
            }
        
            $sStem = $sChild
            If ( $Rest.Count -gt 1 ) {
                If ( $Rest[1] -and ( $Rest[1] -ne "." ) ) {
                    $sStem = ( $Rest[1] | Join-Path -ChildPath $sChild )
                }
            }
            $Rest[1] = $sStem
        }
        Else {
            $Rest = @( $sPath, "." )
        }

        If ( $Rest[0] ) {
            If ( $Canonicalize ) {
                If ( $Props ) {
                    If ( $Props.Canonical ) {
                        $Rest[0] = ( $Props.Canonical | ConvertTo-ColdStorageSettingsFilePath )
                    }
                }
            }
        }

        $Rest[$Parts] | Write-Output
    }
}

Function Get-MirrorMatchedItem {
Param( [Parameter(ValueFromPipeline=$true)] $File, $Pair=$null, $In=@(), [switch] $Original=$false, [switch] $Reflection=$false, [switch] $ColdStorage=$false, [switch] $Trashcan=$false, [switch] $Self=$false, [switch] $All=$false, [switch] $IgnoreBagging=$false, $Repositories=$null )

Begin { $mirrors = ( Get-ColdStorageRepositories -Tag ) }

Process {
    
    $Range = $In
    $Implicit = $false
    If ( $Original ) { $Range += , "Original" }
    If ( $Reflection ) { $Range += , "Reflection" }
    If ( $ColdStorage ) { $Range += , "ColdStorage" }
    If ( $Trashcan ) { $Range += , "Trashcan" }

    If ( $Range.Count -eq 0 ) { $Range = ( "Original", "Reflection" ); $Implicit = $true }

    Write-Debug ( "[Get-MirrorMatchedItem] Match {0}" -f $( If ( $File -is [String] ) { $File } Else { $File.FullName } ) )
    $oRepository = ( $File | Get-FileRepositoryProps )
    If ( $Pair -eq $null ) {
        $Pair = ( $oRepository.Repository )
        If ( $Pair.Length -gt 0 ) {
            Write-Debug ( "* Adopted implicit Repository from item: {0}" -f ${Pair} )
        }
        Else  {
            Write-Warning ( "! Cannot determine a Repository from item: {0}" -f $File.FullName )
        }
    }

    # Split the path up; look for $Stock in list of mirrored repositories, then we can reattach $Stem
    $Stock, $Stem = ( $File | Split-MirrorMatchedPath -Root -Stem -Canonicalize )
    
    If ( $Stock -and $Pair ) {

        $Locations = $null
        If ( $mirrors.ContainsKey($Pair) ) {
            $Locations = $mirrors[$Pair].Locations
        }

        $Here = (
            $Locations | Get-Member -MemberType NoteProperty |% {
                $PropName = $_.Name
                $PropValue = $Locations.${PropName}
                If ( $PropValue -eq $Stock ) {
                    [PSCustomObject] @{ "Name"=$PropName; "Value"=$PropValue }
                }
            }
        )
        $There = (
            $Range |% {
                $PropName = $_
                $PropValue = $Locations.${PropName}
                $ItsMe = ( $PropValue -eq $Stock )

                # default = return only the requested locations in $Range that are alternative counterparts to the selected item; never the item itself
                # -Self = return only the requested locations in $Range that are the item itself, not alternative counterparts
                # -All = return all the requested locations in $Range, whether the item itself or alternative counterparts
                If ( ( -Not $Implicit ) -or ( $All ) -or ( $ItsMe -eq $Self ) ) {
                    [PSCustomObject] @{ "Name"=$PropName; "Value"=$PropValue }
                }
            }
        )

        $Container = ( Get-ItemFileSystemLocation $File | Get-UNCPathResolved -ReturnObject | Get-LocalPathFromUNC )

        $There |% {
            $Aspect = $_.Name
            $Location =  ( $_.Value | Get-UNCPathResolved -ReturnObject | Get-LocalPathFromUNC )

            # Simple Case -- do we have an alter at the exactly corresponding relative path?
            $ProspectivePath = ( $Location | Join-Path -ChildPath $Stem )

            $UseThis = $( If ( $IgnoreBagging ) { $true } Else { ( "Test-Path({0}): {1}" -f $Aspect, $ProspectivePath ) | Write-Debug ; Test-Path -LiteralPath $ProspectivePath } )
            If ( $UseThis ) {
                $ProspectivePath
            }
            Else {
                # Does not match directly. Check for bagging, etc.
                $sPossiblePath = $ProspectivePath

                $oParent = $Container.Parent
                If ( $oParent ) {
                    $oParent.FullName | Get-MirrorMatchedItem -Pair:$Pair -Repositories:$Repositories -In:@($Aspect) -All | ForEach-Object {
                        If ( $_.Length -gt 0 ) {
                            ( "PARENT MATCHED({0}): {1} -> {2}" -f $Aspect, $_, $Container.FullName ) | Write-Debug
                        
                            # Attempt to adjust around BagIt formatting:
                            # if known file is IN a bag, test for an alter OUTSIDE the bag
                            # if known file is OUTSIDE a bag, test for an alter IN a bag
                            # only use this to change the return value IF the alternative path exists
                            $oMirroredParent = ( Get-Item -Force -LiteralPath $_ )
                            $sMirroredParent = $oMirroredParent.FullName

                            $aProspectivePath = (( ( @($sMirroredParent) + $Container.RelativePath ) -ne $null ) -ne "" )
                            $sProspectivePath = ( $aProspectivePath -join "\" )

                            # Attempt to adjust around BagIt formatting:
                            # if known file is IN a bag, test for an alter OUTSIDE the bag
                            # if known file is OUTSIDE a bag, test for an alter IN a bag
                            # only use this to change the return value IF the alternative path exists
                            $Leaf = ( $aProspectivePath | Select-Object -Last 1 )
                            $Branch = ( $aProspectivePath | Select-Object -SkipLast 1 )

                            # Test for an alter INSIDE a bag
                            $AlternativePath = ( @($Branch) + @("data") + @($Leaf) )
                            $sAlternativePath = ( $AlternativePath -join "\" )

                            If ( Test-Path -LiteralPath "${sAlternativePath}" ) {
                                $sPossiblePath = $sAlternativePath
                            }

                            # If we are already in a bag, test for an alter OUTSIDE the bag
                            Else {
                            
                                $InData = ( $Leaf -eq "data" )
                                If ( $Branch.Count -gt 0 ) {
                                    $InData = ($InData -or ( $Branch[-1] -eq "data" ))
                                }

                                If ( $InData ) {
                                    If ( Test-BagItFormattedDirectory -File $oParent ) {
                                       
                                        $LeafFileName = ( $Container.RelativePath | Select-Object -Skip 1 )
                                        $AlternativePath = ( @($oMirroredParent) + @($LeafFileName) )
                                        $sAlternativePath = ( $AlternativePath -join "\" )
                                        
                                        ( "LEAF FILE NAME: {0}" -f "${LeafFileName}" ) | Write-Debug
                                        ( "PARENT PATH: {0}" -f $oMirroredParent.FullName ) | Write-Debug

                                        If ( Test-Path -LiteralPath "${sAlternativePath}" ) {
                                            $sPossiblePath = $sAlternativePath
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                $sPossiblePath | Write-Output
            }

        }
    }
    Else {
        $sFile = $File
        If ( -Not ( $File -is [String] ) ) {
            $sFile = Get-FileLiteralPath($File)
        }
        ( "[Get-MirrorMatchedItem] Does not appear to be in a mirrored location: {0}" -f $sFile ) | Write-Warning
    }

}

End { }

}

Function Test-MirrorMatchedItem {
Param( [Parameter(ValueFromPipeline=$true)] $File, $Pair, [switch] $Original=$false, [switch] $Reflection=$false, [switch] $ColdStorage=$false )

    Begin { }

    Process {
        # Is it mirrored at all?
        $images = ( $File | Get-MirrorMatchedItem -Pair:$Pair -All )

        If ( $images.Count -gt 1 ) {

            # If it is mirrored, then is it (a) the Original? (b) the Reflection? (c) the ColdStorage copy?
            $self = ( $File | Get-MirrorMatchedItem -Pair:$Pair -Self:$true )
            $alter = ( $File | Get-MirrorMatchedItem -Original:$Original -Reflection:$Reflection -ColdStorage:$ColdStorage -Pair:$Pair -All )

            # If $self is in the $alter set at least once, then we have a match.
            ( ( @($alter) -ieq $self ).Count -gt 0 )

        }
        Else {
            $false
        }
    }

    End { }
}

Export-ModuleMember -Function Get-ColdStorageRepositories
Export-ModuleMember -Function Get-ColdStorageLocation
Export-ModuleMember -Function Get-ColdStorageZipLocation
Export-ModuleMember -Function Get-ColdStorageTrashLocation
Export-ModuleMember -Function Get-FileRepository
Export-ModuleMember -Function Get-FileRepositoryName
Export-ModuleMember -Function Get-FileRepositoryPrefix
Export-ModuleMember -Function Get-FileRepositoryLocation
Export-ModuleMember -Function Get-FileRepositoryProps
Export-ModuleMember -Function Get-ColdStorageRepositoryDirectoryProps
Export-ModuleMember -Function New-ColdStorageRepositoryDirectoryProps
Export-ModuleMember -Function Test-ColdStoragePropsDirectory
Export-ModuleMember -Function Test-ColdStorageRepositoryPropsDirectory
Export-ModuleMember -Function Test-ColdStorageRepositoryPropsFile
Export-ModuleMember -Function Split-PathEntirely
Export-ModuleMember -Function Split-MirrorMatchedPath
Export-ModuleMember -Function Get-MirrorMatchedItem
Export-ModuleMember -Function Test-MirrorMatchedItem
